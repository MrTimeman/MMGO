defmodule MMGOWeb.GameModeController do
  use MMGOWeb, :controller

  alias MMGO.{Accounts, Arena, Play}
  alias MMGO.Accounts.CharacterProfiles

  def select(conn, %{"mode" => "world"}) do
    with account_id when is_binary(account_id) <- get_session(conn, :current_account_id) do
      open_world(conn, account_id)
    else
      _other -> mode_error(conn, "Сессия устарела. Войдите через Telegram ещё раз.")
    end
  end

  def select(conn, %{"mode" => "arena"}) do
    with account_id when is_binary(account_id) <- get_session(conn, :current_account_id),
         %Arena.Profile{} = profile <- Arena.get_profile_for_account(account_id),
         {:ok, character} <- Accounts.switch_character(account_id, profile.character_id) do
      conn
      |> renew_game_session(account_id, character.id, "arena")
      |> redirect(to: ~p"/arena")
    else
      nil -> redirect(conn, to: ~p"/arena/new")
      _other -> mode_error(conn, "Не удалось открыть профиль Арены.")
    end
  end

  def select(conn, _params), do: mode_error(conn, "Такого режима не существует.")

  defp world_character(account_id) do
    Accounts.get_default_world_character_for_account(account_id) ||
      account_id
      |> Accounts.list_characters_for_account()
      |> Enum.find(fn character ->
        character.status in [:active, :new, :frozen] and
          not CharacterProfiles.sealed_spirit?(character)
      end)
  end

  defp open_world(conn, account_id) do
    result =
      with %Accounts.Character{} = character <- world_character(account_id),
           {:ok, character} <- Accounts.switch_character(account_id, character.id),
           {:ok, character} <- Play.ensure_character_usable(character) do
        {:ok, character, world_destination(account_id)}
      end

    case result do
      {:ok, character, destination} ->
        conn
        |> renew_game_session(account_id, character.id, "world")
        |> redirect(to: destination)

      _other ->
        open_migration_or_error(conn, account_id)
    end
  end

  defp open_migration_or_error(conn, account_id) do
    case Accounts.get_active_migration_character_for_account(account_id) do
      {:ok, character} ->
        conn
        |> renew_game_session(account_id, character.id, "world")
        |> redirect(to: ~p"/realms")

      {:error, _reason} ->
        mode_error(conn, "Не удалось открыть персонажа общего мира.")
    end
  end

  defp world_destination(account_id) do
    if length(Accounts.list_characters_for_account(account_id)) > 1,
      do: ~p"/characters",
      else: ~p"/map"
  end

  defp renew_game_session(conn, account_id, character_id, mode) do
    conn
    |> configure_session(renew: true)
    |> put_session(:current_account_id, account_id)
    |> put_session(:current_character_id, character_id)
    |> put_session(:game_mode, mode)
  end

  defp mode_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/mode")
  end
end
