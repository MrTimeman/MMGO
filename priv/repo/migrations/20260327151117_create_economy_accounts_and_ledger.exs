defmodule MMGO.Repo.Migrations.CreateEconomyAccountsAndLedger do
  use Ecto.Migration

  def change do
    create table(:economy_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict)
      add :owner_type, :string, null: false
      add :current_balance, :bigint, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:economy_accounts, [:realm_id])

    create unique_index(:economy_accounts, [:realm_id],
             where: "owner_type = 'treasury'",
             name: :economy_accounts_single_treasury_index
           )

    create unique_index(:economy_accounts, [:character_id],
             where: "character_id IS NOT NULL",
             name: :economy_accounts_character_index
           )

    create table(:ledger_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :entry_type, :string, null: false
      add :amount, :bigint, null: false
      add :metadata, :map, null: false, default: %{}
      add :debit_account_id, references(:economy_accounts, type: :binary_id, on_delete: :restrict)

      add :credit_account_id,
          references(:economy_accounts, type: :binary_id, on_delete: :restrict)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ledger_entries, [:realm_id])
    create index(:ledger_entries, [:entry_type])
    create index(:ledger_entries, [:debit_account_id])
    create index(:ledger_entries, [:credit_account_id])
  end
end
