defmodule MMGO.DungeonCombatIntegrationTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Dungeons
  alias MMGO.Dungeons.Encounter
  alias MMGO.Grimoires
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 260,
        safe_zone: false
      })

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

    character = character_fixture(realm, tower, "combat-delver", "Combat Delver")

    spell =
      spell_fixture(character, %{
        name: "Ignis Maxima",
        formula: "Ignis Maxima Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 35, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 99,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    _grimoire = grimoire_fixture(character, spell, "Delver Grimoire")

    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Combat Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)

    %{character: character, spell: spell, dungeon: dungeon, encounter: encounter, run: run}
  end

  test "start_encounter_combat/2 creates a dungeon combat linked to the encounter", %{
    encounter: encounter
  } do
    assert {:ok, %{combat: combat, encounter: updated_encounter}} =
             Dungeons.start_encounter_combat(encounter)

    assert combat.kind == :dungeon_encounter
    assert updated_encounter.status == :active
    assert updated_encounter.combat_id == combat.id
    assert combat.sides["party"]["shared_hp"] == 100
    assert combat.sides["encounter"]["shared_hp"] >= 25
  end

  test "finished dungeon combat can clear an encounter and generate loot", %{
    encounter: encounter,
    character: character,
    spell: spell
  } do
    assert {:ok, %{combat: combat}} = Dungeons.start_encounter_combat(encounter)

    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == character.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "encounter"
             })

    assert {:ok, %CombatSchema{} = resolved_combat} = Combat.resolve_turn(combat)
    assert resolved_combat.status == :finished
    assert resolved_combat.winner_side == "party"

    assert {:ok, %{encounter: resolved_encounter, loot_drops: [loot_drop]}} =
             Dungeons.sync_encounter_combat(resolved_combat)

    assert resolved_encounter.status == :cleared
    assert loot_drop.status == :available
    assert loot_drop.encounter_id == encounter.id
  end

  test "losing a dungeon combat fails the encounter and the run", %{
    encounter: encounter,
    run: run
  } do
    assert {:ok, %{combat: combat}} = Dungeons.start_encounter_combat(encounter)

    combat =
      combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "encounter",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, %{encounter: resolved_encounter}} = Dungeons.sync_encounter_combat(combat)

    assert resolved_encounter.status == :failed
    assert Dungeons.get_run!(run.id).status == :failed
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 18})
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
