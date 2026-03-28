defmodule MMGO.Federation.ExchangeRate do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Worlds.Realm

  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "federation_exchange_rates" do
    field :numerator, :integer
    field :denominator, :integer
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :source_realm, Realm
    belongs_to :destination_realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(exchange_rate, attrs) do
    exchange_rate
    |> cast(attrs, [
      :numerator,
      :denominator,
      :status,
      :metadata,
      :source_realm_id,
      :destination_realm_id
    ])
    |> validate_required([
      :numerator,
      :denominator,
      :status,
      :source_realm_id,
      :destination_realm_id
    ])
    |> validate_number(:numerator, greater_than: 0)
    |> validate_number(:denominator, greater_than: 0)
    |> validate_distinct_realms()
    |> unique_constraint(:source_realm_id, name: :federation_exchange_rates_pair_index)
  end

  defp validate_distinct_realms(changeset) do
    if get_field(changeset, :source_realm_id) == get_field(changeset, :destination_realm_id) do
      add_error(changeset, :destination_realm_id, "must differ from the source realm")
    else
      changeset
    end
  end
end
