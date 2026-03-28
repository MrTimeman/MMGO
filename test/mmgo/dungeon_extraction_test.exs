defmodule MMGO.DungeonExtractionTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Specialization
  alias MMGO.Dungeons
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "tower",
        name: "Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon",
        name: "Tower Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})

    {:ok, entrance_node} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Entrance",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 0
      })

    {:ok, deep_node} =
      Dungeons.create_node(floor, %{
        slug: "deep",
        name: "Deep Room",
        kind: :room,
        x: 1,
        y: 0,
        threat_level: 0
      })

    {:ok, _link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: deep_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    character = character_fixture(realm, tower, "delver", "Delver")
    spell = spell_fixture(character)
    _grimoire = grimoire_fixture(character, spell)

    {:ok, herb_template} =
      Inventory.create_item_template(%{
        code: "lost_herb",
        name: "Lost Herb",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, _items} = Inventory.grant_item(character, herb_template, %{quantity: 3})

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

    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    %{
      tower: tower,
      entrance_node: entrance_node,
      deep_node: deep_node,
      character: character,
      run: run,
      expedition: expedition
    }
  end

  test "extract_via_ascent/2 completes a run from an ascent node", %{
    character: character,
    run: run,
    tower: tower
  } do
    assert {:ok, %{run: updated_run}} = Dungeons.extract_via_ascent(run)

    assert updated_run.status == :completed
    assert Repo.get!(Character, character.id).current_location_id == tower.id
  end

  test "return ritual extracts from a non-ascent node", %{
    character: character,
    run: run,
    deep_node: deep_node,
    tower: tower
  } do
    {:ok, %{run: moved_run}} = Dungeons.move_run(run, deep_node.id)

    assert {:ok, %{extraction: extraction}} = Dungeons.start_return_ritual(moved_run, character)
    assert extraction.status == :active

    assert {:ok, %{run: extracted_run, extraction: completed_extraction}} =
             Dungeons.complete_extraction_by_id(extraction.id, force: true)

    assert completed_extraction.status == :completed
    assert extracted_run.status == :completed
    assert Repo.get!(Character, character.id).current_location_id == tower.id
  end

  test "fail_run_with_sacrifice/2 drops inventory and active grimoire", %{
    character: character,
    run: run,
    tower: tower
  } do
    assert {:ok, %{run: failed_run, drops: drops}} = Dungeons.fail_run_with_sacrifice(run)

    assert failed_run.status == :failed
    assert length(drops) >= 2
    assert Enum.any?(drops, &(&1.drop_kind == :inventory))
    assert Enum.any?(drops, &(&1.drop_kind == :grimoire))
    assert Repo.get!(Character, character.id).current_location_id == tower.id
    refute Grimoires.active_grimoire_for_character(character.id)
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

  defp spell_fixture(character) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: "Return Bolt",
        formula: "Ignis Minor",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 20, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 95,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    spell
  end

  defp grimoire_fixture(character, spell) do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Delver Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
