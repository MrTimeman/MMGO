defmodule MMGO.Crafting.CompleteCraftJobWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Crafting

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"craft_job_id" => craft_job_id}}) do
    case Crafting.complete_craft_job_by_id(craft_job_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_craft_job}
    end
  end
end
