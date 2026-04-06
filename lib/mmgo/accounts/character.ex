defmodule MMGO.Accounts.Character do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Account
  alias MMGO.Worlds.{Location, Realm}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "characters" do
    field :name, :string
    field :status, Ecto.Enum, values: [:new, :active, :frozen, :retired], default: :new
    field :level, :integer, default: 1
    field :xp, :integer, default: 0
    field :import_reference, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :realm, Realm
    belongs_to :current_location, Location

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(character, attrs) do
    base_changeset(character, attrs, [])
  end

  def import_changeset(character, attrs) do
    base_changeset(character, attrs, [:import_reference])
  end

  defp base_changeset(character, attrs, extra_fields) do
    character
    |> cast(attrs, [:name, :status, :level, :xp, :metadata] ++ extra_fields)
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 40)
    |> validate_number(:level, greater_than_or_equal_to: 1)
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> unique_constraint(:name, name: :characters_realm_name_index)
    |> unique_constraint(:account_id, name: :characters_account_realm_index)
    |> unique_constraint(:import_reference, name: :characters_import_reference_index)
  end

  def travel_changeset(character, attrs) do
    character
    |> cast(attrs, [:current_location_id])
  end
end
