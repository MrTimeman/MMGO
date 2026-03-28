defmodule MMGO.Dungeons.MaintenanceWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Dungeons

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dungeon_id" => dungeon_id}}) do
    case Dungeons.maintain_dungeon_by_id(dungeon_id) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_dungeon}
    end
  end
end
