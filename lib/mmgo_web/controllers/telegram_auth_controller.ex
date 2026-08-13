defmodule MMGOWeb.TelegramAuthController do
  use MMGOWeb, :controller

  require Logger

  alias MMGO.Accounts
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
        open_mode_selection(conn, account, character)

      {:error, operation, %Ecto.Changeset{} = changeset, _changes_so_far} ->
        # Field names and validation metadata only. The rejected values are the
        # player's Telegram profile and must stay out of the log.
        Logger.error(
          "Telegram player provisioning failed at #{inspect(operation)}: " <>
            inspect(
              Enum.map(changeset.errors, fn {field, {message, _opts}} -> {field, message} end)
            )
        )

        authentication_failed(conn)

      reason ->
        Logger.error("Telegram player provisioning failed: #{inspect(reason)}")
        authentication_failed(conn)
    end
  end

  defp open_mode_selection(conn, account, character) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:demo_character_id)
    |> delete_session(:demo_opponent_id)
    |> delete_session(:game_mode)
    |> put_session(:current_account_id, account.id)
    |> put_session(:current_character_id, character.id)
    |> redirect(to: ~p"/mode")
  end

  defp authentication_failed(conn) do
    conn
    |> put_flash(:error, "Подтверждение Telegram не удалось. Откройте игру из бота ещё раз.")
    |> redirect(to: ~p"/play")
  end
end
