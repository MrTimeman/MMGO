defmodule MMGO.Scavenging.ResourceCache do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Inventory.ItemTemplate
  alias MMGO.Scavenging.Attempt
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:available, :depleted, :respawning]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "location_resource_caches" do
    field :resource_code, :string
    field :status, Ecto.Enum, values: @statuses, default: :available
    field :quantity_total, :integer, default: 0
    field :quantity_remaining, :integer, default: 0
    field :respawn_game_days, :integer, default: 0
    field :respawn_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :location, Location
    belongs_to :item_template, ItemTemplate
    has_many :attempts, Attempt

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(resource_cache, attrs) do
    resource_cache
    |> cast(attrs, [
      :resource_code,
      :status,
      :quantity_total,
      :quantity_remaining,
      :respawn_game_days,
      :respawn_at,
      :metadata,
      :realm_id,
      :location_id,
      :item_template_id
    ])
    |> validate_required([
      :resource_code,
      :status,
      :quantity_total,
      :quantity_remaining,
      :respawn_game_days,
      :realm_id,
      :location_id
    ])
    |> validate_length(:resource_code, min: 2, max: 64)
    |> validate_number(:quantity_total, greater_than_or_equal_to: 0)
    |> validate_number(:quantity_remaining, greater_than_or_equal_to: 0)
    |> validate_number(:respawn_game_days, greater_than_or_equal_to: 0)
    |> validate_remaining_bound()
    |> unique_constraint(:resource_code, name: :location_resource_caches_location_resource_index)
  end

  defp validate_remaining_bound(changeset) do
    total = get_field(changeset, :quantity_total, 0)
    remaining = get_field(changeset, :quantity_remaining, 0)

    if remaining > total do
      add_error(changeset, :quantity_remaining, "must not exceed the total quantity")
    else
      changeset
    end
  end
end
