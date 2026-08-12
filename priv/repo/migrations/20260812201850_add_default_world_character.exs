defmodule MMGO.Repo.Migrations.AddDefaultWorldCharacter do
  use Ecto.Migration

  def up do
    # The old alpha rule allowed only one active/new world profile globally.
    # Realm identity now lives at account+realm, while character switching
    # decides which profile is active for each mode.
    drop index(:characters, [:account_id], name: :characters_account_single_playable_index)

    alter table(:accounts) do
      add :default_character_id,
          references(:characters, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:accounts, [:default_character_id])

    # Preserve historical rows without letting them remain selectable as a
    # second identity in the same realm. This is defensive for installations
    # that accumulated frozen duplicates before the invariant was introduced.
    execute("""
    WITH ranked_profiles AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY account_id, realm_id
               ORDER BY
                 CASE status WHEN 'active' THEN 0 WHEN 'new' THEN 1 ELSE 2 END,
                 updated_at DESC,
                 id
             ) AS position
      FROM characters
      WHERE status IN ('active', 'new', 'frozen')
        AND COALESCE(metadata->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')
    )
    UPDATE characters
    SET status = 'retired', updated_at = NOW()
    FROM ranked_profiles
    WHERE characters.id = ranked_profiles.id
      AND ranked_profiles.position > 1
    """)

    # A realm has one playable ordinary MMO identity per account. Arena
    # characters and the sealed anchor are technical profiles; retired rows
    # remain as history and cannot be selected as a default.
    create unique_index(:characters, [:account_id, :realm_id],
             where:
               "status IN ('active', 'new', 'frozen') AND COALESCE(metadata->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')",
             name: :characters_account_realm_world_index
           )

    execute("""
    WITH candidates AS (
      SELECT DISTINCT ON (characters.account_id)
        characters.account_id,
        characters.id
      FROM characters
      WHERE characters.status = 'active'
        AND COALESCE(characters.metadata->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')
      ORDER BY
        characters.account_id,
        CASE characters.status WHEN 'active' THEN 0 WHEN 'new' THEN 1 ELSE 2 END,
        characters.updated_at DESC,
        characters.id
    )
    UPDATE accounts
    SET default_character_id = candidates.id
    FROM candidates
    WHERE candidates.account_id = accounts.id
    """)
  end

  def down do
    drop index(:characters, [:account_id, :realm_id], name: :characters_account_realm_world_index)

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
        AND COALESCE(metadata->>'profile_kind', '') <> 'arena'
    )
    UPDATE characters
    SET status = 'frozen', updated_at = NOW()
    FROM ranked_profiles
    WHERE characters.id = ranked_profiles.id
      AND ranked_profiles.position > 1
    """)

    create unique_index(:characters, [:account_id],
             where:
               "status IN ('new', 'active') AND COALESCE(metadata->>'profile_kind', '') <> 'arena'",
             name: :characters_account_single_playable_index
           )

    drop index(:accounts, [:default_character_id])

    alter table(:accounts) do
      remove :default_character_id
    end
  end
end
