defmodule MMGO.Arena.TitleSeat do
  @moduledoc """
  One occupancy of a named seat at the top of the ladder.

  The Champion tier is deliberately not a rating band. There are exactly two
  seats per season — Champion and Deputy — and a row here is one holder's tenure
  in one of them. Superseded tenures are kept rather than deleted so a season's
  succession can be read back as history.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Account
  alias MMGO.Arena.Profile

  @seats [:champion, :deputy]
  # A Deputy seat is offered before it is held, and may be declined. A Champion
  # seat is taken by winning, so it is created already held.
  @statuses [:offered, :declined, :held, :vacated]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_title_seats" do
    field :seat, Ecto.Enum, values: @seats
    field :season, :integer, default: 1
    field :status, Ecto.Enum, values: @statuses, default: :offered
    field :offered_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :vacated_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :profile, Profile
    belongs_to :appointed_by_profile, Profile
    # Denormalised from the profile so the database can forbid one person
    # holding both seats with two arena characters.
    belongs_to :account, Account

    timestamps(type: :utc_datetime_usec)
  end

  def seats, do: @seats
  def statuses, do: @statuses

  def changeset(seat, attrs) do
    seat
    |> cast(attrs, [
      :seat,
      :season,
      :status,
      :profile_id,
      :account_id,
      :appointed_by_profile_id,
      :offered_at,
      :accepted_at,
      :vacated_at,
      :metadata
    ])
    |> validate_required([:seat, :season, :status, :profile_id, :account_id])
    |> validate_number(:season, greater_than_or_equal_to: 1)
    |> validate_appointment()
    |> unique_constraint([:season, :seat],
      name: :arena_title_seats_one_holder_per_seat_index,
      message: "seat is already held this season"
    )
    |> unique_constraint([:season, :profile_id],
      name: :arena_title_seats_one_seat_per_profile_index,
      message: "profile already holds a seat this season"
    )
    |> unique_constraint([:season, :account_id],
      name: :arena_title_seats_one_seat_per_account_index,
      message: "you already hold a seat this season"
    )
    |> check_constraint(:seat, name: :arena_title_seats_seat_check)
    |> check_constraint(:status, name: :arena_title_seats_status_check)
  end

  # A Champion is never appointed, and nobody may appoint themselves.
  defp validate_appointment(changeset) do
    seat = get_field(changeset, :seat)
    appointer = get_field(changeset, :appointed_by_profile_id)
    holder = get_field(changeset, :profile_id)

    cond do
      seat == :champion and not is_nil(appointer) ->
        add_error(changeset, :appointed_by_profile_id, "a champion is won, not appointed")

      not is_nil(appointer) and appointer == holder ->
        add_error(changeset, :appointed_by_profile_id, "cannot appoint yourself")

      true ->
        changeset
    end
  end
end
