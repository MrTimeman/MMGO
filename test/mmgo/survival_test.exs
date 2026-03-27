defmodule MMGO.SurvivalTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Survival
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "camp",
        name: "Camp",
        kind: :wilderness,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "ration",
        name: "Ration",
        item_type: :food,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "ore_chunk",
        name: "Ore Chunk",
        item_type: :tool,
        stackable: true,
        weight: 8,
        max_durability: 0,
        nutrition_units: 0,
        actions: [
          %{
            key: "use",
            action_kind: :repair,
            targeting: :self,
            effects: [
              %{
                applies_to: :caster,
                state: "regenerating",
                intensity: 1,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      })

    character = character_fixture(realm, location, "survivor", "Survivor")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 6})
    {:ok, _ore} = Inventory.grant_item(character, ore_template, %{quantity: 3})

    spell =
      spell_fixture(character, %{
        name: "Field Spell",
        formula: "Ignis Levis",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
      })

    _grimoire = grimoire_fixture(character, spell, "Field Grimoire", 7)

    %{realm: realm, location: location, character: character, ration_template: ration_template}
  end

  test "carried_weight/1 includes inventory and active grimoire weight", %{character: character} do
    assert Survival.carried_weight(character) == 43
    assert Survival.carry_capacity(character) == 40
    assert Survival.food_units_available(character) == 6
  end

  test "travel_plan/2 adds encumbrance penalty when overweight", %{
    realm: realm,
    location: location
  } do
    character = character_fixture(realm, location, "heavy", "Heavy")

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "trail_ration",
        name: "Trail Ration",
        item_type: :food,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, heavy_template} =
      Inventory.create_item_template(%{
        code: "boulder_fragment",
        name: "Boulder Fragment",
        item_type: :tool,
        stackable: true,
        weight: 15,
        max_durability: 0,
        nutrition_units: 0,
        actions: [
          %{
            key: "use",
            action_kind: :repair,
            targeting: :self,
            effects: [
              %{
                applies_to: :caster,
                state: "regenerating",
                intensity: 1,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      })

    {:ok, _food} = Inventory.grant_item(character, ration_template, %{quantity: 10})
    {:ok, _heavy} = Inventory.grant_item(character, heavy_template, %{quantity: 3})

    plan = Survival.travel_plan(character, 4)

    assert plan.encumbered?
    assert plan.encumbrance_penalty_days > 0
    assert plan.total_game_days > 4
    assert plan.required_food_units == plan.total_game_days
  end

  test "consume_food/3 deducts food from inventory", %{
    character: character,
    ration_template: ration_template
  } do
    assert {:ok, %{food_units_consumed: 4}} = Survival.consume_food(character, 4)

    inventory_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: ration_template.id
      )

    assert inventory_item.quantity == 2
  end

  test "expedition_supply_summary/1 aggregates member supplies and carry capacity", %{
    character: character
  } do
    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Supply Party"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    summary = Survival.expedition_supply_summary(expedition.id)
    assert summary.member_count == 1
    assert summary.total_food_units == 6
    assert summary.daily_food_demand == 1
    assert summary.projected_days == 6

    expedition = Repo.get!(Parties.Expedition, expedition.id)
    assert expedition.food_units_snapshot == 6
    assert expedition.daily_food_demand == 1
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

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name, weight) do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: weight})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: activated_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    activated_grimoire
  end
end
