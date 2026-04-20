defmodule MMGO.Combat.OrchestratedResolutionTest do
  use MMGO.DataCase, async: true

  import Ecto.Query, warn: false

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.{Event, Participant, Turn}
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  defmodule ScriptedAiProvider do
    @behaviour MMGO.AI.Provider

    def compile_spell(_prompt_payload, _opts), do: {:error, :unused}

    def narrate_turn(_prompt_payload, _opts) do
      {:ok, "Ход 1: огненный удар пробивает строй, и пламя цепляется за защитников."}
    end

    def orchestrate_combat(prompt_payload, _opts) do
      resolution_id =
        prompt_payload
        |> Map.fetch!(:user_prompt)
        |> Jason.decode!()
        |> get_in(["resolutions", Access.at(0), "resolution_id"])

      {:ok,
       %{
         "picks" => [
           %{
             "resolution_id" => resolution_id,
             "outcome" => "success",
             "chosen_roll" => 41,
             "effect_picks" => [
               %{"effect_index" => 0, "intensity" => 20},
               %{"effect_index" => 1, "intensity" => 5}
             ]
           }
         ]
       }}
    end

    def tick_dungeon(_prompt_payload, _opts), do: {:error, :unused}
  end

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    attacker_one = character_fixture(realm, "orch-attacker-1", "Attacker One")
    attacker_two = character_fixture(realm, "orch-attacker-2", "Attacker Two")
    defender_one = character_fixture(realm, "orch-defender-1", "Defender One")
    defender_two = character_fixture(realm, "orch-defender-2", "Defender Two")

    spell =
      spell_fixture(attacker_one, %{
        name: "Ignis Chorus",
        formula: "Ignis Chorus Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0},
          %{applies_to: :target, state: "burning", intensity: 5, variance: 0, duration: 2}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    _grimoire = grimoire_fixture(attacker_one, spell, "Orchestrator Tome")

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker_one.id, side: "attackers", position: 0},
          %{character_id: attacker_two.id, side: "attackers", position: 1},
          %{character_id: defender_one.id, side: "defenders", position: 0},
          %{character_id: defender_two.id, side: "defenders", position: 1}
        ],
        sides: %{
          attackers: %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
          defenders: %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
        }
      })

    %{
      combat: combat,
      attacker_one: attacker_one,
      defender_one: defender_one,
      spell: spell
    }
  end

  test "resolve_turn/2 persists scripted dramatic picks and Russian narration in a 2v2 duel", %{
    combat: combat,
    attacker_one: attacker_one,
    defender_one: defender_one,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker_one.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender_one.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders",
               target_participant_id: defender_participant.id
             })

    assert {:ok, resolved_combat} = Combat.resolve_turn(combat, provider: ScriptedAiProvider)
    assert resolved_combat.turn_number == 2
    assert resolved_combat.sides["defenders"]["shared_hp"] == 80

    turn = Repo.get_by!(Turn, combat_id: combat.id, number: 1)

    assert turn.narration ==
             "Ход 1: огненный удар пробивает строй, и пламя цепляется за защитников."

    spell_event = Repo.get_by!(Event, combat_id: combat.id, event_type: "spell_cast")
    assert spell_event.payload["orchestration"]["mode"] == "ai"
    assert spell_event.payload["orchestration"]["chosen_roll"] == 41

    assert spell_event.payload["effects"] == [
             %{
               "damage" => 20,
               "effect_index" => 0,
               "exposed_bonus" => 0,
               "range" => %{"min" => 16, "max" => 20},
               "shield_absorbed" => 0,
               "state" => "impact",
               "target_side" => "defenders",
               "warded_reduction" => 0
             },
             %{
               "duration" => 2,
               "effect_index" => 1,
               "intensity" => 5,
               "participant_id" => defender_participant.id,
               "range" => %{"min" => 5, "max" => 5},
               "state" => "burning"
             }
           ]

    defender_after =
      Repo.get_by!(Participant, combat_id: combat.id, character_id: defender_one.id)

    assert Enum.any?(
             defender_after.active_states,
             &(&1["state"] == "burning" and &1["intensity"] == 5)
           )

    ai_request_kinds =
      Repo.all(
        from request in Request, select: request.kind, order_by: [asc: request.inserted_at]
      )

    assert ai_request_kinds == [:combat_orchestrator, :turn_narration]
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 18})
    |> Repo.insert!()
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
