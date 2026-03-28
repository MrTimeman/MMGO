defmodule MMGO.Academia.Professor do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.Realm

  @statuses [:active, :retired]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academia_professors" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :appointed_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(professor, attrs) do
    professor
    |> cast(attrs, [:status, :appointed_at, :retired_at, :metadata, :character_id, :realm_id])
    |> validate_required([:status, :appointed_at, :character_id, :realm_id])
    |> unique_constraint(:character_id, name: :academia_professors_active_character_index)
  end
end
