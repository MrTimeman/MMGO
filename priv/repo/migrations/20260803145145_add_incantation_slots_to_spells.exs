defmodule MMGO.Repo.Migrations.AddIncantationSlotsToSpells do
  use Ecto.Migration

  def change do
    alter table(:spells) do
      add :incantation_slots, :map, null: false, default: %{}
    end
  end
end
