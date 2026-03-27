defmodule MMGO.Repo.Migrations.CreateDungeonContentState do
  use Ecto.Migration

  def change do
    create table(:dungeon_encounters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :combat_id, references(:combats, type: :binary_id, on_delete: :nilify_all)
      add :encounter_kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :threat_level, :integer, null: false, default: 0
      add :started_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_encounters, [:run_id, :node_id],
             name: :dungeon_encounters_run_node_index
           )

    create table(:dungeon_resource_caches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :nilify_all)
      add :resource_code, :string, null: false
      add :status, :string, null: false, default: "available"
      add :quantity_total, :integer, null: false, default: 0
      add :quantity_remaining, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_resource_caches, [:run_id, :node_id, :resource_code],
             name: :dungeon_resource_caches_run_node_resource_index
           )

    create table(:dungeon_loot_drops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :encounter_id, references(:dungeon_encounters, type: :binary_id, on_delete: :nilify_all)
      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :nilify_all)

      add :claimed_by_character_id,
          references(:characters, type: :binary_id, on_delete: :nilify_all)

      add :reward_kind, :string, null: false
      add :status, :string, null: false, default: "available"
      add :amount, :integer, null: false, default: 1
      add :claimed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:dungeon_loot_drops, [:run_id])
    create index(:dungeon_loot_drops, [:node_id])
    create index(:dungeon_loot_drops, [:encounter_id])
    create index(:dungeon_loot_drops, [:claimed_by_character_id])
  end
end
