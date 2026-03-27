defmodule MMGO.Parties.Expedition do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Parties.{ExpeditionMember, Party}
  alias MMGO.Worlds.{Location, Realm}

  @types [:dungeon]
  @statuses [:active, :completed, :aborted, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "expeditions" do
    field :expedition_type, Ecto.Enum, values: @types, default: :dungeon
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :party, Party
    belongs_to :realm, Realm
    belongs_to :location, Location
    has_many :members, ExpeditionMember

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(expedition, attrs) do
    expedition
    |> cast(attrs, [
      :expedition_type,
      :status,
      :started_at,
      :ended_at,
      :metadata,
      :party_id,
      :realm_id,
      :location_id
    ])
    |> validate_required([
      :expedition_type,
      :status,
      :started_at,
      :party_id,
      :realm_id,
      :location_id
    ])
    |> unique_constraint(:party_id, name: :expeditions_single_active_party_index)
  end
end
