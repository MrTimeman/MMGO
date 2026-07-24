defmodule MMGOWeb.SpellbookLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases.Base
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Travel.Journey
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, capital_city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    {:ok, the_tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 100,
        y: 100,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Tower Road",
        origin_location_id: capital_city.id,
        destination_location_id: the_tower.id,
        travel_days: 2,
        risk_level: 10,
        bidirectional: true
      })

    character = character_fixture(realm, capital_city, "spellcaster", "Spellcaster")
    base_spell = spell_fixture(character, "Ignis Prima", "Ignis Prima", :fire)

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Дорожный гримуар", capacity: 3, weight: 2})

    %{
      realm: realm,
      capital_city: capital_city,
      the_tower: the_tower,
      route: route,
      character: character,
      base_spell: base_spell,
      grimoire: grimoire
    }
  end

  test "unauthenticated visitors are redirected to /play", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/spellbook")
  end

  test "a character outside a Tower or owned base can read but not change the spellbook", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spellbook-screen")
    assert has_element?(view, "#spell-compose-locked")
    assert has_element?(view, "#spellbook-read-only-note")
    refute has_element?(view, "#spell-compose-form")
  end

  test "the composition form compiles an owned base spell at the Tower", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: base_spell
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spell-compose-form")
    assert has_element?(view, "#spell-compose-base")
    assert has_element?(view, "#spell-compose-school")
    assert has_element?(view, "#spell-compose-formula")
    assert has_element?(view, "#spell-compose-formula[maxlength='180']")

    view
    |> form("#spell-compose-form", %{
      "composition" => %{
        "base_spell_id" => base_spell.id,
        "school" => "fire",
        "formula" => "Ignis Radius"
      }
    })
    |> render_submit()

    compiled_spell =
      character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Ignis Radius"))

    assert compiled_spell.source_spell_id == base_spell.id
    assert has_element?(view, "#spell-compose-result-#{compiled_spell.id}")
    assert has_element?(view, "#spell-library-#{compiled_spell.id}")
  end

  test "an active owned base permits the same form outside the Tower", %{
    conn: conn,
    character: character,
    capital_city: capital_city
  } do
    create_active_base(character, capital_city)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spell-compose-form")
    assert has_element?(view, "#spellbook-location")
  end

  test "a travelling character can read but not change the spellbook", %{
    conn: conn,
    character: character,
    realm: realm,
    route: route,
    capital_city: capital_city,
    the_tower: the_tower
  } do
    create_active_journey(character, realm, route, capital_city, the_tower)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spell-compose-locked")
    assert has_element?(view, "#spellbook-read-only-note")
    refute has_element?(view, "#spell-compose-form")
  end

  test "a forged foreign base ID produces a server-rendered validation error", %{
    conn: conn,
    realm: realm,
    character: character,
    the_tower: the_tower
  } do
    foreign_character = character_fixture(realm, the_tower, "foreign-mage", "Foreign Mage")
    foreign_spell = spell_fixture(foreign_character, "Aqua Prima", "Aqua Prima", :water)
    character = move_to(character, the_tower)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    view
    |> form("#spell-compose-form")
    |> render_submit(%{
      "composition" => %{
        "base_spell_id" => foreign_spell.id,
        "school" => "fire",
        "formula" => "Ignis Radius"
      }
    })

    assert has_element?(view, "#spell-compose-error")
  end

  test "an invalid formula is shown as a server-rendered validation error", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: base_spell
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    view
    |> form("#spell-compose-form", %{
      "composition" => %{
        "base_spell_id" => base_spell.id,
        "school" => "fire",
        "formula" => "Ignis 123"
      }
    })
    |> render_submit()

    assert has_element?(view, "#spell-compose-error")
  end

  test "the player explicitly inscribes a selected spell and activates that grimoire", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: base_spell,
    grimoire: grimoire
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#grimoire-#{grimoire.id}")
    assert has_element?(view, "#grimoire-inscribe-#{grimoire.id}")

    view
    |> form("#grimoire-inscribe-form-#{grimoire.id}", %{
      "inscription" => %{"grimoire_id" => grimoire.id, "spell_id" => base_spell.id}
    })
    |> render_submit()

    assert Grimoires.spell_inscribed?(grimoire.id, base_spell.id)

    view
    |> element("#grimoire-activate-#{grimoire.id}")
    |> render_click()

    assert %{id: active_id} = Grimoires.active_grimoire_for_character(character.id)
    assert active_id == grimoire.id
  end

  defp session_conn(conn, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, character.account_id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  defp move_to(character, location) do
    character
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp create_active_base(character, location) do
    %Base{}
    |> Base.changeset(%{
      name: "#{location.name} Tower Room",
      kind: :city_purchase,
      status: :active,
      storage_weight_capacity: 250,
      owner_character_id: character.id,
      realm_id: character.realm_id,
      location_id: location.id,
      built_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp create_active_journey(character, realm, route, from_location, to_location) do
    started_at = DateTime.utc_now()

    %Journey{}
    |> Journey.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      route_id: route.id,
      from_location_id: from_location.id,
      to_location_id: to_location.id,
      status: :active,
      travel_days: 2,
      food_units_consumed: 0,
      encumbrance_penalty_days: 0,
      carried_weight: 0,
      carry_capacity: 100,
      started_at: started_at,
      arrival_at: DateTime.add(started_at, 86_400, :second),
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp spell_fixture(character, name, formula, school) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: name,
        formula: formula,
        school: school,
        description: "A stable spell for the spellbook fixture.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 10, variance: 1, duration: 0}
        ],
        failure_profile: %{difficulty: 10, base_success_rate: 85, partial_success_rate: 10}
      })

    spell
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
