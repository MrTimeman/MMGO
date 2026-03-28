defmodule MMGO.Federation.RemoteRealm do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Federation.Ruleset

  @statuses [:active, :inactive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "federation_remote_realms" do
    field :slug, :string
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :manifest_url, :string
    field :public_endpoint, :string
    field :currency_code, :string
    field :public_description, :string
    field :operator_name, :string
    field :allow_migration, :boolean, default: true
    field :population_hint, :integer, default: 1
    field :ruleset_version, :integer, default: 1
    field :ruleset, :map, default: %{}
    field :entry_location_slug, :string
    field :access_token, :string
    field :last_synced_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(remote_realm, attrs) do
    remote_realm
    |> cast(attrs, [
      :slug,
      :name,
      :status,
      :manifest_url,
      :public_endpoint,
      :currency_code,
      :public_description,
      :operator_name,
      :allow_migration,
      :population_hint,
      :ruleset_version,
      :ruleset,
      :entry_location_slug,
      :access_token,
      :last_synced_at,
      :metadata
    ])
    |> validate_required([
      :slug,
      :name,
      :status,
      :manifest_url,
      :public_endpoint,
      :currency_code,
      :allow_migration,
      :population_hint,
      :ruleset_version,
      :ruleset
    ])
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_length(:name, min: 3, max: 120)
    |> validate_length(:currency_code, min: 2, max: 12)
    |> validate_number(:population_hint, greater_than_or_equal_to: 1)
    |> validate_ruleset()
    |> unique_constraint(:slug)
    |> unique_constraint(:manifest_url)
    |> unique_constraint(:public_endpoint)
  end

  defp validate_ruleset(changeset) do
    case Ruleset.validate(get_field(changeset, :ruleset, %{})) do
      {:ok, ruleset} -> put_change(changeset, :ruleset, ruleset)
      {:error, message} -> add_error(changeset, :ruleset, message)
    end
  end
end
