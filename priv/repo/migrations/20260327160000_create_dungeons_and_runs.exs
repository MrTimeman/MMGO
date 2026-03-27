defmodule MMGO.Repo.Migrations.CreateDungeonsAndRuns do
  use Ecto.Migration

  def change do
    create table(:dungeons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :entrance_location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeons, [:realm_id, :slug], name: :dungeons_realm_slug_index)

    create table(:dungeon_floors, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :number, :integer, null: false
      add :name, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_floors, [:dungeon_id, :number],
             name: :dungeon_floors_number_index
           )

    create table(:dungeon_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :floor_id, references(:dungeon_floors, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slug, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :threat_level, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_nodes, [:floor_id, :slug], name: :dungeon_nodes_floor_slug_index)

    create table(:dungeon_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :from_node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :to_node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :travel_cost, :integer, null: false, default: 1
      add :bidirectional, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_links, [:from_node_id, :to_node_id],
             name: :dungeon_links_from_to_index
           )

    create table(:dungeon_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :expedition_id, references(:expeditions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :dungeon_id, references(:dungeons, type: :binary_id, on_delete: :restrict), null: false

      add :current_floor_id, references(:dungeon_floors, type: :binary_id, on_delete: :restrict),
        null: false

      add :current_node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "active"
      add :steps_taken, :integer, null: false, default: 0
      add :started_at, :utc_datetime_usec, null: false
      add :last_progressed_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_runs, [:expedition_id],
             where: "status = 'active'",
             name: :dungeon_runs_single_active_expedition_index
           )

    create table(:dungeon_node_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:dungeon_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:dungeon_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "current"
      add :encounter_status, :string, null: false, default: "pending"
      add :resource_status, :string, null: false, default: "unknown"
      add :visit_count, :integer, null: false, default: 1
      add :entered_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dungeon_node_states, [:run_id, :node_id],
             name: :dungeon_node_states_run_node_index
           )
  end
end
