defmodule MMGO.TravelSurvivalTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
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
        travel_days: 4,
        risk_level: 20,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "journey_ration",
        name: "Journey Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "traveler", "Traveler")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 8})

    %{
      realm: realm,
      city: city,
      tower: tower,
      route: route,
      character: character,
      ration_template: ration_template
    }
  end

  test "start_journey/3 consumes food and records load metrics", %{
    route: route,
    character: character,
    ration_template: ration_template
  } do
    assert {:ok, %{journey: journey}} =
             Travel.start_journey(character, route, started_at: ~U[2026-03-27 12:00:00Z])

    assert journey.travel_days == 4
    assert journey.food_units_consumed == 4
    assert journey.encumbrance_penalty_days == 0
    assert journey.carried_weight > 0
    assert journey.carry_capacity > 0

    ration_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: ration_template.id
      )

    assert ration_stack.quantity == 4
  end

  test "start_journey/3 rejects travel without enough food", %{
    route: route,
    realm: realm,
    city: city
  } do
    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "short_ration",
        name: "Short Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "hungry", "Hungry")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 2})

    assert {:error, changeset} = Travel.start_journey(character, route)

    assert %{nutrition_units: ["not enough food for the requested activity"]} =
             errors_on(changeset)
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
