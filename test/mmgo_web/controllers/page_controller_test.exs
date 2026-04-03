defmodule MMGOWeb.PageControllerTest do
  use MMGOWeb.ConnCase

  test "GET /bootstrap", %{conn: conn} do
    conn = get(conn, ~p"/bootstrap")
    assert html_response(conn, 200) =~ "Ministry of MaGic Online starts here"
  end
end
