defmodule MMGOWeb.PlayLiveTest do
  use MMGOWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MMGO.Worlds

  test "renders the MMGO-2 client-owned map shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#play-shell")
    assert has_element?(view, "#map-screen[phx-hook='Map']")
    assert has_element?(view, "#map-screen[data-map-src='/images/mmgo2-map.png']")
    assert has_element?(view, "#map-screen[data-state-path='/api/play/state']")
    assert has_element?(view, "#map-screen[data-journeys-path='/api/play/journeys']")
    assert has_element?(view, "#game-time-pill")
    refute has_element?(view, "#play-bottom-nav")
    refute has_element?(view, "#play-mode-switcher")
  end

  test "renders game surface routes with stable IDs", %{conn: conn} do
    seed_realm()

    {:ok, academy, _html} = live(conn, ~p"/academy")
    assert has_element?(academy, "#academy-screen")
    assert has_element?(academy, "#academy-schedule")

    {:ok, spells, _html} = live(conn, ~p"/spells")
    assert has_element?(spells, "#spell-list-screen")
    assert has_element?(spells, "#spell-new-link")

    {:ok, spell_new, _html} = live(conn, ~p"/spells/new")
    assert has_element?(spell_new, "#spell-circle-screen")
    assert has_element?(spell_new, "#spell-circle-hook[phx-hook='SpellCircle']")

    {:ok, base, _html} = live(conn, ~p"/base")
    assert has_element?(base, "#base-screen")
    assert has_element?(base, "#base-inventory")
    base |> element("#base-stats-tab") |> render_click()
    assert has_element?(base, "#base-stats")

    {:ok, grimoires, _html} = live(conn, ~p"/grimoires")
    assert has_element?(grimoires, "#grimoire-screen")
    assert has_element?(grimoires, "#grimoire-shelf-hook")
    assert has_element?(grimoires, ".grimoire-book")
    grimoires |> element("#grimoire-book-demo-chaos") |> render_click()
    assert has_element?(grimoires, "#grimoire-book-demo-chaos.is-selected")

    {:ok, combat, _html} = live(conn, ~p"/combat/demo")
    assert has_element?(combat, "#combat-screen")
    assert has_element?(combat, "#combat-action-spell")

    combat
    |> form("#combat-cast-form", cast: %{incantation: "Ictus ignis"})
    |> render_submit()

    assert has_element?(combat, "#combat-log .is-player")

    {:ok, operator, _html} = live(conn, ~p"/operator/map")
    assert has_element?(operator, "#operator-map-editor")
    assert has_element?(operator, "#operator-map-tools")
    assert has_element?(operator, "#operator-route-preview")
    assert has_element?(operator, "#operator-location-form")
    assert has_element?(operator, "#operator-route-form")
  end

  defp seed_realm do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "live-realm-#{System.unique_integer([:positive])}",
        name: "Live Realm",
        is_default: true
      })

    {:ok, _city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 1_000,
        y: 1_000,
        safe_zone: true
      })

    realm
  end
end
