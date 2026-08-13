defmodule MMGO.Repo.Migrations.CreateArenaTitleSeats do
  use Ecto.Migration

  # The top of the ladder is two named seats rather than a rating band: one
  # Champion and one Deputy, per season. A partial unique index keeps that
  # literally true — the database refuses a second holder of either seat.
  def change do
    create table(:arena_title_seats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :seat, :string, null: false
      add :season, :integer, null: false, default: 1
      add :status, :string, null: false, default: "offered"

      add :profile_id, references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
        null: false

      # Who offered the Deputy seat. Null for a Champion, who takes the seat by
      # winning rather than by appointment.
      add :appointed_by_profile_id,
          references(:arena_profiles, type: :binary_id, on_delete: :nilify_all)

      add :offered_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      add :vacated_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:arena_title_seats, [:profile_id])
    create index(:arena_title_seats, [:season, :status])

    # At most one held Champion and one held Deputy per season.
    create unique_index(:arena_title_seats, [:season, :seat],
             where: "status = 'held'",
             name: :arena_title_seats_one_holder_per_seat_index
           )

    # A profile may not hold both seats at once.
    create unique_index(:arena_title_seats, [:season, :profile_id],
             where: "status = 'held'",
             name: :arena_title_seats_one_seat_per_profile_index
           )

    create constraint(:arena_title_seats, :arena_title_seats_seat_check,
             check: "seat IN ('champion', 'deputy')"
           )

    create constraint(:arena_title_seats, :arena_title_seats_status_check,
             check: "status IN ('offered', 'declined', 'held', 'vacated')"
           )
  end
end
