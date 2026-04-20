defmodule MMGOWeb.PlayDemoController do
  use MMGOWeb, :controller

  alias MMGO.Play
  alias MMGOWeb.PlaySession

  def reset(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, reset_character} <- Play.reset_demo(character),
         {:ok, state} <- Play.map_state(reset_character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
