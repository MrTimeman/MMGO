defmodule MMGO.Notifications.DeliveryWorker do
  use Oban.Worker, queue: :telegram, max_attempts: 5

  alias MMGO.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id}}) do
    case Notifications.deliver_notification_by_id(notification_id) do
      {:ok, _notification} -> :ok
      {:error, %MMGO.Notifications.Notification{status: :failed}} -> {:discard, :delivery_failed}
      {:error, _changeset} -> {:discard, :invalid_notification}
    end
  end
end
