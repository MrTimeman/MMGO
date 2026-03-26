defmodule MMGOWeb.TelegramWebhookController do
  use MMGOWeb, :controller

  alias MMGO.Telegram

  def create(conn, params) do
    secret = List.first(get_req_header(conn, "x-telegram-bot-api-secret-token"))

    with true <- Telegram.authorized_webhook_secret?(secret),
         {:ok, _result} <- Telegram.handle_update(params) do
      json(conn, %{ok: true})
    else
      false ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "unauthorized"})

      {:error, :invalid_update} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "invalid_update"})

      {:error, :default_realm_not_found} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, error: "default_realm_not_found"})

      {:error, operation, changeset, _changes_so_far} when is_atom(operation) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(operation), details: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
