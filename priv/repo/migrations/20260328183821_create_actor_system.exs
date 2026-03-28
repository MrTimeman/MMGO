defmodule MMGO.Repo.Migrations.CreateActorSystem do
  use Ecto.Migration

  def change do
    create table(:actor_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :code, :string, null: false
      add :name, :string, null: false
      add :role, :string, null: false
      add :combat_level, :integer, null: false
      add :base_hp, :integer, null: false
      add :behavior_profile, :string, null: false, default: "aggressive"
      add :tags, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:actor_templates, [:realm_id, :code],
             name: :actor_templates_realm_code_index
           )

    create table(:dungeon_encounter_spawns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :encounter_id,
          references(:dungeon_encounters, type: :binary_id, on_delete: :delete_all), null: false

      add :actor_template_id,
          references(:actor_templates, type: :binary_id, on_delete: :restrict), null: false

      add :quantity, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :current_hp, :integer, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:dungeon_encounter_spawns, [:encounter_id])
    create index(:dungeon_encounter_spawns, [:actor_template_id])

    execute("ALTER TABLE combat_participants ALTER COLUMN character_id DROP NOT NULL")

    alter table(:combat_participants) do
      add :actor_template_id,
          references(:actor_templates, type: :binary_id, on_delete: :nilify_all)

      add :display_name, :string
      add :combat_level, :integer
      add :metadata, :map, null: false, default: %{}
    end

    create index(:combat_participants, [:actor_template_id])
  end
end
