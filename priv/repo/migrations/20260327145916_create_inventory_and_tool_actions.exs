defmodule MMGO.Repo.Migrations.CreateInventoryAndToolActions do
  use Ecto.Migration

  def change do
    create table(:item_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :item_type, :string, null: false
      add :stackable, :boolean, null: false, default: false
      add :weight, :integer, null: false, default: 1
      add :max_durability, :integer, null: false, default: 0
      add :tags, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
      add :actions, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:item_templates, [:code])

    create table(:inventory_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false, default: 1
      add :durability, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:inventory_items, [:character_id])
    create index(:inventory_items, [:item_template_id])

    alter table(:combat_actions) do
      add :inventory_item_id,
          references(:inventory_items, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:combat_actions, [:inventory_item_id])
  end
end
