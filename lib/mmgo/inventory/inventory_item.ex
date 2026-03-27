defmodule MMGO.Inventory.InventoryItem do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Inventory.ItemTemplate

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inventory_items" do
    field :quantity, :integer, default: 1
    field :durability, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(inventory_item, attrs) do
    inventory_item
    |> cast(attrs, [:character_id, :item_template_id, :quantity, :durability, :metadata])
    |> validate_required([:character_id, :item_template_id, :quantity, :durability])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:durability, greater_than_or_equal_to: 0)
  end
end
