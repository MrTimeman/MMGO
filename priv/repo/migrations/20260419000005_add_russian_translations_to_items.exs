defmodule MMGO.Repo.Migrations.AddRussianTranslationsToItems do
  use Ecto.Migration

  def change do
    alter table(:item_templates) do
      add :name_ru, :string
      add :description_ru, :string
    end
  end
end
