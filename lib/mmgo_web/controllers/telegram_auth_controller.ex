defmodule MMGOWeb.TelegramAuthController do
  use MMGOWeb, :controller

  alias MMGO.Accounts
  alias MMGO.Telegram.WebApp

  @session_key :play_character_id

  def create(conn, %{"initData" => init_data}) do
    bot_token = config()[:bot_token]

    if is_nil(bot_token) or bot_token == "" do
      conn
      |> put_status(:service_unavailable)
      |> json(%{ok: false, error: "bot_not_configured"})
    else
      case WebApp.validate_init_data(init_data, bot_token) do
        {:ok, user} ->
          case Accounts.provision_from_telegram(user) do
            {:ok, %{character: character}} ->
              conn
              |> put_session(@session_key, character.id)
              |> json(%{ok: true, character_id: character.id})

            {:error, :default_realm_not_found} ->
              conn
              |> put_status(:service_unavailable)
              |> json(%{ok: false, error: "no_default_realm"})

            {:error, _op, changeset, _changes} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: "validation_failed", details: format_errors(changeset)})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: to_string(reason)})
          end

        {:error, reason} ->
          conn
          |> put_status(:unauthorized)
          |> json(%{ok: false, error: to_string(reason)})
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "initData_required"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp config do
    Application.get_env(:mmgo, MMGO.Telegram, [])
  end
end
