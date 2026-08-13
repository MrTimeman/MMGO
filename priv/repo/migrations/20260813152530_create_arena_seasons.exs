defmodule MMGO.Repo.Migrations.CreateArenaSeasons do
  use Ecto.Migration

  # A season is a real thing with a beginning and an end, not a number carried
  # on every profile and hoped to agree. Ending one records where everybody
  # finished — that record is the reward, and it outlives the reset that follows.
  def change do
    create table(:arena_seasons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_seasons, [:number])

    create unique_index(:arena_seasons, [:status],
             where: "status = 'active'",
             name: :arena_seasons_one_active_index
           )

    create constraint(:arena_seasons, :arena_seasons_status_check,
             check: "status IN ('active', 'finished')"
           )

    create table(:arena_season_awards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :season_id, references(:arena_seasons, type: :binary_id, on_delete: :delete_all),
        null: false

      add :profile_id, references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :division, :string, null: false
      add :rating, :integer, null: false
      add :wins, :integer, null: false, default: 0
      add :losses, :integer, null: false, default: 0
      add :seat, :string
      add :coins_awarded, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_season_awards, [:season_id, :profile_id])
    create index(:arena_season_awards, [:profile_id])

    # Placement matches: until they are played, the ladder moves faster because
    # it knows less about you.
    alter table(:arena_profiles) do
      add :placements_remaining, :integer, null: false, default: 0
    end
  end
end
