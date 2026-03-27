defmodule MMGO.Repo.Migrations.AddSurvivalAndCarryCapacity do
  use Ecto.Migration

  def change do
    alter table(:item_templates) do
      add :nutrition_units, :integer, null: false, default: 0
    end

    alter table(:journeys) do
      add :food_units_consumed, :integer, null: false, default: 0
      add :encumbrance_penalty_days, :integer, null: false, default: 0
      add :carried_weight, :integer, null: false, default: 0
      add :carry_capacity, :integer, null: false, default: 0
    end

    alter table(:expeditions) do
      add :food_units_snapshot, :integer, null: false, default: 0
      add :daily_food_demand, :integer, null: false, default: 0
      add :carried_weight, :integer, null: false, default: 0
      add :carry_capacity, :integer, null: false, default: 0
    end
  end
end
