defmodule MMGOWeb.PlayDemoController do
  use MMGOWeb, :controller

  alias MMGO.Play

  def start(conn, _params) do
    with_local_demo(conn, fn conn -> start_session(conn, &Play.continue_local_session/0) end)
  end

  def new(conn, _params) do
    with_local_demo(conn, fn conn -> start_session(conn, &Play.start_new_local_session/0) end)
  end

  def continue(conn, _params) do
    with_local_demo(conn, fn conn -> start_session(conn, &Play.continue_local_session/0) end)
  end

  def reset(conn, _params) do
    with_local_demo(conn, fn conn ->
      case Play.reset_demo_session() do
        {:ok, %{challenger: challenger, opponent: opponent}} ->
          conn
          |> put_demo_session(challenger, opponent)
          |> json(%{ok: true, character_id: challenger.id, opponent_id: opponent.id})

        {:error, _reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Не удалось сбросить демонстрационную игру."})
      end
    end)
  end

  defp start_session(conn, setup_fun) do
    case setup_fun.() do
      {:ok, %{challenger: challenger, opponent: opponent}} ->
        conn
        |> put_demo_session(challenger, opponent)
        |> redirect(to: ~p"/map")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Не удалось подготовить игру. Попробуйте ещё раз.")
        |> redirect(to: ~p"/")
    end
  end

  defp with_local_demo(conn, action) do
    if Application.get_env(:mmgo, :local_demo_enabled, false) == true do
      action.(conn)
    else
      send_resp(conn, :not_found, "Страница не найдена")
    end
  end

  defp put_demo_session(conn, challenger, opponent) do
    conn
    |> put_session(:demo_character_id, challenger.id)
    |> put_session(:demo_opponent_id, opponent.id)
    |> put_session(:current_account_id, challenger.account_id)
    |> put_session(:current_character_id, challenger.id)
  end
end
