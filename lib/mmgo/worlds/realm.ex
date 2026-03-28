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
    field :currency_code, :string
    field :public_endpoint, :string
    field :public_description, :string
    field :operator_name, :string
    field :allow_migration, :boolean, default: true
    field :population_hint, :integer
    field :metadata, :map, default: %{}

    belongs_to :entry_location, MMGO.Worlds.Location

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(realm, attrs) do
    realm
    |> cast(attrs, [
      :slug,
      :name,
      :status,
      :ruleset_version,
      :is_default,
      :currency_code,
      :public_endpoint,
      :public_description,
      :operator_name,
      :allow_migration,
      :population_hint,
      :metadata,
      :entry_location_id
    ])
    |> validate_required([:slug, :name, :status, :ruleset_version])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 48)
    |> validate_length(:name, min: 3, max: 120)
    |> validate_length(:currency_code, min: 2, max: 12)
    |> validate_number(:population_hint, greater_than_or_equal_to: 0)
    |> validate_number(:ruleset_version, greater_than: 0)
    |> unique_constraint(:slug)
    |> unique_constraint(:is_default, name: :realms_single_default_index)
  end
end
