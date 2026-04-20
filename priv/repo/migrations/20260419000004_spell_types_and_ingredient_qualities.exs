defmodule MMGO.Repo.Migrations.SpellTypesAndIngredientQualities do
  use Ecto.Migration

  def change do
    alter table(:spells) do
      add :spell_type, :string, null: false, default: "active"
      add :mana_reservation, :integer, null: false, default: 0
    end

    alter table(:item_templates) do
      add :description, :string
      add :qualities, {:array, :string}, null: false, default: []
    end
  end
end
