defmodule MMGO.Arena.TitleChallenge do
  @moduledoc """
  One attempt on a seat at the top of the ladder.

  A challenge is a standing obligation on the defender rather than an invitation:
  it cannot be declined, and one left unanswered past `expires_at` is claimed by
  the challenger. Winning a Deputy fight does not take the Champion's seat — it
  earns the right to call them out, and `grants_until` is how long that right
  stands before it lapses.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.{Match, Profile}

  @seats [:champion, :deputy]
  @statuses [:open, :won, :lost, :claimed, :expired]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_title_challenges" do
    field :seat, Ecto.Enum, values: @seats
    field :season, :integer, default: 1
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :challenged_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :grants_until, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :challenger_profile, Profile
    belongs_to :defender_profile, Profile
    belongs_to :arena_match, Match

    timestamps(type: :utc_datetime_usec)
  end

  def seats, do: @seats
  def statuses, do: @statuses

  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [
      :seat,
      :season,
      :status,
      :challenger_profile_id,
      :defender_profile_id,
      :arena_match_id,
      :challenged_at,
      :expires_at,
      :resolved_at,
      :grants_until,
      :metadata
    ])
    |> validate_required([
      :seat,
      :season,
      :status,
      :challenger_profile_id,
      :defender_profile_id,
      :challenged_at,
      :expires_at
    ])
    |> validate_number(:season, greater_than_or_equal_to: 1)
    |> validate_distinct_parties()
    |> unique_constraint([:season, :seat],
      name: :arena_title_challenges_one_open_per_seat_index,
      message: "this seat is already being challenged"
    )
    |> unique_constraint([:season, :challenger_profile_id],
      name: :arena_title_challenges_one_open_per_challenger_index,
      message: "you already have a challenge outstanding"
    )
    |> check_constraint(:seat, name: :arena_title_challenges_seat_check)
    |> check_constraint(:status, name: :arena_title_challenges_status_check)
    |> check_constraint(:challenger_profile_id,
      name: :arena_title_challenges_distinct_parties,
      message: "cannot challenge yourself"
    )
  end

  defp validate_distinct_parties(changeset) do
    challenger = get_field(changeset, :challenger_profile_id)
    defender = get_field(changeset, :defender_profile_id)

    if not is_nil(challenger) and challenger == defender do
      add_error(changeset, :challenger_profile_id, "cannot challenge yourself")
    else
      changeset
    end
  end
end
