defmodule MMGO.Repo.Migrations.CreateOverworldEncounters do
  use Ecto.Migration

  def change do
    create table(:overworld_encounters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :initiator_character_id,
          references(:characters, type: :binary_id, on_delete: :restrict), null: false

      add :target_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :combat_id, references(:combats, type: :binary_id, on_delete: :nilify_all)
      add :encounter_kind, :string, null: false, default: "player"
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:overworld_encounters, [:realm_id])
    create index(:overworld_encounters, [:location_id])
    create index(:overworld_encounters, [:initiator_character_id])
    create index(:overworld_encounters, [:target_character_id])
    create index(:overworld_encounters, [:status])

    create table(:overworld_encounter_responses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :encounter_id,
          references(:overworld_encounters, type: :binary_id, on_delete: :delete_all), null: false

      add :actor_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :action, :string, null: false
      add :chosen_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:overworld_encounter_responses, [:encounter_id, :actor_character_id],
             name: :overworld_encounter_responses_unique_actor_index
           )
  end
end
