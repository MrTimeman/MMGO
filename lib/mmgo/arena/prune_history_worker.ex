defmodule MMGO.Arena.PruneHistoryWorker do
  @moduledoc """
  Forgets arena fights older than the retention window.

  Replays are cheap to keep and cheap to read, but not free forever: every turn
  of every fight is a row. This runs nightly so the record stays a recent
  memory rather than an archive.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias MMGO.Arena.History

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, pruned} = History.prune()

    {:ok, %{pruned: pruned}}
  end
end
