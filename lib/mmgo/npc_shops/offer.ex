defmodule MMGO.NPCShops.Offer do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Inventory.ItemTemplate
  alias MMGO.NPCShops.Shop

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "npc_shop_offers" do
    field :buy_price, :integer, default: 0
    field :sell_price, :integer, default: 0
    field :item_durability, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :shop, Shop
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [
      :buy_price,
      :sell_price,
      :item_durability,
      :metadata,
      :shop_id,
      :item_template_id
    ])
    |> validate_required([:buy_price, :sell_price, :item_durability, :shop_id, :item_template_id])
    |> validate_number(:buy_price, greater_than_or_equal_to: 0)
    |> validate_number(:sell_price, greater_than_or_equal_to: 0)
    |> validate_number(:item_durability, greater_than_or_equal_to: 0)
    |> unique_constraint(:item_template_id, name: :npc_shop_offers_shop_item_template_index)
  end
end
