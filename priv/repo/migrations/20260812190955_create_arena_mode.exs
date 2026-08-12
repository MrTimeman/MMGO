defmodule MMGO.Repo.Migrations.CreateArenaMode do
  use Ecto.Migration

  @schools ~w(fire water earth air life death chaos order)
  @event_codes ~w(
    emberfall
    healing_rain
    verdant_upheaval
    grave_eclipse
    wind_shear
    chaos_surge
    order_convergence
  )

  def up do
    drop index(:characters, [:account_id], name: :characters_account_single_playable_index)

    create unique_index(:characters, [:account_id],
             where:
               "status IN ('new', 'active') AND COALESCE(metadata->>'profile_kind', '') <> 'arena'",
             name: :characters_account_single_playable_index
           )

    create table(:arena_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :schools, {:array, :string}, null: false
      add :rating, :integer, null: false, default: 1_000
      add :season_xp, :integer, null: false, default: 0
      add :wins, :integer, null: false, default: 0
      add :losses, :integer, null: false, default: 0
      add :draws, :integer, null: false, default: 0
      add :matches_played, :integer, null: false, default: 0
      add :season, :integer, null: false, default: 1
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_profiles, [:account_id])
    create unique_index(:arena_profiles, [:character_id])
    create index(:arena_profiles, [:season, :rating])

    create constraint(:arena_profiles, :arena_profiles_exactly_three_schools,
             check: "cardinality(schools) = 3"
           )

    create constraint(:arena_profiles, :arena_profiles_distinct_schools,
             check:
               "schools[1] <> schools[2] AND schools[1] <> schools[3] AND schools[2] <> schools[3]"
           )

    create constraint(:arena_profiles, :arena_profiles_allowed_schools,
             check: "schools <@ ARRAY[#{quoted_values(@schools)}]::varchar[]"
           )

    create constraint(:arena_profiles, :arena_profiles_nonnegative_progress,
             check:
               "rating >= 0 AND season_xp >= 0 AND wins >= 0 AND losses >= 0 AND draws >= 0 AND matches_played >= 0 AND season > 0"
           )

    create constraint(:arena_profiles, :arena_profiles_match_totals,
             check: "matches_played = wins + losses + draws"
           )

    create table(:arena_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mode, :string, null: false
      add :status, :string, null: false, default: "forming"
      add :team_size, :integer, null: false, default: 1
      add :event_policy, :string, null: false, default: "random"
      add :event_codes, {:array, :string}, null: false, default: []
      add :settings, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :code, :string
      add :seed, :bigint, null: false

      add :host_profile_id,
          references(:arena_profiles, type: :binary_id, on_delete: :delete_all), null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :combat_id, references(:combats, type: :binary_id, on_delete: :nilify_all)
      add :winner_team, :string
      add :queued_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_matches, [:code], where: "code IS NOT NULL")
    create unique_index(:arena_matches, [:combat_id], where: "combat_id IS NOT NULL")
    create index(:arena_matches, [:host_profile_id])
    create index(:arena_matches, [:realm_id, :mode, :status, :queued_at])

    create unique_index(:arena_matches, [:host_profile_id],
             where: "mode = 'ranked' AND status = 'queued'",
             name: :arena_matches_single_ranked_queue_index
           )

    create constraint(:arena_matches, :arena_matches_valid_mode,
             check: "mode IN ('ranked', 'custom')"
           )

    create constraint(:arena_matches, :arena_matches_valid_status,
             check: "status IN ('forming', 'queued', 'active', 'finished', 'cancelled')"
           )

    create constraint(:arena_matches, :arena_matches_valid_team_size,
             check: "team_size BETWEEN 1 AND 5"
           )

    create constraint(:arena_matches, :arena_matches_valid_event_policy,
             check: "event_policy IN ('random', 'fixed', 'none')"
           )

    create constraint(:arena_matches, :arena_matches_allowed_events,
             check: "event_codes <@ ARRAY[#{quoted_values(@event_codes)}]::varchar[]"
           )

    create constraint(:arena_matches, :arena_matches_positive_seed, check: "seed > 0")

    create constraint(:arena_matches, :arena_matches_valid_winner,
             check: "winner_team IS NULL OR winner_team IN ('a', 'b')"
           )

    create constraint(:arena_matches, :arena_matches_custom_code,
             check: "(mode = 'custom' AND code IS NOT NULL) OR (mode = 'ranked' AND code IS NULL)"
           )

    create table(:arena_match_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_id, references(:arena_matches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :profile_id, references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :team, :string, null: false
      add :position, :integer, null: false
      add :ready, :boolean, null: false, default: false
      add :joined_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_match_members, [:match_id, :profile_id])
    create unique_index(:arena_match_members, [:match_id, :team, :position])
    create index(:arena_match_members, [:profile_id])

    create constraint(:arena_match_members, :arena_match_members_valid_team,
             check: "team IN ('a', 'b')"
           )

    create constraint(:arena_match_members, :arena_match_members_valid_position,
             check: "position BETWEEN 1 AND 5"
           )
  end

  def down do
    drop table(:arena_match_members)
    drop table(:arena_matches)
    drop table(:arena_profiles)

    drop index(:characters, [:account_id], name: :characters_account_single_playable_index)

    execute("""
    WITH ranked_profiles AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY account_id
               ORDER BY
                 CASE status WHEN 'active' THEN 0 WHEN 'new' THEN 1 ELSE 2 END,
                 updated_at DESC,
                 id
             ) AS position
      FROM characters
      WHERE status IN ('new', 'active')
    )
    UPDATE characters
    SET status = 'frozen', updated_at = NOW()
    FROM ranked_profiles
    WHERE characters.id = ranked_profiles.id
      AND ranked_profiles.position > 1
    """)

    create unique_index(:characters, [:account_id],
             where: "status IN ('new', 'active')",
             name: :characters_account_single_playable_index
           )
  end

  defp quoted_values(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
