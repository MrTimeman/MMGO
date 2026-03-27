defmodule MMGO.Inventory do
  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Repo

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

  def grant_item(%Character{} = character, %ItemTemplate{} = item_template, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    quantity = attrs["quantity"] || 1
    durability = attrs["durability"] || default_durability(item_template)

    if item_template.stackable do
      case Repo.get_by(InventoryItem,
             character_id: character.id,
             item_template_id: item_template.id
           ) do
        %InventoryItem{} = existing_item ->
          existing_item
          |> InventoryItem.changeset(%{quantity: existing_item.quantity + quantity})
          |> Repo.update()

        nil ->
          create_inventory_item(character, item_template, quantity, durability, attrs)
      end
    else
      create_inventory_item(character, item_template, quantity, durability, attrs)
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

  defp create_inventory_item(character, item_template, quantity, durability, attrs) do
    %InventoryItem{}
    |> InventoryItem.changeset(%{
      character_id: character.id,
      item_template_id: item_template.id,
      quantity: quantity,
      durability: durability,
      metadata: attrs["metadata"] || %{}
    })
    |> Repo.insert()
  end

  defp default_durability(%ItemTemplate{max_durability: max_durability}) when max_durability > 0,
    do: max_durability

  defp default_durability(_item_template), do: 0

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
