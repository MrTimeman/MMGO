defmodule MMGO.Repo.Migrations.CreateInitialCoreTables do
  use Ecto.Migration

  def change do
    create table(:realms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :ruleset_version, :integer, null: false, default: 1
      add :is_default, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:realms, [:slug])

    create unique_index(:realms, [:is_default],
             where: "is_default = true",
             name: :realms_single_default_index
           )

    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string, null: false
      add :handle, :string, null: false
      add :status, :string, null: false, default: "active"
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:handle])

    create table(:telegram_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :telegram_user_id, :bigint, null: false
      add :telegram_username, :string
      add :first_name, :string
      add :last_name, :string
      add :language_code, :string
      add :is_bot, :boolean, null: false, default: false
      add :auth_data, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telegram_identities, [:account_id])
    create unique_index(:telegram_identities, [:telegram_user_id])

    create table(:characters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "new"
      add :level, :integer, null: false, default: 1
      add :xp, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:characters, [:account_id, :realm_id],
             name: :characters_account_realm_index
           )

    create unique_index(:characters, [:realm_id, :name], name: :characters_realm_name_index)
  end
end
