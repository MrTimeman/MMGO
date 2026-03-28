defmodule MMGO.Repo.Migrations.CreateCraftingSystem do
  use Ecto.Migration

  def change do
    create table(:crafting_workshops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :installed_tool_codes, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:crafting_workshops, [:realm_id])

    create unique_index(:crafting_workshops, [:owner_character_id],
             where: "status = 'active'",
             name: :crafting_workshops_active_owner_index
           )

    create table(:crafting_recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :result_item_template_id,
          references(:item_templates, type: :binary_id, on_delete: :restrict), null: false

      add :code, :string, null: false
      add :name, :string, null: false
      add :craft_time_game_days, :integer, null: false, default: 1
      add :difficulty, :integer, null: false, default: 1
      add :required_tool_codes, {:array, :string}, null: false, default: []
      add :result_quantity, :integer, null: false, default: 1
      add :result_durability, :integer, null: false, default: 0
      add :requirements, :map, null: false, default: fragment("'[]'::jsonb")
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crafting_recipes, [:code])

    create table(:crafting_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :workspace_id, references(:crafting_workshops, type: :binary_id, on_delete: :restrict),
        null: false

      add :recipe_id, references(:crafting_recipes, type: :binary_id, on_delete: :restrict),
        null: false

      add :quantity, :integer, null: false
      add :yielded_quantity, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :completes_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:crafting_jobs, [:realm_id])
    create index(:crafting_jobs, [:recipe_id])

    create unique_index(:crafting_jobs, [:character_id],
             where: "status = 'active'",
             name: :crafting_jobs_single_active_character_index
           )
  end
end
