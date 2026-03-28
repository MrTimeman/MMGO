defmodule MMGO.Repo.Migrations.CreateBasesAndStorage do
  use Ecto.Migration

  def change do
    create table(:bases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "building"
      add :storage_weight_capacity, :integer, null: false, default: 0
      add :build_started_at, :utc_datetime_usec
      add :ready_at, :utc_datetime_usec
      add :built_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bases, [:owner_character_id])
    create index(:bases, [:realm_id])
    create index(:bases, [:location_id])

    create table(:base_storage_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_id, references(:bases, type: :binary_id, on_delete: :delete_all), null: false

      add :item_template_id, references(:item_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false
      add :durability, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:base_storage_items, [:base_id])
    create index(:base_storage_items, [:item_template_id])
  end
end
