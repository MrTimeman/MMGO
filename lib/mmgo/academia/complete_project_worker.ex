defmodule MMGO.Academia.CompleteProjectWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Academia

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case Academia.complete_project_by_id(project_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_project}
    end
  end
end
