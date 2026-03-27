defmodule MMGO.Grimoires.Grimoire do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Grimoires.GrimoireEntry
  alias MMGO.Worlds.Realm

  @statuses [:draft, :sealed, :active]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "grimoires" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :capacity, :integer, default: 5
    field :weight, :integer, default: 1
    field :metadata, :map, default: %{}

    belongs_to :owner_character, Character
    belongs_to :realm, Realm
    has_many :entries, GrimoireEntry

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(grimoire, attrs) do
    grimoire
    |> cast(attrs, [:name, :status, :capacity, :weight, :metadata, :owner_character_id, :realm_id])
    |> validate_required([:name, :status, :capacity, :weight, :owner_character_id, :realm_id])
    |> validate_length(:name, min: 3, max: 120)
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 45)
    |> validate_number(:weight, greater_than: 0)
    |> unique_constraint(:owner_character_id, name: :grimoires_active_owner_index)
  end
end
