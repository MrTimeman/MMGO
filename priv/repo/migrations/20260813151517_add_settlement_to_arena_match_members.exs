defmodule MMGO.Repo.Migrations.AddSettlementToArenaMatchMembers do
  use Ecto.Migration

  # What a match did to a player is written down when it is settled rather than
  # recomputed later: a history list should read a row, not replay the Elo maths
  # against ratings that have since moved on.
  def change do
    alter table(:arena_match_members) do
      add :outcome, :string
      add :rating_before, :integer
      add :rating_after, :integer
    end

    create constraint(:arena_match_members, :arena_match_members_valid_outcome,
             check: "outcome IS NULL OR outcome IN ('win', 'loss', 'draw')"
           )

    create index(:arena_match_members, [:profile_id, :inserted_at])
  end
end
