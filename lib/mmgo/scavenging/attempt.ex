defmodule MMGO.Scavenging.Attempt do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Scavenging.ResourceCache
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:active, :completed, :failed, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scavenge_attempts" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :quantity_requested, :integer, default: 0
    field :quantity_yielded, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    belongs_to :resource_cache, ResourceCache

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :status,
      :quantity_requested,
      :quantity_yielded,
      :started_at,
      :completes_at,
      :completed_at,
      :metadata,
      :character_id,
      :realm_id,
      :location_id,
      :resource_cache_id
    ])
    |> validate_required([
      :status,
      :quantity_requested,
      :quantity_yielded,
      :started_at,
      :completes_at,
      :character_id,
      :realm_id,
      :location_id,
      :resource_cache_id
    ])
    |> validate_number(:quantity_requested, greater_than: 0)
    |> validate_number(:quantity_yielded, greater_than_or_equal_to: 0)
    |> validate_yield_bound()
    |> unique_constraint(:character_id, name: :scavenge_attempts_single_active_character_index)
  end

  defp validate_yield_bound(changeset) do
    requested = get_field(changeset, :quantity_requested, 0)
    yielded = get_field(changeset, :quantity_yielded, 0)

    if yielded > requested do
      add_error(changeset, :quantity_yielded, "must not exceed the requested quantity")
    else
      changeset
    end
  end
end
