defmodule MMGO.Combat.ResolveTurnWorker do
  @moduledoc """
  Resolves one persisted combat turn after its authoritative deadline.

  The job names both combat and turn, so a retry can never accidentally apply
  itself to a later turn that happened to open in the meantime.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Combat
  alias MMGO.Combat.Resolution
  alias MMGO.Combat.TurnArtifacts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"combat_id" => combat_id, "turn_id" => turn_id}} = job) do
    result =
      case Map.get(job.args, "trigger") do
        "all_actions" -> Combat.resolve_locked_turn(combat_id, turn_id)
        _other -> Combat.resolve_due_turn(combat_id, turn_id)
      end

    case result do
      {:ok, _combat} ->
        complete_turn(combat_id, turn_id)

      {:error, :turn_not_due} ->
        {:snooze, 1}

      {:error, reason} when reason in [:turn_closed, :turn_not_found, :combat_not_found] ->
        complete_turn(combat_id, turn_id)

      {:error, _reason} ->
        {:discard, :invalid_turn}
    end
  end

  defp complete_turn(combat_id, turn_id) do
    with :ok <- TurnArtifacts.persist(combat_id, turn_id) do
      finalize_finished_combat(combat_id)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_finished_combat(combat_id) do
    case Combat.get_combat(combat_id) do
      %{status: :finished} = combat ->
        case Resolution.finalize(combat) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _other ->
        :ok
    end
  end
end
