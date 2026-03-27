defmodule MMGO.Economy.LedgerEntry do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Economy.EconomyAccount
  alias MMGO.Worlds.Realm

  @entry_types [
    :realm_seed,
    :transfer,
    :tax,
    :reward,
    :wager,
    :purchase,
    :black_market,
    :manual_adjustment
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ledger_entries" do
    field :entry_type, Ecto.Enum, values: @entry_types
    field :amount, :integer
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :debit_account, EconomyAccount
    belongs_to :credit_account, EconomyAccount

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :entry_type,
      :amount,
      :metadata,
      :realm_id,
      :debit_account_id,
      :credit_account_id
    ])
    |> validate_required([:entry_type, :amount, :metadata, :realm_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_account_presence()
  end

  defp validate_account_presence(changeset) do
    debit_account_id = get_field(changeset, :debit_account_id)
    credit_account_id = get_field(changeset, :credit_account_id)

    if is_nil(debit_account_id) and is_nil(credit_account_id) do
      add_error(changeset, :credit_account_id, "one side of the ledger entry must be present")
    else
      changeset
    end
  end
end
