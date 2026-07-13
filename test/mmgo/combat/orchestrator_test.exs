defmodule MMGO.Combat.OrchestratorTest do
  use MMGO.DataCase, async: true

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.{Orchestrator, Turn}
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  defmodule InvalidOrchestrationProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "casts" => [
           %{
             "participant_id" => "foreign-participant",
             "target_participant_id" => "foreign-target",
             "effects" => [
               %{
                 "applies_to" => "target",
                 "state" => "invented_state",
                 "intensity" => 999,
                 "duration" => 999
               }
             ]
           }
         ],
         "narrative_ru" => "Несуществующее проявление."
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "orchestrator-realm",
        name: "Orchestrator Realm",
        is_default: true
      })

    attacker = character_fixture(realm, "orchestrator-attacker", "Orchestrator Attacker")
    defender = character_fixture(realm, "orchestrator-defender", "Orchestrator Defender")

    spell =
      spell_fixture(attacker, %{
        name: "Bound Ignis",
        formula: "Ignis Radius",
        effects: [
          %{applies_to: :target, state: "impact", intensity: 14, variance: 0, duration: 0},
          %{applies_to: :target, state: "burning", intensity: 4, variance: 0, duration: 2}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    activate_grimoire(attacker, spell)

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    assert {:ok, _resolved_combat} = Combat.resolve_turn(combat, force?: true)
    turn = Repo.get_by!(Turn, combat_id: combat.id, number: 1)

    %{combat: combat, turn: turn}
  end

  test "stores a bounded provider artifact once for a resolved turn", %{
    combat: combat,
    turn: turn
  } do
    assert {:ok, stored_turn} = Orchestrator.orchestrate_turn(combat.id, turn.id)

    assert %{
             "source" => "provider",
             "envelope" => %{"state_primitives" => primitives, "casters" => [caster]},
             "result" => %{"casts" => [result_cast], "narrative_ru" => narrative},
             "ai_request_id" => _request_id
           } = stored_turn.resolution["orchestration"]

    assert "impact" in primitives
    assert caster["participant_id"] == result_cast["participant_id"]
    assert result_cast["effects"] != []
    assert narrative =~ "Запечатанные"

    assert %{kind: :combat_orchestration, status: :succeeded, combat_turn_id: turn_id} =
             Repo.one!(Request)

    assert turn_id == turn.id
    assert {:ok, _same_turn} = Orchestrator.orchestrate_turn(combat.id, turn.id)
    assert Repo.aggregate(Request, :count, :id) == 1
  end

  test "rejects malformed provider output and persists a deterministic fallback", %{
    combat: combat,
    turn: turn
  } do
    assert {:ok, stored_turn} =
             Orchestrator.orchestrate_turn(combat.id, turn.id,
               provider: InvalidOrchestrationProvider,
               model: "invalid-orchestration-test"
             )

    assert %{
             "source" => "fallback",
             "fallback_reason" => _reason,
             "result" => %{"narrative_ru" => narration, "casts" => [_ | _]}
           } = stored_turn.resolution["orchestration"]

    assert narration =~ "движок"
    assert %{kind: :combat_orchestration, status: :failed} = Repo.one!(Request)
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 12})
    |> Repo.insert!()
  end

  defp spell_fixture(character, attrs) do
    defaults = %{
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      description: "A bounded orchestration fixture spell.",
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
    }

    {:ok, spell} = Spells.create_spell(character, Map.merge(defaults, attrs))
    spell
  end

  defp activate_grimoire(character, spell) do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Bound Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, %{activate_grimoire: _grimoire}} = Grimoires.activate_grimoire(character, grimoire)
  end
end
