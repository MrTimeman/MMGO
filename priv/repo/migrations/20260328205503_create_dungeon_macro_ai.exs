defmodule MMGO.Repo.Migrations.CreateDungeonMacroAi do
  use Ecto.Migration

  def change do
    create table(:dungeon_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :cycle_number, :integer, null: false, default: 0
      add :active_run_count_snapshot, :integer, null: false, default: 0
      add :pressure_level, :integer, null: false, default: 0
      add :anomaly_level, :integer, null: false, default: 0
      add :last_maintained_at, :utc_datetime_usec
      add :next_maintenance_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_states, [:dungeon_id])

    create table(:dungeon_node_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "stable"
      add :threat_bias, :integer, null: false, default: 0
      add :resource_bias, :integer, null: false, default: 0
      add :anomaly_tag, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_node_overrides, [:dungeon_id, :node_id],
             name: :dungeon_node_overrides_dungeon_node_index
           )

    create table(:dungeon_link_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :link_id, references(:dungeon_links, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_link_states, [:dungeon_id, :link_id],
             name: :dungeon_link_states_dungeon_link_index
           )
  end
end
