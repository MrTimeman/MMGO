defmodule MMGO.CombatTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.{Event, Participant, Turn}
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    attacker = character_fixture("attacker", realm, "Attacker One")
    defender = character_fixture("defender", realm, "Defender One")

    fireball =
      spell_fixture(attacker, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        tags: ["fire", "projectile"],
        effects: [
          %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0},
          %{applies_to: :target, state: "burning", intensity: 5, variance: 0, duration: 2}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    ward =
      spell_fixture(defender, %{
        name: "Aegis Murus",
        formula: "Aegis Murus Levis",
        school: :order,
        targeting: :self,
        delivery_form: :wall,
        tags: ["warding"],
        effects: [
          %{applies_to: :caster, state: "shielded", intensity: 8, variance: 0, duration: 1}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    _attacker_grimoire = grimoire_fixture(attacker, fireball, "Attacker's Grimoire")
    _defender_grimoire = grimoire_fixture(defender, ward, "Defender's Grimoire")

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ],
        sides: %{
          attackers: %{"label" => "Red", "shared_hp" => 100, "max_shared_hp" => 100},
          defenders: %{"label" => "Blue", "shared_hp" => 100, "max_shared_hp" => 100}
        }
      })

    %{
      realm: realm,
      attacker: attacker,
      defender: defender,
      fireball: fireball,
      ward: ward,
      combat: combat
    }
  end

  # A fight nobody is playing used to tick forever: nobody takes damage, so no
  # winner is found, so another turn always opened. One abandoned encounter in
  # production reached 31,805 of them, each paying a provider for orchestration
  # and narration of nothing.
  test "a fight nobody is playing is abandoned instead of ticking forever", %{combat: combat} do
    combat =
      Enum.reduce(1..3, Combat.get_combat!(combat.id), fn _turn, current ->
        assert {:ok, resolved} = Combat.resolve_turn(current, force?: true)
        Combat.get_combat!(resolved.id)
      end)

    assert combat.status == :finished
    assert combat.metadata["idle_turns"] >= 3

    # And no further turn was opened to be resolved after it.
    refute Repo.get_by(MMGO.Combat.Turn, combat_id: combat.id, status: :open)
  end

  # The shape the bug actually had in production: the deadline fills a `wait`
  # in for every participant who did not answer, so an abandoned fight submits
  # a full set of actions every turn and looks busy. An arena match ran 133
  # turns on nothing but deadline waits.
  test "deadline waits are silence, not action", %{combat: combat} do
    combat = Combat.get_combat!(combat.id)

    combat =
      Enum.reduce(1..3, combat, fn _turn, current ->
        turn = Repo.get_by!(MMGO.Combat.Turn, combat_id: current.id, status: :open)

        Enum.each(current.participants, fn participant ->
          %MMGO.Combat.Action{}
          |> MMGO.Combat.Action.changeset(%{
            combat_turn_id: turn.id,
            participant_id: participant.id,
            action_type: :wait,
            submitted_at: DateTime.utc_now(),
            payload: %{"source" => "turn_deadline"}
          })
          |> Repo.insert!()
        end)

        assert {:ok, resolved} = Combat.resolve_turn(current, force?: true)
        Combat.get_combat!(resolved.id)
      end)

    assert combat.status == :finished
    assert combat.metadata["idle_turns"] >= 3
  end

  # A turn of pure silence is not worth paying a provider to describe.
  test "an idle turn is marked so it is never narrated", %{combat: combat} do
    combat = Combat.get_combat!(combat.id)
    assert {:ok, resolved} = Combat.resolve_turn(combat, force?: true)

    turn = Repo.get_by!(MMGO.Combat.Turn, combat_id: resolved.id, number: 1)
    assert turn.resolution["idle"] == true
    assert :ok = MMGO.Combat.TurnArtifacts.persist(resolved.id, turn.id)
  end

  test "one acted turn clears the idle count", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Combat.get_combat!(combat.id)
    assert {:ok, resolved} = Combat.resolve_turn(combat, force?: true)
    assert Combat.get_combat!(resolved.id).metadata["idle_turns"] == 1

    combat = Combat.get_combat!(resolved.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, acted} = Combat.resolve_turn(combat, force?: true)
    assert Combat.get_combat!(acted.id).metadata["idle_turns"] == 0
  end

  test "resolve_turn/1 applies deterministic spell damage and states", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, %CombatSchema{} = resolved_combat} = Combat.resolve_turn(combat, force?: true)
    assert resolved_combat.turn_number == 2

    defenders = resolved_combat.sides["defenders"]
    assert defenders["shared_hp"] < defenders["max_shared_hp"]

    defender_participant = Repo.get_by!(Participant, combat_id: combat.id, side: "defenders")
    assert Enum.any?(defender_participant.active_states, &(&1["state"] == "burning"))
    assert Repo.aggregate(Event, :count, :id) > 0
  end

  test "shielded states absorb incoming impact damage", %{
    combat: combat,
    attacker: attacker,
    defender: defender,
    fireball: fireball,
    ward: ward
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{
               action_type: :cast_spell,
               spell_id: ward.id
             })

    assert {:ok, _combat} = Combat.resolve_turn(combat, force?: true)

    reloaded = Combat.get_combat!(combat.id)

    assert {:ok, _action} =
             Combat.submit_action(reloaded, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, %CombatSchema{} = resolved_again} = Combat.resolve_turn(reloaded, force?: true)
    defenders = resolved_again.sides["defenders"]

    assert defenders["shared_hp"] > 70

    defender_after = Repo.get_by!(Participant, combat_id: combat.id, character_id: defender.id)
    refute Enum.any?(defender_after.active_states, &(&1["state"] == "shielded"))
  end

  test "silenced casters cannot cast prepared spells", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    attacker_participant
    |> Participant.changeset(%{
      active_states: [%{"state" => "silenced", "remaining_turns" => 2, "intensity" => 1}]
    })
    |> Repo.update!()

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat, force?: true)

    blocked_event = Repo.get_by!(Event, combat_id: combat.id, event_type: "action_blocked")
    assert blocked_event.payload["state"] == "silenced"
  end

  test "spells not inscribed in the active grimoire are rejected", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    other_spell =
      spell_fixture(attacker, %{
        name: "Terra Murus",
        formula: "Terra Murus Magnus",
        school: :earth,
        targeting: :enemy,
        delivery_form: :wall,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 15, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:error, :spell_not_prepared} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: other_spell.id,
               target_side: "defenders"
             })

    assert Repo.aggregate(Event, :count, :id) == 0
  end

  test "resolve_turn/1 serializes concurrent resolves and never double-processes a turn", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    # A one-shot spell so the combat finishes on turn 1 — that way a second,
    # concurrent resolve of the *same* turn has no legitimate turn 2 to fall
    # through to; it can only be a stale double-resolve of turn 1.
    killing_blow =
      spell_fixture(attacker, %{
        name: "Ignis Ultima",
        formula: "Ignis Ultima Suprema",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 100, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    _attacker_grimoire = grimoire_fixture(attacker, killing_blow, "Killing Blow Grimoire")

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ],
        sides: %{
          attackers: %{"label" => "Red", "shared_hp" => 100, "max_shared_hp" => 100},
          defenders: %{"label" => "Blue", "shared_hp" => 100, "max_shared_hp" => 100}
        }
      })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: killing_blow.id,
               target_side: "defenders"
             })

    parent = self()

    # Simulate two participants both hitting "resolve" for the same combat at
    # the same time: two separate processes racing MMGO.Combat.resolve_turn/1
    # against the same combat row. Without a row lock + in-transaction status
    # re-check, both could read the same open turn, both compute a resolution,
    # and both write it — double-inserting events and double-finishing the
    # combat. With the fix, only one wins the row lock and actually resolves
    # the turn; the other blocks on the lock, then sees turn 1 already
    # resolved once it acquires it and bails out instead of re-processing.
    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Combat.resolve_turn(combat, force?: true)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, %CombatSchema{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :turn_closed}, &1)) == 1

    # The turn only ever resolved once: exactly one set of resolution events
    # was written and the combat finished exactly once.
    resolved_combat = Combat.get_combat!(combat.id)
    assert resolved_combat.status == :finished
    assert resolved_combat.turn_number == 1

    events =
      Event
      |> where([event], event.combat_id == ^combat.id and event.turn_number == 1)
      |> Repo.all()

    action_events = Enum.filter(events, &(&1.event_type in ["spell_cast", "partial_spell_cast"]))
    assert length(action_events) == 1
  end

  test "resolve_turn/1 rejects a stale turn snapshot instead of resolving turn two", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:error, :turn_open} = Combat.resolve_turn(combat)
    assert {:ok, %CombatSchema{turn_number: 2}} = Combat.resolve_turn(combat, force?: true)
    assert {:error, :turn_closed} = Combat.resolve_turn(combat)

    assert %Turn{status: :open} = Repo.get_by(Turn, combat_id: combat.id, number: 2)

    refute Repo.exists?(
             from event in Event,
               where: event.combat_id == ^combat.id and event.turn_number == 2
           )
  end

  defp character_fixture(handle, realm, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 12})
    |> Repo.insert!()
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 6, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: activated_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    activated_grimoire
  end
end
