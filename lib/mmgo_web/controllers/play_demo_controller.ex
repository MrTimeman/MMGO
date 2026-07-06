defmodule MMGOWeb.PlayDemoController do
  use MMGOWeb, :controller

  alias MMGO.Play

  def start(conn, _params) do
    continue(conn, %{})
  end

  def new(conn, _params) do
    start_session(conn, &Play.start_new_local_session/0)
  end

  def continue(conn, _params) do
    start_session(conn, &Play.continue_local_session/0)
  end

  def reset(conn, _params) do
    case Play.reset_demo_session() do
      {:ok, %{challenger: challenger, opponent: opponent}} ->
        conn
        |> put_session(:demo_character_id, challenger.id)
        |> put_session(:demo_opponent_id, opponent.id)
        |> json(%{ok: true, character_id: challenger.id, opponent_id: opponent.id})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  defp start_session(conn, setup_fun) do
    case setup_fun.() do
      {:ok, %{challenger: challenger, opponent: opponent}} ->
        conn
        |> put_session(:demo_character_id, challenger.id)
        |> put_session(:demo_opponent_id, opponent.id)
        |> redirect(to: ~p"/map")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Play setup failed: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end
end
