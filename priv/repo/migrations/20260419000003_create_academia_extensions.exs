defmodule MMGO.Repo.Migrations.CreateAcademiaExtensions do
  use Ecto.Migration

  def change do
    alter table(:academia_projects) do
      add :defense_scheduled_at, :utc_datetime_usec
      add :defense_state, :string
    end

    create table(:advisor_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :professor_character_id,
          references(:characters, type: :binary_id, on_delete: :restrict),
          null: false

      add :student_character_id,
          references(:characters, type: :binary_id, on_delete: :delete_all),
          null: false

      add :project_id, references(:academia_projects, type: :binary_id, on_delete: :nilify_all)
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:advisor_relationships, [:professor_character_id])
    create index(:advisor_relationships, [:student_character_id])

    create unique_index(:advisor_relationships, [:student_character_id],
             where: "status = 'active'",
             name: :advisor_relationships_active_student_index
           )

    create table(:professor_reputation, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :professor_character_id,
          references(:characters, type: :binary_id, on_delete: :delete_all),
          null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :score, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:professor_reputation, [:professor_character_id, :realm_id],
             name: :professor_reputation_character_realm_index
           )
  end
end
