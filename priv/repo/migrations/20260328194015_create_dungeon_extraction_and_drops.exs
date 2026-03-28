defmodule MMGO.Repo.Migrations.CreateDungeonExtractionAndDrops do
  use Ecto.Migration

  def change do
    create table(:dungeon_extractions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :initiator_character_id,
          references(:characters, type: :binary_id, on_delete: :nilify_all)

      add :extraction_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :completes_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:dungeon_extractions, [:run_id])

    create unique_index(:dungeon_extractions, [:run_id],
             where: "status = 'active'",
             name: :dungeon_extractions_active_run_index
           )

    create table(:dungeon_drops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :owner_character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :nilify_all)
      add :drop_kind, :string, null: false
      add :name, :string, null: false
      add :quantity, :integer, null: false
      add :durability, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:dungeon_drops, [:run_id])
    create index(:dungeon_drops, [:node_id])
    create index(:dungeon_drops, [:owner_character_id])
  end
end
