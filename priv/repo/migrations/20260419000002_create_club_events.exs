defmodule MMGO.Repo.Migrations.CreateClubEvents do
  use Ecto.Migration

  def change do
    create table(:club_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :club_id, references(:academy_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "scheduled"
      add :scheduled_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :result_metadata, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:club_events, [:club_id])
    create index(:club_events, [:realm_id])
    create index(:club_events, [:scheduled_at])

    create table(:club_event_attendance, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_id, references(:club_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :attended_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:club_event_attendance, [:event_id])
    create index(:club_event_attendance, [:character_id])

    create unique_index(:club_event_attendance, [:event_id, :character_id],
             name: :club_event_attendance_event_character_index
           )
  end
end
