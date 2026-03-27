defmodule MMGO.BlackMarket.Deal do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.BlackMarket.Offer
  alias MMGO.Inventory.ItemTemplate
  alias MMGO.Worlds.Realm

  @statuses [:awaiting_delivery, :fulfilled, :defaulted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "black_market_deals" do
    field :quantity, :integer
    field :total_price, :integer
    field :status, Ecto.Enum, values: @statuses, default: :awaiting_delivery
    field :paid_at, :utc_datetime_usec
    field :fulfilled_at, :utc_datetime_usec
    field :defaulted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :offer, Offer
    belongs_to :seller_character, Character
    belongs_to :buyer_character, Character
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [
      :quantity,
      :total_price,
      :status,
      :paid_at,
      :fulfilled_at,
      :defaulted_at,
      :metadata,
      :realm_id,
      :offer_id,
      :seller_character_id,
      :buyer_character_id,
      :item_template_id
    ])
    |> validate_required([
      :quantity,
      :total_price,
      :status,
      :paid_at,
      :realm_id,
      :offer_id,
      :seller_character_id,
      :buyer_character_id,
      :item_template_id
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:total_price, greater_than: 0)
    |> unique_constraint(:offer_id)
  end
end
