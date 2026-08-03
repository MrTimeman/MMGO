defmodule MMGO.Telegram.CommandsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Operator
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Academy.Specialization
  alias MMGO.Alchemy
  alias MMGO.Bases
  alias MMGO.Combat
  alias MMGO.Crafting
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
    fund_base_acquisition!(realm, character)
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 12})

    %{realm: realm, city: city, tower: tower, route: route, character: character}
  end

  test "/admin commands expose operator reports and maintenance", %{character: character} do
    assert Operator.operator_handle?("botter")

    assert {:ok, status_text} = Commands.process_message(character, %{"text" => "/admin status"})
    assert status_text =~ "Системный отчёт"

    assert {:ok, realm_text} =
             Commands.process_message(character, %{"text" => "/admin realm canonical"})

    assert realm_text =~ "Мир canonical"

    assert {:ok, profile_text} =
             Commands.process_message(character, %{"text" => "/admin profile botter"})

    assert profile_text =~ "Профиль botter"

    assert {:ok, crime_text} =
             Commands.process_message(character, %{"text" => "/admin crime botter smuggling 12 5"})

    assert crime_text =~ "зарегистрировано"

    assert {:ok, sweep_text} = Commands.process_message(character, %{"text" => "/admin sweep"})
    assert sweep_text =~ "Обслуживание завершено"
  end

  test "a configured operator handle on the special account authorizes Albert but never Tamiorn" do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "albert",
               "first_name" => "Albert"
             })

    characters = Accounts.list_characters_for_account(account.id)
    albert = Enum.find(characters, &(&1.name == "Альберт Латыпов"))
    tamiorn = Enum.find(characters, &(&1.name == "Тамиорн Найло"))

    assert {:ok, "Недостаточно прав."} =
             Commands.process_message(albert, %{"text" => "/admin status"})

    Application.put_env(:mmgo, MMGO.Operator, handles: ["botter", account.handle])

    assert {:ok, albert_report} =
             Commands.process_message(albert, %{"text" => "/admin status"})

    assert albert_report =~ "Системный отчёт"

    assert {:ok, "Недостаточно прав."} =
             Commands.process_message(tamiorn, %{"text" => "/admin status"})
  end

  test "/status and /inventory expose current state", %{character: character} do
    assert {:ok, status_text} = Commands.process_message(character, %{"text" => "/status"})
    assert status_text =~ "Botter"
    assert status_text =~ "Capital City"
    assert status_text =~ "Еда: 12"
    assert status_text =~ "Следующий шаг:"

    assert {:ok, inventory_text} = Commands.process_message(character, %{"text" => "/inventory"})
    assert inventory_text =~ "Bot Ration"
  end

  test "/help exposes only the small player-facing command surface", %{character: character} do
    assert {:ok, help_text} = Commands.process_message(character, %{"text" => "/help"})
    assert help_text =~ "/play"
    assert help_text =~ "/status"
    assert help_text =~ "Mini App"
    refute help_text =~ "/admin"
    refute help_text =~ "/combat cast"
    refute help_text =~ "<realm-slug>"
  end

  test "/travel and /journey exercise travel from Telegram", %{character: character} do
    assert {:ok, response_text} =
             Commands.process_message(character, %{"text" => "/travel the-tower"})

    assert response_text =~ "Путь к"

    journey = Travel.active_journey(character.id)
    assert journey

    assert {:ok, journey_text} = Commands.process_message(character, %{"text" => "/journey"})
    assert journey_text =~ "The Tower"
  end

  test "/travel renders domain changeset errors in Russian", %{character: character} do
    assert {:ok, _response_text} =
             Commands.process_message(character, %{"text" => "/travel the-tower"})

    assert {:ok, response_text} =
             Commands.process_message(character, %{"text" => "/travel the-tower"})

    assert response_text ==
             "Не удалось начать путь: Состояние: у персонажа уже есть активный путь"

    refute response_text =~ "character already has"
    refute response_text =~ "status:"
  end

  test "/academy start basic and status work", %{character: character} do
    assert {:ok, response_text} =
             Commands.process_message(character, %{"text" => "/academy start basic"})

    assert response_text =~ "Базовое образование начато"

    assert {:ok, status_text} =
             Commands.process_message(character, %{"text" => "/academy status"})

    assert status_text =~ "базовое образование"
  end

  test "/alchemy commands create a workspace and start a brew", %{
    character: character,
    tower: tower
  } do
    character =
      character
      |> Character.travel_changeset(%{current_location_id: tower.id})
      |> Repo.update!()

    {:ok, %{base: building_base}} =
      Bases.start_custom_base_build(character, tower, %{name: "Bot Tower Lab"}, build_days: 1)

    assert {:ok, _active_base} = Bases.complete_base_build_by_id(building_base.id, force: true)

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

    assert workspace_text =~ "Алхимическая мастерская готова"

    assert {:ok, recipes_text} =
             Commands.process_message(character, %{"text" => "/alchemy recipes"})

    assert recipes_text =~ "bot-potion"

    assert {:ok, brew_text} =
             Commands.process_message(character, %{"text" => "/alchemy brew bot-potion 1"})

    assert brew_text =~ "поставлено вариться"

    assert {:ok, jobs_text} = Commands.process_message(character, %{"text" => "/alchemy jobs"})
    assert jobs_text =~ "Bot Potion"
  end

  test "/craft commands create a workshop and start a craft job", %{
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
      track: :mastery,
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "bot_ore",
        name: "Bot Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "bot_sword",
        name: "Bot Sword",
        item_type: :weapon,
        stackable: false,
        weight: 4,
        max_durability: 10,
        nutrition_units: 0,
        actions: [
          %{
            key: "strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 1,
            effects: [
              %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
            ]
          }
        ]
      })

    {:ok, _materials} = Inventory.grant_item(character, ore_template, %{quantity: 4})

    {:ok, _recipe} =
      Crafting.create_recipe(%{
        code: "bot-sword",
        name: "Bot Sword",
        result_item_template_id: sword_template.id,
        craft_time_game_days: 1,
        difficulty: 2,
        required_tool_codes: ["forge"],
        result_quantity: 1,
        result_durability: 10,
        requirements: [%{item_template_id: ore_template.id, quantity: 2}]
      })

    assert {:ok, workspace_text} =
             Commands.process_message(character, %{"text" => "/craft setup forge"})

    assert workspace_text =~ "Ремесленная мастерская готова"

    assert {:ok, recipes_text} =
             Commands.process_message(character, %{"text" => "/craft recipes"})

    assert recipes_text =~ "bot-sword"

    assert {:ok, craft_text} =
             Commands.process_message(character, %{"text" => "/craft build bot-sword 1"})

    assert craft_text =~ "Работа над"

    assert {:ok, jobs_text} = Commands.process_message(character, %{"text" => "/craft jobs"})
    assert jobs_text =~ "Bot Sword"
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

    %Specialization{}
    |> Specialization.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      track: :wizardry,
      status: :active,
      primary_school: :fire,
      secondary_school: :air,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

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
        tags: ["return_ritual"],
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

    assert expedition_text =~ "Экспедиция начата"

    assert {:ok, dungeon_enter_text} =
             Commands.process_message(character, %{"text" => "/dungeon enter"})

    assert dungeon_enter_text =~ "Вы вошли в подземелье"

    assert {:ok, encounter_text} =
             Commands.process_message(character, %{"text" => "/encounter fight"})

    assert encounter_text =~ "Бой во встрече начат"

    assert {:ok, spells_text} = Commands.process_message(character, %{"text" => "/spells"})
    assert spells_text =~ spell.name
    refute spells_text =~ spell.id

    assert {:ok, cast_text} =
             Commands.process_message(character, %{"text" => "/combat cast #{spell.id}"})

    assert cast_text =~ "Заклинание подготовлено"

    combat = Combat.active_combat_for_character(character.id)

    encounter_participant =
      Enum.find(combat.participants, fn participant ->
        participant.character_id != character.id and participant.status == :ready
      end)

    assert {:ok, _wait} =
             Combat.submit_action(combat, encounter_participant.id, %{action_type: :wait})

    assert {:ok, resolve_text} =
             Commands.process_message(character, %{"text" => "/combat resolve"})

    assert resolve_text =~ "Бой рассчитан"

    run =
      character.id
      |> Parties.active_expedition_for_character()
      |> then(&Dungeons.active_run_for_expedition(&1.id))

    encounter = Dungeons.current_encounter_for_run(run.id)
    assert encounter.status == :cleared

    assert {:ok, move_text} =
             Commands.process_message(character, %{"text" => "/dungeon move rest"})

    assert move_text =~ "Rest Chamber"

    assert {:ok, ritual_text} =
             Commands.process_message(character, %{"text" => "/dungeon ritual"})

    assert ritual_text =~ "Ритуал возвращения начат"

    assert {:ok, status_text} =
             Commands.process_message(character, %{"text" => "/dungeon status"})

    assert status_text =~ "Возвращение: ритуал возвращения"
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
