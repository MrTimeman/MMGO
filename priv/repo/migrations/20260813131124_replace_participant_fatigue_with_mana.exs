defmodule MMGO.Repo.Migrations.ReplaceParticipantFatigueWithMana do
  use Ecto.Migration

  # Fatigue was an uncapped counter whose only effect was an accuracy tax: no
  # maximum, no regen, and nothing anywhere that refused a cast for want of it.
  # Mana is the real resource that replaces it — a bounded pool, refilled a
  # share at a time, that a spell can genuinely fail to afford.
  def up do
    alter table(:combat_participants) do
      add :max_mana, :integer, null: false, default: 100
      add :mana, :integer, null: false, default: 100
      # Mana committed to a standing earth-school manifestation. It is neither
      # spent nor available until that manifestation ends.
      add :locked_mana, :integer, null: false, default: 0
      remove :fatigue
    end

    create constraint(:combat_participants, :combat_participants_mana_range,
             check: "mana >= 0 AND mana <= max_mana AND locked_mana >= 0"
           )
  end

  def down do
    drop constraint(:combat_participants, :combat_participants_mana_range)

    alter table(:combat_participants) do
      add :fatigue, :integer, null: false, default: 0
      remove :max_mana
      remove :mana
      remove :locked_mana
    end
  end
end
