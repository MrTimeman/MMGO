defmodule MMGOWeb.GameEntryLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a safe Telegram entry state for a normal browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#game-entry-screen")
    assert has_element?(view, "#telegram-auth-root")
    assert has_element?(view, "#telegram-auth-form[phx-hook='TelegramAuth']")
    assert has_element?(view, "#telegram-auth-init-data[name='telegram_auth[init_data]']")
    assert has_element?(view, "#telegram-auth-normal-browser")
    assert has_element?(view, "#telegram-auth-open-bot[href*='t.me/mmgo_bot']")
  end
end
