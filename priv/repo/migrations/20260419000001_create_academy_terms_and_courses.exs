defmodule MMGO.Repo.Migrations.CreateAcademyTermsAndCourses do
  use Ecto.Migration

  def change do
    create table(:academy_terms, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :enrollment_id,
          references(:academy_enrollments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :term_number, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :exam_score, :integer
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_terms, [:enrollment_id])
    create index(:academy_terms, [:realm_id])

    create unique_index(:academy_terms, [:enrollment_id, :term_number],
             name: :academy_terms_enrollment_term_number_index
           )

    create table(:academy_courses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :publication_id,
          references(:academia_publications, type: :binary_id, on_delete: :nilify_all)

      add :source, :string, null: false, default: "seeded"
      add :npc_professor_code, :string
      add :title, :string, null: false
      add :track, :string
      add :school, :string
      add :syllabus, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_courses, [:realm_id])
    create index(:academy_courses, [:publication_id])

    create table(:course_enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :term_id, references(:academy_terms, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:academy_courses, type: :binary_id, on_delete: :restrict),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "enrolled"
      add :grade, :integer
      add :enrolled_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_enrollments, [:term_id])
    create index(:course_enrollments, [:character_id])

    create unique_index(:course_enrollments, [:term_id, :course_id, :character_id],
             name: :course_enrollments_term_course_character_index
           )
  end
end
