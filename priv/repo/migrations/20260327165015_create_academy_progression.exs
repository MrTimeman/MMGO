defmodule MMGO.Repo.Migrations.CreateAcademyProgression do
  use Ecto.Migration

  def change do
    create table(:academy_enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :program_type, :string, null: false
      add :track, :string
      add :status, :string, null: false, default: "active"
      add :funding_type, :string, null: false, default: "none"
      add :started_at, :utc_datetime_usec, null: false
      add :expected_completion_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_enrollments, [:character_id])
    create index(:academy_enrollments, [:realm_id])

    create unique_index(:academy_enrollments, [:character_id],
             where: "status = 'active'",
             name: :academy_enrollments_single_active_character_index
           )

    create table(:academy_specializations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :track, :string, null: false
      add :status, :string, null: false, default: "active"
      add :primary_school, :string
      add :secondary_school, :string
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_specializations, [:character_id])
    create index(:academy_specializations, [:realm_id])

    create unique_index(:academy_specializations, [:character_id],
             where: "status = 'active'",
             name: :academy_specializations_single_active_character_index
           )
  end
end
