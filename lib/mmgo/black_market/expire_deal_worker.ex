defmodule MMGO.BlackMarket.ExpireDealWorker do
  @moduledoc "Durably closes unpaid-delivery obligations after their server deadline."

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias MMGO.BlackMarket

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deal_id" => deal_id}}) do
    case BlackMarket.expire_deal_by_id(deal_id) do
      {:ok, _result} ->
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        if deadline_pending?(changeset), do: {:snooze, 60}, else: {:discard, :invalid_deal}
    end
  end

  defp deadline_pending?(changeset) do
    Enum.any?(changeset.errors, fn
      {:status, {"deal delivery deadline has not passed", _opts}} -> true
      _other -> false
    end)
  end
end
