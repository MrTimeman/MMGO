defmodule MMGO.Repo.Migrations.RenameSpellLevelRequirementToPower do
  use Ecto.Migration

  # The number a spell earns from its craft is its power budget: every magnitude
  # is derived from it, and the rank allowed to wield it is read off it. It was
  # never a caster level, so it no longer carries that name.
  def up do
    rename table(:spells), :level_requirement, to: :power
  end

  def down do
    rename table(:spells), :power, to: :level_requirement
  end
end
