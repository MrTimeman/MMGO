defmodule MMGO.Repo.Migrations.CreateMarketListings do
  use Ecto.Migration

  def change do
    alter table(:inventory_items) do
      add :reserved_quantity, :integer, null: false, default: 0
    end

    create table(:market_listings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :seller_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :buyer_character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)

      add :inventory_item_id,
          references(:inventory_items, type: :binary_id, on_delete: :restrict), null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false
      add :unit_price, :bigint, null: false
      add :total_price, :bigint, null: false
      add :tax_rate_bps, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      add :listed_at, :utc_datetime_usec, null: false
      add :sold_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:market_listings, [:realm_id])
    create index(:market_listings, [:seller_character_id])
    create index(:market_listings, [:buyer_character_id])
    create index(:market_listings, [:status])

    create unique_index(:market_listings, [:inventory_item_id],
             where: "status = 'active'",
             name: :market_listings_single_active_inventory_item_index
           )

    create table(:black_market_offers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :seller_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :source_inventory_item_id,
          references(:inventory_items, type: :binary_id, on_delete: :nilify_all)

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false
      add :unit_price, :bigint, null: false
      add :total_price, :bigint, null: false
      add :status, :string, null: false, default: "active"
      add :listed_at, :utc_datetime_usec, null: false
      add :fulfilled_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :defaulted_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:black_market_offers, [:realm_id])
    create index(:black_market_offers, [:seller_character_id])
    create index(:black_market_offers, [:status])

    create table(:black_market_deals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :offer_id, references(:black_market_offers, type: :binary_id, on_delete: :restrict),
        null: false

      add :seller_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :buyer_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false
      add :total_price, :bigint, null: false
      add :status, :string, null: false, default: "awaiting_delivery"
      add :paid_at, :utc_datetime_usec, null: false
      add :fulfilled_at, :utc_datetime_usec
      add :defaulted_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:black_market_deals, [:realm_id])
    create index(:black_market_deals, [:seller_character_id])
    create index(:black_market_deals, [:buyer_character_id])
    create index(:black_market_deals, [:status])
    create unique_index(:black_market_deals, [:offer_id])
  end
end
