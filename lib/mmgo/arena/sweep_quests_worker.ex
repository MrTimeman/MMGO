defmodule MMGO.Arena.SweepQuestsWorker do
  @moduledoc """
  Nightly housekeeping for the quest board.

  Quests reset by period key, so nothing here has to run for a new day to start
  clean. What does need a job is the streak of a player who did not come back:
  nobody else is running on their behalf, and a streak that only broke when they
  returned would have been lying about them in the meantime.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias MMGO.Arena.Quests

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, summary} = Quests.sweep()

    {:ok, summary}
  end
end
