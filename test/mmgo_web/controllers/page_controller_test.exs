defmodule MMGOWeb.PageControllerTest do
  use MMGOWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Министерство"
    assert html =~ "Получить пропуск в Telegram"
  end
end
