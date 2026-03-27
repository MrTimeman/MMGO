defmodule MMGO.Worlds.Route do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Worlds.{Location, Realm}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "routes" do
    field :name, :string
    field :travel_days, :integer
    field :risk_level, :integer, default: 0
    field :bidirectional, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :origin_location, Location
    belongs_to :destination_location, Location

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(route, attrs) do
    route
    |> cast(attrs, [
      :name,
      :travel_days,
      :risk_level,
      :bidirectional,
      :metadata,
      :realm_id,
      :origin_location_id,
      :destination_location_id
    ])
    |> validate_required([
      :name,
      :travel_days,
      :risk_level,
      :bidirectional,
      :realm_id,
      :origin_location_id,
      :destination_location_id
    ])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_number(:travel_days, greater_than: 0)
    |> validate_number(:risk_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_distinct_locations()
    |> unique_constraint(:origin_location_id, name: :routes_origin_destination_index)
  end

  defp validate_distinct_locations(changeset) do
    if get_field(changeset, :origin_location_id) == get_field(changeset, :destination_location_id) do
      add_error(changeset, :destination_location_id, "must differ from the origin location")
    else
      changeset
    end
  end
end
