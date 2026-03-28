defmodule MMGO.Repo.Migrations.CreateAcademiaAndNpcShops do
  use Ecto.Migration

  def change do
    create table(:academia_publications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :author_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :publication_kind, :string, null: false
      add :title, :string, null: false
      add :code, :string, null: false
      add :published_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:academia_publications, [:code])

    create table(:academia_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :publication_id,
          references(:academia_publications, type: :binary_id, on_delete: :nilify_all)

      add :project_kind, :string, null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :completes_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:academia_projects, [:character_id],
             where: "status = 'active'",
             name: :academia_projects_active_character_index
           )

    create table(:academia_professors, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      add :appointed_at, :utc_datetime_usec, null: false
      add :retired_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:academia_professors, [:character_id],
             where: "status = 'active'",
             name: :academia_professors_active_character_index
           )

    create table(:npc_shops, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :description, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:npc_shops, [:location_id, :code], name: :npc_shops_location_code_index)

    create table(:npc_shop_offers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shop_id, references(:npc_shops, type: :binary_id, on_delete: :delete_all), null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :buy_price, :bigint, null: false, default: 0
      add :sell_price, :bigint, null: false, default: 0
      add :item_durability, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:npc_shop_offers, [:shop_id, :item_template_id],
             name: :npc_shop_offers_shop_item_template_index
           )
  end
end
