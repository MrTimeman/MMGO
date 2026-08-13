defmodule MMGO.Arena.MatchMember do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.{Ladder, Match, Profile}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_match_members" do
    field :team, Ecto.Enum, values: [:a, :b]
    field :position, :integer
    field :ready, :boolean, default: false
    field :joined_at, :utc_datetime_usec
    # Written when the match settles, so history reads what happened rather than
    # recomputing it against ratings that have since moved.
    field :outcome, Ecto.Enum, values: [:win, :loss, :draw]
    field :rating_before, :integer
    field :rating_after, :integer
    field :division_before, Ecto.Enum, values: Ladder.keys()
    field :division_after, Ecto.Enum, values: Ladder.keys()
    field :season_xp_gained, :integer

    belongs_to :match, Match
    belongs_to :profile, Profile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [
      :team,
      :position,
      :ready,
      :joined_at,
      :outcome,
      :rating_before,
      :rating_after,
      :division_before,
      :division_after,
      :season_xp_gained
    ])
    |> validate_required([:match_id, :profile_id, :team, :position, :ready, :joined_at])
    |> validate_number(:position, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> unique_constraint(:profile_id, name: :arena_match_members_match_id_profile_id_index)
    |> unique_constraint(:position, name: :arena_match_members_match_id_team_position_index)
    |> check_constraint(:team, name: :arena_match_members_valid_team)
    |> check_constraint(:position, name: :arena_match_members_valid_position)
    |> check_constraint(:outcome, name: :arena_match_members_valid_outcome)
  end
end
