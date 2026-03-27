defmodule MMGO.Travel.CompleteJourneyWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Notifications
  alias MMGO.Travel

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"journey_id" => journey_id}}) do
    case Travel.complete_journey_by_id(journey_id, force: true) do
      {:ok, %{journey: journey, character: character}} ->
        _ = Notifications.notify_journey_arrived(character, journey)
        :ok

      {:error, _changeset} ->
        {:discard, :invalid_journey}
    end
  end
end
