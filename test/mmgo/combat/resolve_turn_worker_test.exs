defmodule MMGO.Combat.ResolveTurnWorkerTest do
  use MMGO.DataCase, async: true

  import Ecto.Query

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.{Action, ResolveTurnWorker, Turn}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "worker-realm", name: "Worker Realm", is_default: true})

    attacker = character_fixture(realm, "worker-attacker", "Worker Attacker")
    defender = character_fixture(realm, "worker-defender", "Worker Defender")

    %{realm: realm, attacker: attacker, defender: defender}
  end

  test "a due worker materializes waits once and resolves its exact turn", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    opened_at = DateTime.add(DateTime.utc_now(), -60, :second)

    assert {:ok, %{combat: combat, turn: turn, deadline_worker: job}} =
             Combat.create_duel(realm, %{
               opened_at: opened_at,
               participants: [
                 %{character_id: attacker.id, side: "attackers", position: 0},
                 %{character_id: defender.id, side: "defenders", position: 0}
               ]
             })

    assert job.args == %{"combat_id" => combat.id, "turn_id" => turn.id}
    assert %{"opened_at" => _, "deadline_at" => _} = Combat.turn_lifecycle(turn)

    assert :ok = ResolveTurnWorker.perform(%Oban.Job{args: job.args})

    resolved_turn = Repo.get!(Turn, turn.id)
    assert resolved_turn.status == :resolved
    assert %{"resolved_at" => _, "resolution_token" => _} = Combat.turn_lifecycle(resolved_turn)
    assert %{"source" => "fallback"} = resolved_turn.resolution["orchestration"]
    assert %{"source" => "provider"} = resolved_turn.resolution["narration"]
    assert is_binary(resolved_turn.narration)

    timeout_actions =
      Action
      |> where([action], action.combat_turn_id == ^turn.id)
      |> Repo.all()

    assert length(timeout_actions) == 2
    assert Enum.all?(timeout_actions, &(&1.action_type == :wait))
    assert Enum.all?(timeout_actions, &(Map.get(&1.payload, "source") == "turn_deadline"))

    assert %{turn_number: 2, status: :active_turn} = Combat.get_combat!(combat.id)
    assert %Turn{status: :open} = Repo.get_by(Turn, combat_id: combat.id, number: 2)

    event_count = Repo.aggregate(MMGO.Combat.Event, :count, :id)
    assert :ok = ResolveTurnWorker.perform(%Oban.Job{args: job.args})
    assert Repo.aggregate(MMGO.Combat.Event, :count, :id) == event_count
  end

  test "an early worker leaves an open turn untouched and asks Oban to retry", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    assert {:ok, %{turn: turn, deadline_worker: job}} =
             Combat.create_duel(realm, %{
               participants: [
                 %{character_id: attacker.id, side: "attackers", position: 0},
                 %{character_id: defender.id, side: "defenders", position: 0}
               ]
             })

    assert {:snooze, 1} = ResolveTurnWorker.perform(%Oban.Job{args: job.args})
    assert %Turn{status: :open} = Repo.get!(Turn, turn.id)
    assert Repo.aggregate(Action, :count, :id) == 0
  end

  test "sealing the final action enqueues an immediate worker for that exact turn", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    assert {:ok, %{combat: combat, turn: turn}} =
             Combat.create_duel(realm, %{
               participants: [
                 %{character_id: attacker.id, side: "attackers", position: 0},
                 %{character_id: defender.id, side: "defenders", position: 0}
               ]
             })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{action_type: :wait})

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    assert %Turn{status: :locked} = Repo.get!(Turn, turn.id)

    job =
      Oban.Job
      |> Repo.all()
      |> Enum.find(fn job ->
        job.worker == "MMGO.Combat.ResolveTurnWorker" and
          job.args["combat_id"] == combat.id and job.args["turn_id"] == turn.id and
          job.args["trigger"] == "all_actions"
      end)

    assert job
    assert :ok = ResolveTurnWorker.perform(%Oban.Job{args: job.args})
    assert %Turn{status: :resolved} = Repo.get!(Turn, turn.id)
    assert %{turn_number: 2, status: :active_turn} = Combat.get_combat!(combat.id)
  end

  test "turn deadlines scale with the number of ready participants", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    opened_at = ~U[2026-07-11 00:00:00Z]

    assert {:ok, %{turn: two_player_turn}} =
             Combat.create_duel(realm, %{
               opened_at: opened_at,
               participants: [
                 %{character_id: attacker.id, side: "attackers", position: 0},
                 %{character_id: defender.id, side: "defenders", position: 0}
               ]
             })

    third = character_fixture(realm, "worker-third", "Worker Third")
    fourth = character_fixture(realm, "worker-fourth", "Worker Fourth")

    assert {:ok, %{turn: four_player_turn}} =
             Combat.create_duel(realm, %{
               opened_at: opened_at,
               participants: [
                 %{character_id: attacker.id, side: "alpha", position: 0},
                 %{character_id: defender.id, side: "alpha", position: 1},
                 %{character_id: third.id, side: "beta", position: 0},
                 %{character_id: fourth.id, side: "beta", position: 1}
               ]
             })

    assert deadline_at(two_player_turn) == DateTime.add(opened_at, 45, :second)
    assert deadline_at(four_player_turn) == DateTime.add(opened_at, 65, :second)
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
  end

  defp deadline_at(turn) do
    %{"deadline_at" => deadline_at} = Combat.turn_lifecycle(turn)
    {:ok, parsed, _offset} = DateTime.from_iso8601(deadline_at)
    parsed
  end
end
