defmodule MMGO.Repo.Migrations.AllowMultipleArenaProfiles do
  use Ecto.Migration

  # Arena is a place to experiment with school combinations, so a player may
  # keep several profiles. Holding more than one seat at the top of the ladder
  # is prevented separately, on arena_title_seats, by account rather than by
  # profile.
  def up do
    drop index(:arena_profiles, [:account_id], name: :arena_profiles_account_id_index)
    create index(:arena_profiles, [:account_id])
  end

  def down do
    drop index(:arena_profiles, [:account_id])

    create unique_index(:arena_profiles, [:account_id], name: :arena_profiles_account_id_index)
  end
end
