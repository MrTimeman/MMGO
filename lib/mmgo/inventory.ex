defmodule MMGO.Inventory do
  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Repo

  @stack_key "stack"

  def list_item_templates do
    Repo.all(from template in ItemTemplate, order_by: [asc: template.inserted_at])
  end

  def get_item_template!(id), do: Repo.get!(ItemTemplate, id)

  def create_item_template(attrs \\ %{}) do
    %ItemTemplate{}
    |> ItemTemplate.changeset(attrs)
    |> Repo.insert()
  end

  def change_item_template(%ItemTemplate{} = item_template, attrs \\ %{}) do
    ItemTemplate.changeset(item_template, attrs)
  end

  def list_inventory_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from item in InventoryItem,
        where: item.character_id == ^character_id,
        order_by: [asc: item.inserted_at],
        preload: [:item_template]
    )
  end

  def get_inventory_item!(id) do
    InventoryItem
    |> Repo.get!(id)
    |> Repo.preload(:item_template)
  end

  def available_quantity(%InventoryItem{} = inventory_item) do
    max(inventory_item.quantity - inventory_item.reserved_quantity, 0)
  end

  def grant_item(%Character{} = character, %ItemTemplate{} = item_template, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    quantity = attrs["quantity"] || 1
    durability = attrs["durability"] || default_durability(item_template)
    metadata = attrs["metadata"] || %{}

    with :ok <- validate_grant_quantity(quantity) do
      if item_template.stackable do
        upsert_stackable_item(character, item_template, quantity, durability, metadata)
      else
        create_inventory_item(character, item_template, quantity, durability, metadata, nil)
      end
    end
  end

  def update_inventory_item(%InventoryItem{} = inventory_item, attrs) when is_map(attrs) do
    inventory_item
    |> InventoryItem.changeset(attrs)
    |> Repo.update()
  end

  def action_definition(%ItemTemplate{} = item_template, action_key) when is_binary(action_key) do
    Enum.find(item_template.actions || [], &(&1.key == action_key))
  end

  def change_inventory_item(%InventoryItem{} = inventory_item, attrs \\ %{}) do
    InventoryItem.changeset(inventory_item, attrs)
  end

  defp upsert_stackable_item(character, item_template, quantity, durability, metadata) do
    %InventoryItem{}
    |> InventoryItem.changeset(%{
      character_id: character.id,
      item_template_id: item_template.id,
      quantity: quantity,
      reserved_quantity: 0,
      durability: durability,
      stack_key: @stack_key,
      metadata: metadata
    })
    |> Repo.insert(
      on_conflict: [
        inc: [quantity: quantity],
        set: [updated_at: DateTime.utc_now()]
      ],
      conflict_target: [:character_id, :item_template_id, :stack_key],
      returning: true
    )
  end

  defp create_inventory_item(character, item_template, quantity, durability, metadata, stack_key) do
    %InventoryItem{}
    |> InventoryItem.changeset(%{
      character_id: character.id,
      item_template_id: item_template.id,
      quantity: quantity,
      reserved_quantity: 0,
      durability: durability,
      stack_key: stack_key,
      metadata: metadata
    })
    |> Repo.insert()
  end

  defp default_durability(%ItemTemplate{max_durability: max_durability}) when max_durability > 0,
    do: max_durability

  defp default_durability(_item_template), do: 0

  defp validate_grant_quantity(quantity) when is_integer(quantity) and quantity >= 0, do: :ok

  defp validate_grant_quantity(_quantity) do
    {:error,
     %InventoryItem{}
     |> Ecto.Changeset.change()
     |> Ecto.Changeset.add_error(:quantity, "must be greater than or equal to zero")}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
