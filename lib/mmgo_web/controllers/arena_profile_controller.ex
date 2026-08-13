defmodule MMGOWeb.ArenaProfileController do
  use MMGOWeb, :controller

  alias MMGO.Arena

  def create(conn, %{"arena_profile" => attrs}) when is_map(attrs) do
    with account_id when is_binary(account_id) <- get_session(conn, :current_account_id),
         account <- MMGO.Accounts.get_account!(account_id),
         {:ok, profile} <- Arena.create_profile(account, attrs) do
      conn
      |> configure_session(renew: true)
      |> put_session(:current_account_id, account.id)
      |> put_session(:current_character_id, profile.character.id)
      |> put_session(:game_mode, "arena")
      |> put_flash(:info, "Профиль Арены готов. Испытайте свой первый гримуар.")
      |> redirect(to: ~p"/arena")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, changeset_message(changeset))
        |> redirect(to: ~p"/arena/new")

      _other ->
        conn
        |> put_flash(:error, "Не удалось создать профиль Арены.")
        |> redirect(to: ~p"/arena/new")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Сессия устарела. Войдите через Telegram ещё раз.")
      |> redirect(to: ~p"/play")
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Выберите имя и ровно три школы магии.")
    |> redirect(to: ~p"/arena/new")
  end

  @doc """
  Switches which of the account's arena profiles is being played.

  A player may keep several profiles for different school combinations. The
  profile is only ever chosen from the ones this account actually owns — the
  posted id is checked against them rather than trusted.
  """
  def switch(conn, %{"profile_id" => profile_id}) when is_binary(profile_id) do
    account_id = get_session(conn, :current_account_id)

    account_id
    |> Arena.list_profiles_for_account()
    |> Enum.find(&(&1.id == profile_id))
    |> case do
      nil ->
        conn
        |> put_flash(:error, "Этот профиль Арены вам не принадлежит.")
        |> redirect(to: ~p"/arena/profiles")

      profile ->
        conn
        |> put_session(:current_character_id, profile.character_id)
        |> put_session(:game_mode, "arena")
        |> put_flash(:info, "Вы играете за «#{profile.character.name}».")
        |> redirect(to: ~p"/arena")
    end
  end

  def switch(conn, _params) do
    conn
    |> put_flash(:error, "Выберите профиль Арены.")
    |> redirect(to: ~p"/arena/profiles")
  end

  defp changeset_message(changeset) do
    if Keyword.has_key?(changeset.errors, :schools) do
      "Для Арены нужны ровно три разные школы магии."
    else
      "Проверьте имя персонажа и выбранные школы."
    end
  end
end
