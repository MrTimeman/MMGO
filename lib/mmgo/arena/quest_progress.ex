defmodule MMGO.Arena.QuestProgress do
  @moduledoc """
  One profile's progress on one quest in one period.

  The row is scoped by `period_key` — a day for a daily, an ISO week for a
  weekly — so a new period is a new row rather than an edit to an old one, and
  nothing has to reset anything at midnight for yesterday to stay yesterday.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.Profile

  @periods [:daily, :weekly]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_quest_progress" do
    field :code, :string
    field :period, Ecto.Enum, values: @periods
    field :period_key, :string
    field :progress, :integer, default: 0
    field :goal, :integer
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :profile, Profile

    timestamps(type: :utc_datetime_usec)
  end

  def periods, do: @periods

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [
      :profile_id,
      :code,
      :period,
      :period_key,
      :progress,
      :goal,
      :completed_at,
      :metadata
    ])
    |> validate_required([:profile_id, :code, :period, :period_key, :progress, :goal])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> validate_number(:goal, greater_than: 0)
    |> unique_constraint([:profile_id, :code, :period_key])
    |> check_constraint(:period, name: :arena_quest_progress_period_check)
  end
end
