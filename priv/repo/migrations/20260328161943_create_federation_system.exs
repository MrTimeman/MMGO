defmodule MMGO.Repo.Migrations.CreateFederationSystem do
  use Ecto.Migration

  def change do
    alter table(:realms) do
      add :currency_code, :string
      add :public_endpoint, :string
      add :public_description, :text
      add :operator_name, :string
      add :allow_migration, :boolean, null: false, default: true
      add :population_hint, :integer
      add :entry_location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:realms, [:entry_location_id])

    create table(:federation_exchange_rates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :source_realm_id, references(:realms, type: :binary_id, on_delete: :delete_all),
        null: false

      add :destination_realm_id, references(:realms, type: :binary_id, on_delete: :delete_all),
        null: false

      add :numerator, :bigint, null: false
      add :denominator, :bigint, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:federation_exchange_rates, [:source_realm_id, :destination_realm_id],
             name: :federation_exchange_rates_pair_index
           )

    create table(:federation_migrations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :origin_realm_id, references(:realms, type: :binary_id, on_delete: :restrict),
        null: false

      add :destination_realm_id, references(:realms, type: :binary_id, on_delete: :restrict),
        null: false

      add :origin_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :destination_character_id,
          references(:characters, type: :binary_id, on_delete: :restrict), null: false

      add :status, :string, null: false, default: "active"
      add :currency_amount, :bigint, null: false
      add :converted_currency_amount, :bigint, null: false
      add :source_level, :integer, null: false
      add :destination_level, :integer, null: false
      add :source_xp, :bigint, null: false
      add :destination_xp, :bigint, null: false
      add :freeze_started_at, :utc_datetime_usec, null: false
      add :freeze_ends_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :passive_xp_awarded, :bigint, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:federation_migrations, [:account_id])
    create index(:federation_migrations, [:origin_character_id])
    create index(:federation_migrations, [:destination_character_id])
    create index(:federation_migrations, [:status])

    create unique_index(:federation_migrations, [:origin_character_id],
             where: "status = 'active'",
             name: :federation_migrations_active_origin_character_index
           )
  end
end
