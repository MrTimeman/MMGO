defmodule MMGO.Spells.RevealCreationAttemptWorker do
  @moduledoc "Reveals a resolved ritual once its global-world-clock hour has elapsed."

  use Oban.Worker,
    queue: :default,
    max_attempts: 100,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias MMGO.Spells.Creation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}}) do
    case Creation.reveal(attempt_id) do
      {:ok, _attempt} ->
        :ok

      {:error, :not_resolved} ->
        {:snooze, 1}

      {:error, {:not_due, completes_at}} ->
        {:snooze, max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 1)}

      {:error, :not_found} ->
        {:discard, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
