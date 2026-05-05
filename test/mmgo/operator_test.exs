defmodule MMGO.OperatorTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Operator
  alias MMGO.Operator.AuditEvent
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 50,
        y: 50,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 1,
        risk_level: 10,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "operator_ration",
        name: "Operator Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "operator", "Operator")
    journey_character = character_fixture(realm, city, "journey-operator", "Journey Operator")

    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 5})
    {:ok, _journey_rations} = Inventory.grant_item(journey_character, ration_template, %{quantity: 5})

    %{
      realm: realm,
      city: city,
      tower: tower,
      route: route,
      character: character,
      journey_character: journey_character
    }
  end

  test "system_report/0 and realm_report/1 summarize world state", %{realm: realm} do
    report = Operator.system_report()
    assert report.realms == 1
    assert report.characters == 2
    assert report.locations == 2
    assert report.routes == 1

    assert {:ok, realm_report} = Operator.realm_report(realm.slug)
    assert realm_report.realm.slug == "canonical"
    assert realm_report.characters == 2
    assert realm_report.locations == 2
  end

  test "maintenance_sweep/1 completes due journeys and records an audit event", %{
    journey_character: journey_character,
    route: route
  } do
    {:ok, %{journey: journey}} =
      Travel.start_journey(journey_character, route, started_at: ~U[2026-03-27 12:00:00Z])

    now = ~U[2026-03-27 12:27:42Z]

    assert {:ok, %{summary: summary, audit_event: audit_event}} =
             Operator.maintenance_sweep(now: now, actor_handle: "operator")

    assert summary.completed_journeys == 1
    assert audit_event.action == "maintenance_sweep"
    assert Repo.aggregate(AuditEvent, :count, :id) == 1

    assert Travel.get_journey!(journey.id).status == :arrived
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
