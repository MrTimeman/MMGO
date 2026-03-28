defmodule MMGO.Dungeons.Drop do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Dungeons.{Node, Run}
  alias MMGO.Inventory.ItemTemplate

  @kinds [:inventory, :grimoire]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_drops" do
    field :drop_kind, Ecto.Enum, values: @kinds
    field :name, :string
    field :quantity, :integer
    field :durability, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :node, Node
    belongs_to :item_template, ItemTemplate
    belongs_to :owner_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(drop, attrs) do
    drop
    |> cast(attrs, [
      :drop_kind,
      :name,
      :quantity,
      :durability,
      :metadata,
      :run_id,
      :node_id,
      :item_template_id,
      :owner_character_id
    ])
    |> validate_required([:drop_kind, :name, :quantity, :run_id, :node_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:durability, greater_than_or_equal_to: 0)
  end
end
