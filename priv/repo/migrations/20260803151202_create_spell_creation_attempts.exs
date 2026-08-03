defmodule MMGO.Repo.Migrations.CreateSpellCreationAttempts do
  use Ecto.Migration

  def change do
    create table(:spell_creation_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "queued"
      add :input, :map, null: false, default: %{}
      add :outcome, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completes_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :revealed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spell_creation_attempts, [:character_id])
    create index(:spell_creation_attempts, [:realm_id])
    create index(:spell_creation_attempts, [:location_id])
    create index(:spell_creation_attempts, [:character_id, :completes_at])

    create unique_index(:spell_creation_attempts, [:character_id],
             where: "status <> 'revealed'",
             name: :spell_creation_attempts_single_unrevealed_character_index
           )

    create constraint(:spell_creation_attempts, :spell_creation_attempts_status_check,
             check:
               "status IN ('queued', 'resolving', 'sealed_success', 'sealed_failure', 'revealed')"
           )

    alter table(:spells) do
      add :creation_attempt_id,
          references(:spell_creation_attempts, type: :binary_id, on_delete: :delete_all)
    end

    create unique_index(:spells, [:creation_attempt_id])
  end
end
