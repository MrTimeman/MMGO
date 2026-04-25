defmodule MMGOWeb.PlayApiController do
  use MMGOWeb, :controller

  alias MMGO.Play
  alias MMGOWeb.PlaySession

  def state(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, state} <- Play.map_state(character) do
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

  def create_journey(conn, %{"route_id" => route_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _result} <- Play.start_journey(character, route_id),
         {:ok, state} <- Play.map_state(character) do
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

  def create_journey(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: "validation_failed",
      details: %{"route_id" => ["route_id is required"]}
    })
  end

  def cast_utility_spell(conn, %{"spell_id" => spell_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _spell} <- Play.cast_utility_spell(character, spell_id),
         {:ok, state} <- Play.map_state(character) do
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

  def cast_utility_spell(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: "validation_failed",
      details: %{"spell_id" => ["spell_id is required"]}
    })
  end

  def fast_arrive(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, arrived_character} <- Play.fast_arrive(character),
         {:ok, state} <- Play.map_state(arrived_character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, :no_active_journey} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "no active journey"})

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
