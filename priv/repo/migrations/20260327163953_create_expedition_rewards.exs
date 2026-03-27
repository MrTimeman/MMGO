defmodule MMGO.Repo.Migrations.CreateExpeditionRewards do
  use Ecto.Migration

  def change do
    create table(:expedition_rewards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :expedition_id, references(:expeditions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :encounter_id, references(:dungeon_encounters, type: :binary_id, on_delete: :nilify_all)

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :reward_kind, :string, null: false
      add :source_type, :string, null: false
      add :reward_code, :string, null: false
      add :amount, :integer, null: false
      add :granted_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:expedition_rewards, [:expedition_id])
    create index(:expedition_rewards, [:run_id])
    create index(:expedition_rewards, [:encounter_id])
    create index(:expedition_rewards, [:character_id])
    create unique_index(:expedition_rewards, [:reward_code])
  end
end
