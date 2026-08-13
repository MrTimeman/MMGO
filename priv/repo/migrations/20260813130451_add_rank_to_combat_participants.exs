defmodule MMGO.Repo.Migrations.AddRankToCombatParticipants do
  use Ecto.Migration

  # A caster's ladder division decides which spells they may wield, so it is
  # frozen onto the participant when the fight starts rather than read live: a
  # promotion mid-match must not change what is legal in that match.
  def change do
    alter table(:combat_participants) do
      add :rank, :string, null: false, default: "initiate"
    end

    create constraint(:combat_participants, :combat_participants_rank_check,
             check:
               "rank IN ('initiate', 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'archmage', 'champion')"
           )
  end
end
