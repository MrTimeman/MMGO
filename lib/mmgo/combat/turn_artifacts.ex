defmodule MMGO.Combat.TurnArtifacts do
  @moduledoc """
  Persists the bounded orchestration and readable narration for one resolved turn.

  It is deliberately separate from the mechanical resolver: provider I/O stays
  outside row locks, and every entrypoint (Oban, Telegram, or a legacy facade)
  can converge on the same durable artifacts before mode settlement.
  """

  alias MMGO.Combat.{Narrator, Orchestrator, Turn}
  alias MMGO.Repo

  def persist(combat_id, turn_id) when is_binary(combat_id) and is_binary(turn_id) do
    with %Turn{status: :resolved} = turn <- Repo.get(Turn, turn_id),
         {:ok, _turn} <- Orchestrator.orchestrate_turn(combat_id, turn_id),
         {:ok, _turn} <- Narrator.narrate_turn(combat_id, turn.number) do
      :ok
    else
      nil -> :ok
      %Turn{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def persist(_combat_id, _turn_id), do: :ok
end
