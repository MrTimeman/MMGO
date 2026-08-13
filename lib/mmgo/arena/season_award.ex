defmodule MMGO.Arena.SeasonAward do
  @moduledoc """
  Where one profile finished one season.

  This is the reward: a permanent record of the division held and the seat sat
  in, kept after the reset has taken the rating away. Coins are paid on top when
  the realm's treasury can afford them, and the row says how many were.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.{Ladder, Profile, Season}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_season_awards" do
    field :division, Ecto.Enum, values: Ladder.keys()
    field :rating, :integer
    field :wins, :integer, default: 0
    field :losses, :integer, default: 0
    field :seat, Ecto.Enum, values: [:champion, :deputy]
    field :coins_awarded, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :season, Season
    belongs_to :profile, Profile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(award, attrs) do
    award
    |> cast(attrs, [
      :season_id,
      :profile_id,
      :division,
      :rating,
      :wins,
      :losses,
      :seat,
      :coins_awarded,
      :metadata
    ])
    |> validate_required([:season_id, :profile_id, :division, :rating])
    |> unique_constraint([:season_id, :profile_id])
  end
end
