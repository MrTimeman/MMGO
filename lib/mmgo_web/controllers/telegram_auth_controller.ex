defmodule MMGOWeb.TelegramAuthController do
  use MMGOWeb, :controller

  require Logger

  alias MMGO.Accounts
  alias MMGO.Play
  alias MMGO.Telegram.WebAppAuth

  def create(conn, %{"telegram_auth" => %{"init_data" => init_data}}) when is_binary(init_data) do
    authenticate(conn, init_data)
  end

  def create(conn, %{"init_data" => init_data}) when is_binary(init_data) do
    authenticate(conn, init_data)
  end

  def create(conn, _params), do: authentication_failed(conn)

  defp authenticate(conn, init_data) do
    case WebAppAuth.authenticate(init_data) do
      {:ok, telegram_user} ->
        provision_player(conn, telegram_user)

      {:error, reason} ->
        Logger.warning("Telegram Mini App authentication rejected: #{reason}")
        authentication_failed(conn)
    end
  end

  defp provision_player(conn, telegram_user) do
    case Accounts.provision_from_telegram(telegram_user) do
      {:ok, %{account: account, character: character}} ->
        open_player_session(conn, account, character)

      _reason ->
        Logger.error("Telegram player provisioning failed after valid authentication")
        authentication_failed(conn)
    end
  end

  defp open_player_session(conn, account, character) do
    case Play.ensure_character_usable(character) do
      {:ok, character} ->
        destination =
          if length(Accounts.list_characters_for_account(account.id)) > 1,
            do: ~p"/characters",
            else: ~p"/map"

        establish_session(conn, account.id, character.id, destination)

      {:error, :character_not_playable} ->
        case Accounts.get_active_migration_character_for_account(account.id) do
          {:ok, migration_character} ->
            establish_session(conn, account.id, migration_character.id, ~p"/realms")

          {:error, _reason} ->
            Logger.error("Telegram player has no usable or migrating profile")
            authentication_failed(conn)
        end

      {:error, _reason} ->
        Logger.error("Telegram player provisioning produced an unusable profile")
        authentication_failed(conn)
    end
  end

  defp establish_session(conn, account_id, character_id, destination) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:demo_character_id)
    |> delete_session(:demo_opponent_id)
    |> put_session(:current_account_id, account_id)
    |> put_session(:current_character_id, character_id)
    |> redirect(to: destination)
  end

  defp authentication_failed(conn) do
    conn
    |> put_flash(:error, "Подтверждение Telegram не удалось. Откройте игру из бота ещё раз.")
    |> redirect(to: ~p"/play")
  end
end
