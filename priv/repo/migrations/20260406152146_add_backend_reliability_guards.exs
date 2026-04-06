defmodule MMGO.Repo.Migrations.AddBackendReliabilityGuards do
  use Ecto.Migration

  def up do
    alter table(:characters) do
      add :import_reference, :string
    end

    create unique_index(:characters, [:import_reference],
             where: "import_reference IS NOT NULL",
             name: :characters_import_reference_index
           )

    alter table(:inventory_items) do
      add :stack_key, :string
    end

    execute("""
    WITH stackable_duplicates AS (
      SELECT
        inventory_items.character_id,
        inventory_items.item_template_id,
        (ARRAY_AGG(inventory_items.id ORDER BY inventory_items.inserted_at, inventory_items.id))[1] AS keep_id,
        SUM(inventory_items.quantity) AS total_quantity,
        SUM(inventory_items.reserved_quantity) AS total_reserved_quantity,
        MAX(inventory_items.durability) AS max_durability
      FROM inventory_items
      INNER JOIN item_templates
        ON item_templates.id = inventory_items.item_template_id
      WHERE item_templates.stackable = TRUE
      GROUP BY inventory_items.character_id, inventory_items.item_template_id
      HAVING COUNT(*) > 1
    )
    UPDATE inventory_items
    SET
      quantity = stackable_duplicates.total_quantity,
      reserved_quantity = stackable_duplicates.total_reserved_quantity,
      durability = stackable_duplicates.max_durability,
      stack_key = 'stack',
      updated_at = NOW()
    FROM stackable_duplicates
    WHERE inventory_items.id = stackable_duplicates.keep_id
    """)

    execute("""
    WITH stackable_duplicates AS (
      SELECT
        inventory_items.character_id,
        inventory_items.item_template_id,
        (ARRAY_AGG(inventory_items.id ORDER BY inventory_items.inserted_at, inventory_items.id))[1] AS keep_id
      FROM inventory_items
      INNER JOIN item_templates
        ON item_templates.id = inventory_items.item_template_id
      WHERE item_templates.stackable = TRUE
      GROUP BY inventory_items.character_id, inventory_items.item_template_id
      HAVING COUNT(*) > 1
    )
    DELETE FROM inventory_items
    USING stackable_duplicates
    WHERE inventory_items.character_id = stackable_duplicates.character_id
      AND inventory_items.item_template_id = stackable_duplicates.item_template_id
      AND inventory_items.id <> stackable_duplicates.keep_id
    """)

    execute("""
    UPDATE inventory_items
    SET stack_key = 'stack'
    FROM item_templates
    WHERE item_templates.id = inventory_items.item_template_id
      AND item_templates.stackable = TRUE
      AND inventory_items.stack_key IS NULL
    """)

    create unique_index(:inventory_items, [:character_id, :item_template_id, :stack_key],
             name: :inventory_items_character_template_stack_key_index
           )
  end

  def down do
    drop index(:inventory_items, [:character_id, :item_template_id, :stack_key],
           name: :inventory_items_character_template_stack_key_index
         )

    alter table(:inventory_items) do
      remove :stack_key
    end

    drop index(:characters, [:import_reference], name: :characters_import_reference_index)

    alter table(:characters) do
      remove :import_reference
    end
  end
end
