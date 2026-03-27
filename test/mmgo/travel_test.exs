defmodule MMGO.TravelTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Travel.{Clock, CompleteJourneyWorker, Journey}
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 220,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 20,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "travel_ration",
        name: "Travel Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "traveler", "Traveler")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    %{
      realm: realm,
      city: city,
      tower: tower,
      route: route,
      character: character,
      ration_template: ration_template
    }
  end

  test "start_journey/3 creates an active journey and enqueues completion", %{
    route: route,
    character: character,
    city: city,
    tower: tower,
    ration_template: ration_template
  } do
    started_at = ~U[2026-03-27 12:00:00Z]

    assert {:ok, %{journey: journey, job: job}} =
             Travel.start_journey(character, route, started_at: started_at)

    assert journey.status == :active
    assert journey.from_location_id == city.id
    assert journey.to_location_id == tower.id
    assert journey.food_units_consumed == 10

    assert DateTime.compare(journey.arrival_at, Clock.arrival_at(started_at, route.travel_days)) ==
             :eq

    assert job.args == %{"journey_id" => journey.id}

    oban_job = Repo.get!(Oban.Job, job.id)
    assert oban_job.worker == "MMGO.Travel.CompleteJourneyWorker"
    assert Travel.active_journey(character.id).id == journey.id

    ration_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: ration_template.id
      )

    assert ration_stack.quantity == 10
  end

  test "start_journey/3 rejects characters with an existing active journey", %{
    route: route,
    character: character
  } do
    assert {:ok, _result} = Travel.start_journey(character, route)

    assert {:error, changeset} = Travel.start_journey(character, route)
    assert %{status: ["character already has an active journey"]} = errors_on(changeset)
  end

  test "start_journey/3 supports reverse travel on bidirectional routes", %{
    realm: realm,
    route: route,
    tower: tower,
    city: city
  } do
    character = character_fixture(realm, tower, "returner", "Returner")
    {:ok, _rations} = Inventory.grant_item(character, ration_template_fixture(), %{quantity: 20})

    assert {:ok, %{journey: journey}} = Travel.start_journey(character, route)
    assert journey.from_location_id == tower.id
    assert journey.to_location_id == city.id
  end

  test "complete_journey_by_id/2 moves the character to the destination", %{
    route: route,
    character: character,
    tower: tower
  } do
    {:ok, %{journey: journey}} =
      Travel.start_journey(character, route, started_at: ~U[2026-03-27 12:00:00Z])

    assert {:ok, %{journey: completed_journey, character: updated_character}} =
             Travel.complete_journey_by_id(journey.id, now: journey.arrival_at, force: true)

    assert completed_journey.status == :arrived
    assert updated_character.current_location_id == tower.id
  end

  test "worker completes due journeys", %{route: route, character: character, tower: tower} do
    {:ok, %{journey: journey}} =
      Travel.start_journey(character, route, started_at: ~U[2026-03-27 12:00:00Z])

    assert :ok = CompleteJourneyWorker.perform(%Oban.Job{args: %{"journey_id" => journey.id}})

    updated_journey = Repo.get!(Journey, journey.id)
    updated_character = Repo.get!(Character, character.id)

    assert updated_journey.status == :arrived
    assert updated_character.current_location_id == tower.id
  end

  test "start_journey/3 rejects routes disconnected from current location", %{
    realm: realm,
    route: route,
    tower: tower
  } do
    wilderness =
      character_fixture(realm, tower, "towerling", "Towerling")
      |> Character.travel_changeset(%{current_location_id: nil})
      |> Repo.update!()

    assert {:error, changeset} = Travel.start_journey(wilderness, route)

    assert %{route_id: ["character must be placed at a location before travelling"]} =
             errors_on(changeset)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp ration_template_fixture do
    Repo.get_by!(Inventory.ItemTemplate, code: "travel_ration")
  end
end
