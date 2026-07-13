defmodule MMGOWeb.TelegramAuthController do
  use MMGOWeb, :controller

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
    with {:ok, telegram_user} <- WebAppAuth.authenticate(init_data),
         {:ok, %{account: account, character: character}} <-
           Accounts.provision_from_telegram(telegram_user),
         {:ok, character} <- Play.ensure_character_usable(character) do
      conn
      |> configure_session(renew: true)
      |> delete_session(:demo_character_id)
      |> delete_session(:demo_opponent_id)
      |> put_session(:current_account_id, account.id)
      |> put_session(:current_character_id, character.id)
      |> redirect(to: ~p"/map")
    else
      _reason -> authentication_failed(conn)
    end
  end

  defp authentication_failed(conn) do
    conn
    |> put_flash(:error, "Подтверждение Telegram не удалось. Откройте игру из бота ещё раз.")
    |> redirect(to: ~p"/play")
  end
end
