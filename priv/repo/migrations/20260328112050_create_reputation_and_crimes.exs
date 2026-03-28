defmodule MMGO.Repo.Migrations.CreateReputationAndCrimes do
  use Ecto.Migration

  def change do
    create table(:reputation_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :reputation_score, :integer, null: false, default: 0
      add :crime_count, :integer, null: false, default: 0
      add :outstanding_fine, :bigint, null: false, default: 0
      add :npc_hostility_level, :integer, null: false, default: 0
      add :market_ban_until, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reputation_profiles, [:realm_id])
    create unique_index(:reputation_profiles, [:character_id])

    create table(:crime_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :profile_id, references(:reputation_profiles, type: :binary_id, on_delete: :nilify_all)
      add :crime_type, :string, null: false
      add :status, :string, null: false, default: "open"
      add :severity, :integer, null: false
      add :reputation_delta, :integer, null: false
      add :fine_amount, :bigint, null: false, default: 0
      add :recorded_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:crime_records, [:character_id])
    create index(:crime_records, [:realm_id])
    create index(:crime_records, [:crime_type])
    create index(:crime_records, [:status])
  end
end
