defmodule MMGO.Dungeons.Dungeon do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Floor, LinkState, NodeOverride, Run, State}
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:draft, :active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeons" do
    field :slug, :string
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :entrance_location, Location
    has_many :floors, Floor
    has_many :link_states, LinkState
    has_many :node_overrides, NodeOverride
    has_many :runs, Run
    has_one :state, State

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(dungeon, attrs) do
    dungeon
    |> cast(attrs, [:slug, :name, :status, :metadata, :realm_id, :entrance_location_id])
    |> validate_required([:slug, :name, :status, :realm_id, :entrance_location_id])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_length(:name, min: 2, max: 120)
    |> unique_constraint(:slug, name: :dungeons_realm_slug_index)
  end
end
