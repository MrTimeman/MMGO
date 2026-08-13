defmodule MMGO.Repo.Migrations.AddDivisionChangeToMatchMembers do
  use Ecto.Migration

  # The moment a match promotes or demotes someone is the moment worth showing
  # them, so it is recorded rather than inferred: a held division lags rating by
  # the demotion buffer, and guessing it back from the numbers would sometimes
  # announce a rank-up that never happened.
  def change do
    alter table(:arena_match_members) do
      add :division_before, :string
      add :division_after, :string
      add :season_xp_gained, :integer
    end
  end
end
