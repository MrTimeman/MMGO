defmodule MMGO.Federation.Migration do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Federation.RemoteRealm
  alias MMGO.Worlds.Realm

  @statuses [:active, :completed, :cancelled]
  @modes [:local, :remote]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "federation_migrations" do
    field :mode, Ecto.Enum, values: @modes, default: :local
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :currency_amount, :integer
    field :converted_currency_amount, :integer
    field :source_level, :integer
    field :destination_level, :integer
    field :source_xp, :integer
    field :destination_xp, :integer
    field :freeze_started_at, :utc_datetime_usec
    field :freeze_ends_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :passive_xp_awarded, :integer, default: 0
    field :destination_character_name, :string
    field :destination_external_ref, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :origin_realm, Realm
    belongs_to :destination_realm, Realm
    belongs_to :remote_realm, RemoteRealm
    belongs_to :origin_character, Character
    belongs_to :destination_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(migration, attrs) do
    migration
    |> cast(attrs, [
      :status,
      :mode,
      :currency_amount,
      :converted_currency_amount,
      :source_level,
      :destination_level,
      :source_xp,
      :destination_xp,
      :freeze_started_at,
      :freeze_ends_at,
      :completed_at,
      :passive_xp_awarded,
      :destination_character_name,
      :destination_external_ref,
      :metadata,
      :account_id,
      :origin_realm_id,
      :destination_realm_id,
      :remote_realm_id,
      :origin_character_id,
      :destination_character_id
    ])
    |> validate_required([
      :status,
      :mode,
      :currency_amount,
      :converted_currency_amount,
      :source_level,
      :destination_level,
      :source_xp,
      :destination_xp,
      :freeze_started_at,
      :freeze_ends_at,
      :passive_xp_awarded,
      :account_id,
      :origin_realm_id,
      :origin_character_id,
      :destination_character_name
    ])
    |> validate_number(:currency_amount, greater_than: 0)
    |> validate_number(:converted_currency_amount, greater_than_or_equal_to: 0)
    |> validate_number(:source_level, greater_than: 0)
    |> validate_number(:destination_level, greater_than: 0)
    |> validate_number(:source_xp, greater_than_or_equal_to: 0)
    |> validate_number(:destination_xp, greater_than_or_equal_to: 0)
    |> validate_number(:passive_xp_awarded, greater_than_or_equal_to: 0)
    |> validate_destination_fields()
    |> validate_distinct_realms()
    |> unique_constraint(:origin_character_id,
      name: :federation_migrations_active_origin_character_index
    )
  end

  defp validate_destination_fields(changeset) do
    case get_field(changeset, :mode) do
      :local -> validate_required(changeset, [:destination_realm_id, :destination_character_id])
      :remote -> validate_required(changeset, [:remote_realm_id])
      _other -> changeset
    end
  end

  defp validate_distinct_realms(changeset) do
    case get_field(changeset, :mode) do
      :local ->
        if get_field(changeset, :origin_realm_id) == get_field(changeset, :destination_realm_id) do
          add_error(changeset, :destination_realm_id, "must differ from the origin realm")
        else
          changeset
        end

      :remote ->
        changeset

      _other ->
        changeset
    end
  end
end
