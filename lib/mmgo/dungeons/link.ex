defmodule MMGO.Dungeons.Link do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Dungeon, Node}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_links" do
    field :travel_cost, :integer, default: 1
    field :bidirectional, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :dungeon, Dungeon
    belongs_to :from_node, Node
    belongs_to :to_node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :travel_cost,
      :bidirectional,
      :metadata,
      :dungeon_id,
      :from_node_id,
      :to_node_id
    ])
    |> validate_required([:travel_cost, :bidirectional, :dungeon_id, :from_node_id, :to_node_id])
    |> validate_number(:travel_cost, greater_than: 0)
    |> validate_distinct_nodes()
    |> unique_constraint(:from_node_id, name: :dungeon_links_from_to_index)
  end

  defp validate_distinct_nodes(changeset) do
    if get_field(changeset, :from_node_id) == get_field(changeset, :to_node_id) do
      add_error(changeset, :to_node_id, "must differ from the origin node")
    else
      changeset
    end
  end
end
