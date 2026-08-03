defmodule MMGOWeb.CharacterController do
  use MMGOWeb, :controller

  alias MMGO.Accounts
  alias MMGO.Play
  alias MMGOWeb.GameAuth

  def index(conn, _params) do
    with account_id when is_binary(account_id) <- get_session(conn, :current_account_id),
         account <- Accounts.get_account!(account_id) do
      characters = Accounts.list_characters_for_account(account.id)
      active_migration_character_ids = Accounts.list_active_migration_character_ids(account.id)

      current_scope =
        case GameAuth.current_scope(session_scope(conn)) do
          {:ok, scope} -> scope
          {:error, _reason} -> nil
        end

      render(conn, :index,
        page_title: "Выбор персонажа",
        account: account,
        current_scope: current_scope,
        current_character_id: get_session(conn, :current_character_id),
        blocked_character_ids: blocked_character_ids(characters, active_migration_character_ids),
        realm_groups: group_by_realm(characters)
      )
    else
      _other ->
        conn
        |> put_flash(:error, "Сначала подтвердите вход через Telegram.")
        |> redirect(to: ~p"/play")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Сессия устарела. Войдите через Telegram ещё раз.")
      |> redirect(to: ~p"/play")
  end

  def select(conn, %{"id" => character_id}) do
    with account_id when is_binary(account_id) <- get_session(conn, :current_account_id),
         {:ok, character} <- Accounts.switch_character(account_id, character_id),
         {:ok, character} <- Play.ensure_character_usable(character) do
      conn
      |> configure_session(renew: true)
      |> put_session(:current_account_id, account_id)
      |> put_session(:current_character_id, character.id)
      |> put_flash(:info, "Теперь вы играете за #{character.name}.")
      |> redirect(to: ~p"/map")
    else
      {:error, :migration_in_progress} ->
        conn
        |> put_flash(:error, "Этот персонаж заморожен переходом между мирами.")
        |> redirect(to: ~p"/characters")

      {:error, :not_playable} ->
        conn
        |> put_flash(:error, "Этот профиль пока нельзя открыть.")
        |> redirect(to: ~p"/characters")

      _other ->
        conn
        |> put_flash(:error, "Не удалось выбрать персонажа.")
        |> redirect(to: ~p"/characters")
    end
  end

  defp session_scope(conn) do
    %{
      "current_account_id" => get_session(conn, :current_account_id),
      "current_character_id" => get_session(conn, :current_character_id)
    }
  end

  defp group_by_realm(characters) do
    characters
    |> Enum.group_by(& &1.realm_id)
    |> Enum.map(fn {_realm_id, realm_characters} ->
      %{realm: hd(realm_characters).realm, characters: realm_characters}
    end)
    |> Enum.sort_by(& &1.realm.name)
  end

  defp blocked_character_ids(_characters, []), do: MapSet.new()

  defp blocked_character_ids(characters, _active_migration_character_ids) do
    characters
    |> Enum.reject(&(&1.status == :active))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end
end
