defmodule MMGO.Arena.MatchMember do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.{Match, Profile}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_match_members" do
    field :team, Ecto.Enum, values: [:a, :b]
    field :position, :integer
    field :ready, :boolean, default: false
    field :joined_at, :utc_datetime_usec

    belongs_to :match, Match
    belongs_to :profile, Profile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:team, :position, :ready, :joined_at])
    |> validate_required([:match_id, :profile_id, :team, :position, :ready, :joined_at])
    |> validate_number(:position, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> unique_constraint(:profile_id, name: :arena_match_members_match_id_profile_id_index)
    |> unique_constraint(:position, name: :arena_match_members_match_id_team_position_index)
    |> check_constraint(:team, name: :arena_match_members_valid_team)
    |> check_constraint(:position, name: :arena_match_members_valid_position)
  end
end
