defmodule MMGO.Economy.EconomyAccount do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Economy.LedgerEntry
  alias MMGO.Worlds.Realm

  @owner_types [:treasury, :character]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "economy_accounts" do
    field :owner_type, Ecto.Enum, values: @owner_types
    field :current_balance, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :character, Character
    has_many :debit_entries, LedgerEntry, foreign_key: :debit_account_id
    has_many :credit_entries, LedgerEntry, foreign_key: :credit_account_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:owner_type, :current_balance, :metadata, :realm_id, :character_id])
    |> validate_required([:owner_type, :current_balance, :realm_id])
    |> validate_number(:current_balance, greater_than_or_equal_to: 0)
    |> validate_owner_link()
    |> unique_constraint(:realm_id, name: :economy_accounts_single_treasury_index)
    |> unique_constraint(:character_id, name: :economy_accounts_character_index)
  end

  defp validate_owner_link(changeset) do
    case get_field(changeset, :owner_type) do
      :treasury -> validate_absence(changeset, :character_id)
      :character -> validate_required(changeset, [:character_id])
      _other -> changeset
    end
  end

  defp validate_absence(changeset, field) do
    if get_field(changeset, field) do
      add_error(changeset, field, "must be empty for treasury accounts")
    else
      changeset
    end
  end
end
