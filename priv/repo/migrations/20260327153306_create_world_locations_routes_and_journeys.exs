defmodule MMGO.Repo.Migrations.CreateWorldLocationsRoutesAndJourneys do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :safe_zone, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:locations, [:realm_id, :slug], name: :locations_realm_slug_index)

    create table(:routes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :origin_location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :destination_location_id,
          references(:locations, type: :binary_id, on_delete: :restrict), null: false

      add :name, :string, null: false
      add :travel_days, :integer, null: false
      add :risk_level, :integer, null: false, default: 0
      add :bidirectional, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:routes, [:origin_location_id, :destination_location_id],
             name: :routes_origin_destination_index
           )

    alter table(:characters) do
      add :current_location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:characters, [:current_location_id])

    create table(:journeys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :route_id, references(:routes, type: :binary_id, on_delete: :restrict), null: false

      add :from_location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :to_location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "active"
      add :travel_days, :integer, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :arrival_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:journeys, [:realm_id])
    create index(:journeys, [:character_id])

    create unique_index(:journeys, [:character_id],
             where: "status = 'active'",
             name: :journeys_single_active_character_index
           )
  end
end
