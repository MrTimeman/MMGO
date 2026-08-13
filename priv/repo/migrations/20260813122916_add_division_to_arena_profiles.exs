defmodule MMGO.Repo.Migrations.AddDivisionToArenaProfiles do
  use Ecto.Migration

  # The held division is stored rather than derived from rating, so a profile
  # that dips a point below a threshold keeps its division until it falls a
  # clear margin below it.
  def up do
    alter table(:arena_profiles) do
      add :division, :string, null: false, default: "initiate"
    end

    # Adopt the division each existing rating has already earned. Thresholds
    # match MMGO.Arena.Ladder.
    execute """
    UPDATE arena_profiles
    SET division = CASE
      WHEN rating >= 2500 THEN 'champion'
      WHEN rating >= 2150 THEN 'archmage'
      WHEN rating >= 1900 THEN 'diamond'
      WHEN rating >= 1650 THEN 'platinum'
      WHEN rating >= 1400 THEN 'gold'
      WHEN rating >= 1150 THEN 'silver'
      WHEN rating >= 900  THEN 'bronze'
      ELSE 'initiate'
    END
    """

    create index(:arena_profiles, [:division])
  end

  def down do
    drop index(:arena_profiles, [:division])

    alter table(:arena_profiles) do
      remove :division
    end
  end
end
