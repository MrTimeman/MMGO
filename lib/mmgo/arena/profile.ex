defmodule MMGO.Arena.Profile do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Arena.{Match, MatchMember}

  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_profiles" do
    field :schools, {:array, Ecto.Enum}, values: @schools
    field :rating, :integer, default: 1_000
    field :season_xp, :integer, default: 0
    field :wins, :integer, default: 0
    field :losses, :integer, default: 0
    field :draws, :integer, default: 0
    field :matches_played, :integer, default: 0
    field :season, :integer, default: 1
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :character, Character
    has_many :hosted_matches, Match, foreign_key: :host_profile_id
    has_many :match_memberships, MatchMember

    timestamps(type: :utc_datetime_usec)
  end

  def schools, do: @schools

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :schools,
      :rating,
      :season_xp,
      :wins,
      :losses,
      :draws,
      :matches_played,
      :season,
      :metadata
    ])
    |> validate_required([:account_id, :character_id, :schools, :season])
    |> validate_length(:schools, is: 3)
    |> validate_subset(:schools, @schools)
    |> validate_distinct_schools()
    |> validate_number(:rating, greater_than_or_equal_to: 0)
    |> validate_number(:season_xp, greater_than_or_equal_to: 0)
    |> validate_number(:wins, greater_than_or_equal_to: 0)
    |> validate_number(:losses, greater_than_or_equal_to: 0)
    |> validate_number(:draws, greater_than_or_equal_to: 0)
    |> validate_number(:matches_played, greater_than_or_equal_to: 0)
    |> validate_number(:season, greater_than: 0)
    |> validate_match_totals()
    |> unique_constraint(:account_id)
    |> unique_constraint(:character_id)
    |> check_constraint(:schools, name: :arena_profiles_exactly_three_schools)
    |> check_constraint(:schools, name: :arena_profiles_distinct_schools)
    |> check_constraint(:schools, name: :arena_profiles_allowed_schools)
    |> check_constraint(:matches_played, name: :arena_profiles_match_totals)
  end

  defp validate_distinct_schools(changeset) do
    schools = get_field(changeset, :schools, [])

    if Enum.uniq(schools) == schools do
      changeset
    else
      add_error(changeset, :schools, "must be distinct")
    end
  end

  defp validate_match_totals(changeset) do
    matches_played = get_field(changeset, :matches_played, 0)

    recorded_results =
      get_field(changeset, :wins, 0) + get_field(changeset, :losses, 0) +
        get_field(changeset, :draws, 0)

    if matches_played == recorded_results do
      changeset
    else
      add_error(changeset, :matches_played, "must equal wins, losses, and draws")
    end
  end
end
