defmodule MMGO.Bases.Base do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Bases.StorageItem
  alias MMGO.Worlds.{Location, Realm}

  @kinds [:city_purchase, :custom_build]
  @statuses [:building, :active, :abandoned]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bases" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses, default: :building
    field :storage_weight_capacity, :integer, default: 0
    field :build_started_at, :utc_datetime_usec
    field :ready_at, :utc_datetime_usec
    field :built_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :owner_character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    has_many :storage_items, StorageItem

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(base, attrs) do
    base
    |> cast(attrs, [
      :name,
      :kind,
      :status,
      :storage_weight_capacity,
      :build_started_at,
      :ready_at,
      :built_at,
      :metadata,
      :owner_character_id,
      :realm_id,
      :location_id
    ])
    |> validate_required([
      :name,
      :kind,
      :status,
      :storage_weight_capacity,
      :owner_character_id,
      :realm_id,
      :location_id
    ])
    |> validate_length(:name, min: 3, max: 120)
    |> validate_number(:storage_weight_capacity, greater_than: 0)
    |> validate_ready_fields()
  end

  defp validate_ready_fields(changeset) do
    case get_field(changeset, :status) do
      :building -> validate_required(changeset, [:build_started_at, :ready_at])
      :active -> changeset
      _other -> changeset
    end
  end
end
