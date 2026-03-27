defmodule MMGO.Parties.Party do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Parties.{Expedition, Membership}
  alias MMGO.Worlds.Realm

  @statuses [:active, :disbanded]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "parties" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :leader_character, Character
    has_many :memberships, Membership
    has_many :expeditions, Expedition

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(party, attrs) do
    party
    |> cast(attrs, [:name, :status, :metadata, :realm_id, :leader_character_id])
    |> validate_required([:name, :status, :realm_id, :leader_character_id])
    |> validate_length(:name, min: 2, max: 120)
  end
end
