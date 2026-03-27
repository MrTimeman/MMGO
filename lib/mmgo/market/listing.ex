defmodule MMGO.Market.Listing do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Worlds.Realm

  @statuses [:active, :sold, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "market_listings" do
    field :quantity, :integer
    field :unit_price, :integer
    field :total_price, :integer
    field :tax_rate_bps, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :listed_at, :utc_datetime_usec
    field :sold_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :seller_character, Character
    belongs_to :buyer_character, Character
    belongs_to :inventory_item, InventoryItem
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [
      :quantity,
      :unit_price,
      :total_price,
      :tax_rate_bps,
      :status,
      :listed_at,
      :sold_at,
      :cancelled_at,
      :metadata,
      :realm_id,
      :seller_character_id,
      :buyer_character_id,
      :inventory_item_id,
      :item_template_id
    ])
    |> validate_required([
      :quantity,
      :unit_price,
      :total_price,
      :tax_rate_bps,
      :status,
      :listed_at,
      :realm_id,
      :seller_character_id,
      :inventory_item_id,
      :item_template_id
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> validate_number(:total_price, greater_than: 0)
    |> validate_number(:tax_rate_bps, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> validate_total_price()
    |> unique_constraint(:inventory_item_id,
      name: :market_listings_single_active_inventory_item_index
    )
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
