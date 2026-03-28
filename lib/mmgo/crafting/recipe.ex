defmodule MMGO.Crafting.Recipe do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Crafting.Requirement
  alias MMGO.Inventory.ItemTemplate

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crafting_recipes" do
    field :code, :string
    field :name, :string
    field :craft_time_game_days, :integer, default: 1
    field :difficulty, :integer, default: 1
    field :required_tool_codes, {:array, :string}, default: []
    field :result_quantity, :integer, default: 1
    field :result_durability, :integer, default: 0
    field :metadata, :map, default: %{}

    embeds_many :requirements, Requirement, on_replace: :delete
    belongs_to :result_item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [
      :code,
      :name,
      :craft_time_game_days,
      :difficulty,
      :required_tool_codes,
      :result_quantity,
      :result_durability,
      :metadata,
      :result_item_template_id
    ])
    |> validate_required([
      :code,
      :name,
      :craft_time_game_days,
      :difficulty,
      :result_quantity,
      :result_durability,
      :result_item_template_id
    ])
    |> validate_length(:code, min: 3, max: 80)
    |> validate_length(:name, min: 3, max: 120)
    |> validate_number(:craft_time_game_days, greater_than: 0)
    |> validate_number(:difficulty, greater_than: 0)
    |> validate_number(:result_quantity, greater_than: 0)
    |> validate_number(:result_durability, greater_than_or_equal_to: 0)
    |> cast_embed(:requirements, required: true, with: &Requirement.changeset/2)
    |> unique_constraint(:code)
  end
end
