defmodule MMGO.Dungeons.NodeOverride do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Dungeon, Node}

  @statuses [:stable, :volatile, :depleted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_node_overrides" do
    field :status, Ecto.Enum, values: @statuses, default: :stable
    field :threat_bias, :integer, default: 0
    field :resource_bias, :integer, default: 0
    field :anomaly_tag, :string
    field :metadata, :map, default: %{}

    belongs_to :dungeon, Dungeon
    belongs_to :node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node_override, attrs) do
    node_override
    |> cast(attrs, [
      :status,
      :threat_bias,
      :resource_bias,
      :anomaly_tag,
      :metadata,
      :dungeon_id,
      :node_id
    ])
    |> validate_required([:status, :threat_bias, :resource_bias, :dungeon_id, :node_id])
    |> validate_number(:threat_bias, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> validate_number(:resource_bias, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> unique_constraint(:node_id, name: :dungeon_node_overrides_dungeon_node_index)
  end
end
