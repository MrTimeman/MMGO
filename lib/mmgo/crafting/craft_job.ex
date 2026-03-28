defmodule MMGO.Crafting.CraftJob do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Crafting.{Recipe, Workshop}
  alias MMGO.Worlds.Realm

  @statuses [:active, :completed, :failed, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crafting_jobs" do
    field :quantity, :integer
    field :yielded_quantity, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :workspace, Workshop
    belongs_to :recipe, Recipe

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(craft_job, attrs) do
    craft_job
    |> cast(attrs, [
      :quantity,
      :yielded_quantity,
      :status,
      :started_at,
      :completes_at,
      :completed_at,
      :metadata,
      :character_id,
      :realm_id,
      :workspace_id,
      :recipe_id
    ])
    |> validate_required([
      :quantity,
      :yielded_quantity,
      :status,
      :started_at,
      :completes_at,
      :character_id,
      :realm_id,
      :workspace_id,
      :recipe_id
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:yielded_quantity, greater_than_or_equal_to: 0)
    |> unique_constraint(:character_id, name: :crafting_jobs_single_active_character_index)
  end
end
