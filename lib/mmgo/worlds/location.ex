defmodule MMGO.Worlds.Location do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Worlds.Realm

  @location_kinds [:city, :tower, :wilderness, :base, :dungeon_entrance]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "locations" do
    field :slug, :string
    field :name, :string
    field :kind, Ecto.Enum, values: @location_kinds
    field :x, :integer
    field :y, :integer
    field :safe_zone, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:slug, :name, :kind, :x, :y, :safe_zone, :metadata, :realm_id])
    |> validate_required([:slug, :name, :kind, :x, :y, :realm_id])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_length(:name, min: 2, max: 120)
    |> unique_constraint(:slug, name: :locations_realm_slug_index)
  end
end
