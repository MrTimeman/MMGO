defmodule MMGO.Scavenging.CompleteAttemptWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Scavenging

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}}) do
    case Scavenging.complete_attempt_by_id(attempt_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_attempt}
    end
  end
end
