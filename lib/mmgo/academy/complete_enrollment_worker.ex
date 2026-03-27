defmodule MMGO.Academy.CompleteEnrollmentWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Academy
  alias MMGO.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"enrollment_id" => enrollment_id}}) do
    case Academy.complete_enrollment_by_id(enrollment_id, force: true) do
      {:ok, %{enrollment: enrollment, character: character}} ->
        _ = Notifications.notify_enrollment_completed(character, enrollment)
        :ok

      {:error, _changeset} ->
        {:discard, :invalid_enrollment}
    end
  end
end
