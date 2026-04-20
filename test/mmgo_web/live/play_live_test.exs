defmodule MMGOWeb.PlayLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the live play shell with map tab and hook mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#play-shell")
    assert has_element?(view, "#play-nav-map")
    assert has_element?(view, "#play-hub-root[data-play-hub-root]")
    assert has_element?(view, "#map-night-toggle")
  end

  test "switches to the academy screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    view
    |> element("#play-nav-academy")
    |> render_click()

    view
    |> element("#academy-tab-clubs")
    |> render_click()

    assert has_element?(view, "#club-toggle-duel")
    refute has_element?(view, "#play-hub-root")
  end

  test "combat screen exposes action, target, and plan controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    view
    |> element("#play-nav-combat")
    |> render_click()

    assert has_element?(view, "#combat-action-spell")
    assert has_element?(view, "#combat-target-reaper")
    assert has_element?(view, "#combat-plan-cast")

    view
    |> element("#combat-target-goblin")
    |> render_click()

    view
    |> element("#combat-plan-retreat")
    |> render_click()

    assert has_element?(view, "#combat-selected-target", "Гоблин-вор")
    assert has_element?(view, "#combat-selected-plan", "Retreat")
  end
end
