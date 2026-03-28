defmodule MMGO.Alchemy.CompleteBrewJobWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Alchemy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"brew_job_id" => brew_job_id}}) do
    case Alchemy.complete_brew_job_by_id(brew_job_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_brew_job}
    end
  end
end
