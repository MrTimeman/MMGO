defmodule MMGO.FederationRulesetTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Event
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  test "canonical ruleset suppresses magic in city duels while global ruleset allows it" do
    {:ok, canonical_realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
      })

    {:ok, global_realm} =
      Worlds.create_realm(%{
        slug: "global-magic",
        name: "Global Magic Realm",
        currency_code: "GLD",
        ruleset: %{"magic_scope" => "global"}
      })

    {:ok, canonical_city} =
      Worlds.create_location(canonical_realm, %{
        slug: "city-a",
        name: "City A",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, global_city} =
      Worlds.create_location(global_realm, %{
        slug: "city-b",
        name: "City B",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    {canonical_caster, canonical_target, canonical_spell} =
      duel_fixture(canonical_realm, canonical_city, 50)

    {global_caster, global_target, global_spell} = duel_fixture(global_realm, global_city, 50)

    {:ok, canonical_duel} = PVP.challenge_duel(canonical_caster, canonical_target, 10)
    {:ok, canonical_duel} = PVP.accept_duel(canonical_duel)
    canonical_combat = Combat.get_combat!(canonical_duel.combat.id)

    canonical_participant =
      Enum.find(canonical_combat.participants, &(&1.character_id == canonical_caster.id))

    assert {:ok, _action} =
             Combat.submit_action(canonical_combat, canonical_participant.id, %{
               action_type: :cast_spell,
               spell_id: canonical_spell.id
             })

    assert {:ok, _resolved} = Combat.resolve_turn(canonical_combat)
    assert Repo.get_by!(Event, combat_id: canonical_combat.id, event_type: "magic_suppressed")

    {:ok, global_duel} = PVP.challenge_duel(global_caster, global_target, 10)
    {:ok, global_duel} = PVP.accept_duel(global_duel)
    global_combat = Combat.get_combat!(global_duel.combat.id)

    global_participant =
      Enum.find(global_combat.participants, &(&1.character_id == global_caster.id))

    assert {:ok, _action} =
             Combat.submit_action(global_combat, global_participant.id, %{
               action_type: :cast_spell,
               spell_id: global_spell.id
             })

    assert {:ok, _resolved} = Combat.resolve_turn(global_combat)
    refute Repo.get_by(Event, combat_id: global_combat.id, event_type: "magic_suppressed")
  end

  defp duel_fixture(realm, location, funds) do
    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    caster = character_fixture(realm, location, "#{realm.slug}-caster", "#{realm.name} Caster")
    target = character_fixture(realm, location, "#{realm.slug}-target", "#{realm.name} Target")
    {:ok, _caster_funds} = Economy.grant_from_treasury(realm, caster, funds)
    {:ok, _target_funds} = Economy.grant_from_treasury(realm, target, funds)

    spell =
      spell_fixture(caster, %{
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

    _grimoire = grimoire_fixture(caster, spell, "Realm Grimoire")
    {caster, target, spell}
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

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
