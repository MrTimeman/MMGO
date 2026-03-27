defmodule MMGO.Scavenging.CompleteAttemptWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Notifications
  alias MMGO.Scavenging

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}}) do
    case Scavenging.complete_attempt_by_id(attempt_id, force: true) do
      {:ok, %{attempt: attempt, character: character}} ->
        _ = Notifications.notify_scavenge_completed(character, attempt)
        :ok

      {:error, _changeset} ->
        {:discard, :invalid_attempt}
    end
  end
end
