defmodule MMGO.BlackMarket.Offer do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.BlackMarket.Deal
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Worlds.Realm

  @statuses [:active, :committed, :fulfilled, :cancelled, :defaulted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "black_market_offers" do
    field :quantity, :integer
    field :unit_price, :integer
    field :total_price, :integer
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :listed_at, :utc_datetime_usec
    field :fulfilled_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :defaulted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :seller_character, Character
    belongs_to :source_inventory_item, InventoryItem
    belongs_to :item_template, ItemTemplate
    has_one :deal, Deal

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [
      :quantity,
      :unit_price,
      :total_price,
      :status,
      :listed_at,
      :fulfilled_at,
      :cancelled_at,
      :defaulted_at,
      :metadata,
      :realm_id,
      :seller_character_id,
      :source_inventory_item_id,
      :item_template_id
    ])
    |> validate_required([
      :quantity,
      :unit_price,
      :total_price,
      :status,
      :listed_at,
      :realm_id,
      :seller_character_id,
      :source_inventory_item_id,
      :item_template_id
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> validate_number(:total_price, greater_than: 0)
    |> validate_total_price()
  end

  defp validate_total_price(changeset) do
    quantity = get_field(changeset, :quantity, 0)
    unit_price = get_field(changeset, :unit_price, 0)
    total_price = get_field(changeset, :total_price, 0)

    if quantity > 0 and unit_price > 0 and total_price != quantity * unit_price do
      add_error(changeset, :total_price, "must equal quantity multiplied by unit price")
    else
      changeset
    end
  end
end
