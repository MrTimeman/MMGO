defmodule MMGO.Bases.StorageItem do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Bases.Base
  alias MMGO.Inventory.ItemTemplate

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "base_storage_items" do
    field :quantity, :integer
    field :durability, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :base, Base
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(storage_item, attrs) do
    storage_item
    |> cast(attrs, [:quantity, :durability, :metadata, :base_id, :item_template_id])
    |> validate_required([:quantity, :durability, :base_id, :item_template_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:durability, greater_than_or_equal_to: 0)
  end
end
