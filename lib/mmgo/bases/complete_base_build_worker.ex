defmodule MMGO.Bases.CompleteBaseBuildWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Bases

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"base_id" => base_id}}) do
    case Bases.complete_base_build_by_id(base_id, force: true) do
      {:ok, _result} -> :ok
      {:error, _changeset} -> {:discard, :invalid_base}
    end
  end
end
