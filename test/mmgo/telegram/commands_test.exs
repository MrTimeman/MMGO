defmodule MMGO.Telegram.CommandsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Operator
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Academy.Specialization
  alias MMGO.Alchemy
  alias MMGO.Spells
  alias MMGO.Telegram.Commands
  alias MMGO.Travel
  alias MMGO.Worlds

  setup do
    original_operator_config = Application.get_env(:mmgo, MMGO.Operator)
    Application.put_env(:mmgo, MMGO.Operator, handles: ["botter"])

    on_exit(fn ->
      if original_operator_config do
        Application.put_env(:mmgo, MMGO.Operator, original_operator_config)
      else
        Application.delete_env(:mmgo, MMGO.Operator)
      end
    end)

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
        y: 200,
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
        code: "bot_ration",
        name: "Bot Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "botter", "Botter")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 12})

    %{realm: realm, city: city, tower: tower, route: route, character: character}
  end

  test "/admin commands expose operator reports and maintenance", %{character: character} do
    assert Operator.operator_handle?("botter")

    assert {:ok, status_text} = Commands.process_message(character, %{"text" => "/admin status"})
    assert status_text =~ "System report"

    assert {:ok, realm_text} =
             Commands.process_message(character, %{"text" => "/admin realm canonical"})

    assert realm_text =~ "Realm canonical"

    assert {:ok, profile_text} =
             Commands.process_message(character, %{"text" => "/admin profile botter"})

    assert profile_text =~ "Profile for botter"

    assert {:ok, crime_text} =
             Commands.process_message(character, %{"text" => "/admin crime botter smuggling 12 5"})

    assert crime_text =~ "Crime recorded"

    assert {:ok, sweep_text} = Commands.process_message(character, %{"text" => "/admin sweep"})
    assert sweep_text =~ "Maintenance sweep complete"
  end

  test "/status and /inventory expose current state", %{character: character} do
    assert {:ok, status_text} = Commands.process_message(character, %{"text" => "/status"})
    assert status_text =~ "Botter"
    assert status_text =~ "Capital City"
    assert status_text =~ "Food: 12"

    assert {:ok, inventory_text} = Commands.process_message(character, %{"text" => "/inventory"})
    assert inventory_text =~ "Bot Ration"
  end

  test "/travel and /journey exercise travel from Telegram", %{character: character} do
    assert {:ok, response_text} =
             Commands.process_message(character, %{"text" => "/travel the-tower"})

    assert response_text =~ "Journey started"

    journey = Travel.active_journey(character.id)
    assert journey

    assert {:ok, journey_text} = Commands.process_message(character, %{"text" => "/journey"})
    assert journey_text =~ "The Tower"
  end

  test "/academy start basic and status work", %{character: character} do
    assert {:ok, response_text} =
             Commands.process_message(character, %{"text" => "/academy start basic"})

    assert response_text =~ "Basic education started"

    assert {:ok, status_text} =
             Commands.process_message(character, %{"text" => "/academy status"})

    assert status_text =~ "basic_education"
  end

  test "/alchemy commands create a workspace and start a brew", %{
    character: character,
    tower: tower
  } do
    character =
      character
      |> Character.travel_changeset(%{current_location_id: tower.id})
      |> Repo.update!()

    %Specialization{}
    |> Specialization.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      track: :alchemy,
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, herb_template} =
      Inventory.create_item_template(%{
        code: "bot_herb",
        name: "Bot Herb",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, potion_template} =
      Inventory.create_item_template(%{
        code: "bot_potion",
        name: "Bot Potion",
        item_type: :potion,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: [
          %{
            key: "throw",
            action_kind: :throw,
            targeting: :ally,
            quantity_cost: 1,
            effects: [
              %{
                applies_to: :target,
                state: "regenerating",
                intensity: 3,
                variance: 0,
                duration: 2
              }
            ]
          }
        ]
      })

    {:ok, _ingredients} = Inventory.grant_item(character, herb_template, %{quantity: 5})

    {:ok, _recipe} =
      Alchemy.create_recipe(%{
        code: "bot-potion",
        name: "Bot Potion",
        result_item_template_id: potion_template.id,
        brew_time_game_days: 1,
        difficulty: 2,
        required_tool_codes: ["cauldron"],
        result_quantity: 1,
        requirements: [%{item_template_id: herb_template.id, quantity: 2}]
      })

    assert {:ok, workspace_text} =
             Commands.process_message(character, %{"text" => "/alchemy setup cauldron"})

    assert workspace_text =~ "Alchemy workspace ready"

    assert {:ok, recipes_text} =
             Commands.process_message(character, %{"text" => "/alchemy recipes"})

    assert recipes_text =~ "bot-potion"

    assert {:ok, brew_text} =
             Commands.process_message(character, %{"text" => "/alchemy brew bot-potion 1"})

    assert brew_text =~ "Brewing started"

    assert {:ok, jobs_text} = Commands.process_message(character, %{"text" => "/alchemy jobs"})
    assert jobs_text =~ "Bot Potion"
  end

  test "party, expedition, dungeon, and combat commands work together", %{
    realm: realm,
    character: character,
    tower: tower
  } do
    character =
      character
      |> Character.travel_changeset(%{current_location_id: tower.id})
      |> Repo.update!()

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon",
        name: "Tower Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor_one} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})

    {:ok, entrance_node} =
      Dungeons.create_node(floor_one, %{
        slug: "entrance",
        name: "Entrance Hall",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 5
      })

    {:ok, rest_node} =
      Dungeons.create_node(floor_one, %{
        slug: "rest",
        name: "Rest Chamber",
        kind: :rest,
        x: 1,
        y: 0,
        threat_level: 0
      })

    {:ok, _link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: rest_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    spell =
      spell_fixture(character, %{
        name: "Ignis Maxima",
        formula: "Ignis Maxima Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 40, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 99,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    _grimoire = grimoire_fixture(character, spell, "Bot Grimoire")

    assert {:ok, _text} =
             Commands.process_message(character, %{"text" => "/party create Solo Delvers"})

    assert {:ok, expedition_text} =
             Commands.process_message(character, %{"text" => "/expedition start"})

    assert expedition_text =~ "Expedition started"

    assert {:ok, dungeon_enter_text} =
             Commands.process_message(character, %{"text" => "/dungeon enter"})

    assert dungeon_enter_text =~ "Entered dungeon"

    assert {:ok, encounter_text} =
             Commands.process_message(character, %{"text" => "/encounter fight"})

    assert encounter_text =~ "Encounter combat started"

    assert {:ok, spells_text} = Commands.process_message(character, %{"text" => "/spells"})
    assert spells_text =~ spell.id

    assert {:ok, cast_text} =
             Commands.process_message(character, %{"text" => "/combat cast #{spell.id}"})

    assert cast_text =~ "Spell queued"

    assert {:ok, resolve_text} =
             Commands.process_message(character, %{"text" => "/combat resolve"})

    assert resolve_text =~ "Combat resolved"

    run =
      character.id
      |> Parties.active_expedition_for_character()
      |> then(&Dungeons.active_run_for_expedition(&1.id))

    encounter = Dungeons.current_encounter_for_run(run.id)
    assert encounter.status == :cleared

    assert {:ok, move_text} =
             Commands.process_message(character, %{"text" => "/dungeon move rest"})

    assert move_text =~ "Rest Chamber"
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 18, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
