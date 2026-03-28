defmodule MMGO.ActorsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Actors
  alias MMGO.Combat
  alias MMGO.Dungeons
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
        x: 50,
        y: 50,
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

    {:ok, node} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Entrance Hall",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 12
      })

    character = character_fixture(realm, tower, "caster", "Caster")
    spell = spell_fixture(character)
    _grimoire = grimoire_fixture(character, spell, "Field Grimoire")

    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)
    encounter = Repo.get_by!(Dungeons.Encounter, run_id: run.id, node_id: node.id)

    %{realm: realm, run: run, encounter: encounter, character: character}
  end

  test "ensure_default_spawns/2 creates generic hostile actor templates and encounter spawns", %{
    realm: realm,
    encounter: encounter
  } do
    assert {:ok, [spawn]} = Actors.ensure_default_spawns(encounter, realm)
    assert spawn.quantity >= 1
    assert spawn.actor_template.name =~ "Dungeon"
    assert spawn.actor_template.role == :hostile
    assert spawn.actor_template.combat_level >= 1
  end

  test "starting encounter combat adds actor-backed participants", %{
    encounter: encounter,
    character: character
  } do
    assert {:ok, %{combat: combat}} = Dungeons.start_encounter_combat(encounter)

    combat = Combat.get_combat!(combat.id)
    assert Enum.any?(combat.participants, &(&1.character_id == character.id))

    actor_participants = Enum.filter(combat.participants, &is_nil(&1.character_id))
    assert actor_participants != []
    assert Enum.all?(actor_participants, & &1.actor_template_id)
    assert Enum.all?(actor_participants, &(&1.display_name != nil))
    assert Enum.all?(actor_participants, &(&1.combat_level > 0))
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
        name: "Realm Bolt",
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

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
