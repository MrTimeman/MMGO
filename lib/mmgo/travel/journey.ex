defmodule MMGO.Travel.Journey do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.{Location, Realm, Route}

  @statuses [:active, :arrived, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "journeys" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :travel_days, :integer
    field :food_units_consumed, :integer, default: 0
    field :encumbrance_penalty_days, :integer, default: 0
    field :carried_weight, :integer, default: 0
    field :carry_capacity, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :arrival_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :route, Route
    belongs_to :from_location, Location
    belongs_to :to_location, Location

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(journey, attrs) do
    journey
    |> cast(attrs, [
      :status,
      :travel_days,
      :food_units_consumed,
      :encumbrance_penalty_days,
      :carried_weight,
      :carry_capacity,
      :started_at,
      :arrival_at,
      :completed_at,
      :metadata,
      :character_id,
      :realm_id,
      :route_id,
      :from_location_id,
      :to_location_id
    ])
    |> validate_required([
      :status,
      :travel_days,
      :food_units_consumed,
      :encumbrance_penalty_days,
      :carried_weight,
      :carry_capacity,
      :started_at,
      :arrival_at,
      :character_id,
      :realm_id,
      :route_id,
      :from_location_id,
      :to_location_id
    ])
    |> validate_number(:travel_days, greater_than: 0)
    |> validate_number(:food_units_consumed, greater_than_or_equal_to: 0)
    |> validate_number(:encumbrance_penalty_days, greater_than_or_equal_to: 0)
    |> validate_number(:carried_weight, greater_than_or_equal_to: 0)
    |> validate_number(:carry_capacity, greater_than_or_equal_to: 0)
    |> validate_distinct_locations()
    |> unique_constraint(:character_id, name: :journeys_single_active_character_index)
  end

  defp validate_distinct_locations(changeset) do
    if get_field(changeset, :from_location_id) == get_field(changeset, :to_location_id) do
      add_error(changeset, :to_location_id, "must differ from the departure location")
    else
      changeset
    end
  end
end
