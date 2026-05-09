defmodule MMGOWeb.PlayControllerTest do
  use MMGOWeb.ConnCase, async: true

  test "serves the MMGO hub on /play", %{conn: conn} do
    conn = get(conn, ~p"/play")
    html = html_response(conn, 200)

    assert html =~ "id=\"tab-duels\""
    assert html =~ "id=\"tab-dungeons\""
    assert html =~ "id=\"tab-spells\""
    assert html =~ "data-tab=\"dungeons\""
    assert html =~ "csrf-token"
    refute html =~ "window.__EDITOR_MODE = true"
  end

  test "serves the map editor on /play/editor", %{conn: conn} do
    conn = get(conn, ~p"/play/editor")
    html = html_response(conn, 200)

    assert html =~ "<div id=\"root\">"
    assert html =~ "window.__MAP_URL"
    assert html =~ "csrf-token"
    assert html =~ "window.__EDITOR_MODE = true"
  end
end
