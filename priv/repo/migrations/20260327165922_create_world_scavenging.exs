defmodule MMGO.Repo.Migrations.CreateWorldScavenging do
  use Ecto.Migration

  def change do
    create table(:location_resource_caches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :nilify_all)
      add :resource_code, :string, null: false
      add :status, :string, null: false, default: "available"
      add :quantity_total, :integer, null: false, default: 0
      add :quantity_remaining, :integer, null: false, default: 0
      add :respawn_game_days, :integer, null: false, default: 0
      add :respawn_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:location_resource_caches, [:realm_id])
    create index(:location_resource_caches, [:location_id])

    create unique_index(:location_resource_caches, [:location_id, :resource_code],
             name: :location_resource_caches_location_resource_index
           )

    create table(:scavenge_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :resource_cache_id,
          references(:location_resource_caches, type: :binary_id, on_delete: :restrict),
          null: false

      add :status, :string, null: false, default: "active"
      add :quantity_requested, :integer, null: false
      add :quantity_yielded, :integer, null: false, default: 0
      add :started_at, :utc_datetime_usec, null: false
      add :completes_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scavenge_attempts, [:realm_id])
    create index(:scavenge_attempts, [:character_id])
    create index(:scavenge_attempts, [:location_id])

    create unique_index(:scavenge_attempts, [:character_id],
             where: "status = 'active'",
             name: :scavenge_attempts_single_active_character_index
           )
  end
end
