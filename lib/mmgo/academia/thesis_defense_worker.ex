defmodule MMGO.Academia.ThesisDefenseWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Academia

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case Academia.run_thesis_defense(project_id) do
      {:ok, _result} ->
        :ok

      {:error, {:defense_not_closed, closes_at}} ->
        {:snooze, max(DateTime.diff(closes_at, DateTime.utc_now(), :second), 1)}

      {:error, _changeset} ->
        {:discard, :invalid_project}
    end
  end
end
