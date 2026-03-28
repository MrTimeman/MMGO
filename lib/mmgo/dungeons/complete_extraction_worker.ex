defmodule MMGO.Dungeons.CompleteExtractionWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Dungeons

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"extraction_id" => extraction_id}}) do
    case Dungeons.complete_extraction_by_id(extraction_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_extraction}
    end
  end
end
