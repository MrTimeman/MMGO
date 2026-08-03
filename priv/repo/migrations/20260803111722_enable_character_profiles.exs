defmodule MMGO.Repo.Migrations.EnableCharacterProfiles do
  use Ecto.Migration

  def up do
    drop index(:characters, [:account_id, :realm_id], name: :characters_account_realm_index)

    create index(:characters, [:account_id, :realm_id],
             name: :characters_account_realm_lookup_index
           )

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

    execute("""
    WITH ranked_migrations AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY account_id
               ORDER BY inserted_at DESC, id DESC
             ) AS position
      FROM federation_migrations
      WHERE status = 'active'
    )
    UPDATE federation_migrations
    SET status = 'cancelled',
        completed_at = COALESCE(completed_at, NOW()),
        updated_at = NOW()
    FROM ranked_migrations
    WHERE federation_migrations.id = ranked_migrations.id
      AND ranked_migrations.position > 1
    """)

    create unique_index(:federation_migrations, [:account_id],
             where: "status = 'active'",
             name: :federation_migrations_active_account_index
           )
  end

  def down do
    drop index(:federation_migrations, [:account_id],
           name: :federation_migrations_active_account_index
         )

    drop index(:characters, [:account_id], name: :characters_account_single_playable_index)

    drop index(:characters, [:account_id, :realm_id],
           name: :characters_account_realm_lookup_index
         )

    raise "cannot safely restore one-character-per-realm after multiple profiles have been created"
  end
end
