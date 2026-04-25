defmodule MMGOWeb.PlayLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the MMGO-2 client-owned map shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#play-shell")
    assert has_element?(view, "#map-screen[phx-hook='Map']")
    assert has_element?(view, "#map-screen[data-map-src='/images/mmgo2-map.png']")
    refute has_element?(view, "#play-bottom-nav")
    refute has_element?(view, "#play-mode-switcher")
  end
end
