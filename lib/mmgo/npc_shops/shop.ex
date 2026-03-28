defmodule MMGO.NPCShops.Shop do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.NPCShops.Offer
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:active, :inactive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "npc_shops" do
    field :code, :string
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :location, Location
    has_many :offers, Offer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(shop, attrs) do
    shop
    |> cast(attrs, [:code, :name, :status, :description, :metadata, :realm_id, :location_id])
    |> validate_required([:code, :name, :status, :realm_id, :location_id])
    |> validate_length(:code, min: 3, max: 80)
    |> validate_length(:name, min: 3, max: 120)
    |> unique_constraint(:code, name: :npc_shops_location_code_index)
  end
end
