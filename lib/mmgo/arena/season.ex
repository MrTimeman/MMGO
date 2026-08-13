defmodule MMGO.Arena.Season do
  @moduledoc """
  One season of the ladder.

  Exactly one season is active at a time, enforced by the database rather than
  by convention, so nothing can quietly run two ladders at once.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.SeasonAward

  @statuses [:active, :finished]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_seasons" do
    field :number, :integer
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    has_many :awards, SeasonAward

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(season, attrs) do
    season
    |> cast(attrs, [:number, :status, :started_at, :ended_at, :metadata])
    |> validate_required([:number, :status, :started_at])
    |> validate_number(:number, greater_than_or_equal_to: 1)
    |> unique_constraint(:number)
    |> unique_constraint(:status,
      name: :arena_seasons_one_active_index,
      message: "a season is already running"
    )
    |> check_constraint(:status, name: :arena_seasons_status_check)
  end
end
