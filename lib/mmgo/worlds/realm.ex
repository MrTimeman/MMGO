defmodule MMGO.Worlds.Realm do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "realms" do
    field :slug, :string
    field :name, :string
    field :status, Ecto.Enum, values: [:active, :maintenance, :archived], default: :active
    field :ruleset_version, :integer, default: 1
    field :is_default, :boolean, default: false
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(realm, attrs) do
    realm
    |> cast(attrs, [:slug, :name, :status, :ruleset_version, :is_default, :metadata])
    |> validate_required([:slug, :name, :status, :ruleset_version])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 48)
    |> validate_length(:name, min: 3, max: 120)
    |> validate_number(:ruleset_version, greater_than: 0)
    |> unique_constraint(:slug)
    |> unique_constraint(:is_default, name: :realms_single_default_index)
  end
end
