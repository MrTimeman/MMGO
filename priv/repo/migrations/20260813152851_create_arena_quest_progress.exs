defmodule MMGO.Repo.Migrations.CreateArenaQuestProgress do
  use Ecto.Migration

  # Quests reset by period rather than by mutation: a row belongs to one day or
  # one week, named by `period_key`, and tomorrow simply asks about a different
  # key. Nothing has to run at midnight for the reset to be correct — a nightly
  # job only sweeps up the rows nobody will ask about again.
  def change do
    create table(:arena_quest_progress, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :profile_id, references(:arena_profiles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :period, :string, null: false
      add :period_key, :string, null: false
      add :progress, :integer, null: false, default: 0
      add :goal, :integer, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:arena_quest_progress, [:profile_id, :code, :period_key])
    create index(:arena_quest_progress, [:period_key])

    create constraint(:arena_quest_progress, :arena_quest_progress_period_check,
             check: "period IN ('daily', 'weekly')"
           )

    # A streak is the one piece of engagement state that has to survive between
    # sessions, so it lives on the profile rather than in a period row.
    alter table(:arena_profiles) do
      add :streak_days, :integer, null: false, default: 0
      add :last_played_on, :date
    end
  end
end
