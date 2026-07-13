defmodule MMGO.DungeonExtractionTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Specialization
  alias MMGO.Dungeons
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Play
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
    grimoire = grimoire_fixture(character, spell)

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
      dungeon: dungeon,
      floor: floor,
      entrance_node: entrance_node,
      deep_node: deep_node,
      character: character,
      spell: spell,
      grimoire: grimoire,
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
    spell: spell,
    tower: tower
  } do
    {:ok, %{run: moved_run}} = Dungeons.move_run(run, deep_node.id)

    assert {:ok, %{extraction: extraction}} = Dungeons.start_return_ritual(moved_run, character)
    assert extraction.status == :active
    assert extraction.metadata["origin_floor_number"] == 1
    assert extraction.metadata["origin_node_id"] == deep_node.id
    assert extraction.metadata["prepared_spell_id"] == spell.id

    assert {:ok, state} = Play.dungeon_state(character)
    assert state.return_ritual.prepared?
    assert state.return_ritual.prepared_spell_id == spell.id

    assert {:ok, %{run: extracted_run, extraction: completed_extraction}} =
             Dungeons.complete_extraction_by_id(extraction.id, force: true)

    assert completed_extraction.status == :completed
    assert extracted_run.status == :completed
    assert Repo.get!(Character, character.id).current_location_id == tower.id
  end

  test "return ritual requires an active grimoire", %{
    character: character,
    grimoire: grimoire,
    run: run
  } do
    grimoire
    |> Ecto.Changeset.change(status: :sealed)
    |> Repo.update!()

    assert {:error, changeset} = Dungeons.start_return_ritual(run, character)

    assert %{status: ["ritual caster must have an active grimoire"]} = errors_on(changeset)
  end

  test "return ritual requires an active wizardry specialization", %{
    character: character,
    run: run
  } do
    Specialization
    |> Repo.get_by!(character_id: character.id, status: :active)
    |> Ecto.Changeset.change(status: :retired, ended_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:error, changeset} = Dungeons.start_return_ritual(run, character)

    assert %{status: ["initiator must be a wizardry specialist to perform the return ritual"]} =
             errors_on(changeset)
  end

  test "return ritual requires its explicit prepared spell tag", %{
    character: character,
    run: run,
    spell: spell
  } do
    spell
    |> Ecto.Changeset.change(tags: ["ritual"])
    |> Repo.update!()

    assert {:error, changeset} = Dungeons.start_return_ritual(run, character)

    assert %{status: ["active grimoire must contain a prepared return ritual"]} =
             errors_on(changeset)
  end

  test "return ritual requires the run's recorded current node", %{
    character: character,
    dungeon: dungeon,
    run: run
  } do
    {:ok, detached_floor} = Dungeons.create_floor(dungeon, %{number: 2, name: "Lower Halls"})

    {:ok, detached_node} =
      Dungeons.create_node(detached_floor, %{
        slug: "detached",
        name: "Detached Room",
        kind: :room,
        x: 0,
        y: 0,
        threat_level: 0
      })

    corrupted_run =
      run
      |> Ecto.Changeset.change(current_node_id: detached_node.id)
      |> Repo.update!()

    assert {:error, changeset} = Dungeons.start_return_ritual(corrupted_run, character)
    assert %{status: ["run has no valid current dungeon node"]} = errors_on(changeset)
  end

  test "return ritual cannot start through an unresolved current encounter", %{
    character: character,
    deep_node: deep_node,
    run: run
  } do
    {:ok, %{run: moved_run}} = Dungeons.move_run(run, deep_node.id)

    assert {:ok, %{encounter: encounter}} =
             Dungeons.materialize_node_content(moved_run, deep_node.id, %{
               "encounter" => %{
                 "encounter_kind" => "ambush",
                 "status" => "pending",
                 "threat_level" => 1,
                 "started_at" => DateTime.utc_now(),
                 "metadata" => %{}
               }
             })

    assert encounter.status == :pending
    assert {:error, changeset} = Dungeons.start_return_ritual(moved_run, character)

    assert %{status: ["current encounter must be resolved before extraction"]} =
             errors_on(changeset)
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
        name: "Return Ritual",
        formula: "Via Domum",
        school: :fire,
        targeting: :self,
        delivery_form: :self,
        tags: ["return_ritual"],
        effects: [
          %{applies_to: :caster, state: "shielded", intensity: 20, variance: 0, duration: 1}
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
