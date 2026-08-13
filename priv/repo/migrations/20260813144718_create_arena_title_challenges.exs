defmodule MMGO.Repo.Migrations.CreateArenaTitleChallenges do
  use Ecto.Migration

  # The gauntlet: one row per attempt on a seat. The Deputy is fought first, and
  # winning that fight earns an expiring right to call out the Champion, which
  # is what `grants_until` records. A challenge nobody answers by `expires_at`
  # is claimed by the challenger — title challenges cannot be declined, and
  # ignoring one is the same as declining it.
  def change do
    create table(:arena_title_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :seat, :string, null: false
      add :season, :integer, null: false, default: 1
      add :status, :string, null: false, default: "open"

      add :challenger_profile_id,
          references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :defender_profile_id,
          references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :arena_match_id, references(:arena_matches, type: :binary_id, on_delete: :nilify_all)

      add :challenged_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      # When the challenger won a Deputy fight, how long their right to call out
      # the Champion stands.
      add :grants_until, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:arena_title_challenges, [:challenger_profile_id])
    create index(:arena_title_challenges, [:defender_profile_id])
    create index(:arena_title_challenges, [:season, :status])

    # One open challenge per seat per season: a queue of pretenders would make
    # the seat unplayable.
    create unique_index(:arena_title_challenges, [:season, :seat],
             where: "status = 'open'",
             name: :arena_title_challenges_one_open_per_seat_index
           )

    # And one open challenge per challenger, so nobody may sit on both fights.
    create unique_index(:arena_title_challenges, [:season, :challenger_profile_id],
             where: "status = 'open'",
             name: :arena_title_challenges_one_open_per_challenger_index
           )

    create constraint(:arena_title_challenges, :arena_title_challenges_seat_check,
             check: "seat IN ('champion', 'deputy')"
           )

    create constraint(:arena_title_challenges, :arena_title_challenges_status_check,
             check: "status IN ('open', 'won', 'lost', 'claimed', 'expired')"
           )

    create constraint(:arena_title_challenges, :arena_title_challenges_distinct_parties,
             check: "challenger_profile_id <> defender_profile_id"
           )
  end
end
