defmodule MMGO.Dungeons.NodeState do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Node, Run}

  @statuses [:current, :visited, :cleared, :blocked]
  @encounter_statuses [:pending, :active, :cleared, :avoided]
  @resource_statuses [:unknown, :available, :depleted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_node_states" do
    field :status, Ecto.Enum, values: @statuses, default: :current
    field :encounter_status, Ecto.Enum, values: @encounter_statuses, default: :pending
    field :resource_status, Ecto.Enum, values: @resource_statuses, default: :unknown
    field :visit_count, :integer, default: 1
    field :entered_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node_state, attrs) do
    node_state
    |> cast(attrs, [
      :status,
      :encounter_status,
      :resource_status,
      :visit_count,
      :entered_at,
      :last_seen_at,
      :left_at,
      :metadata,
      :run_id,
      :node_id
    ])
    |> validate_required([
      :status,
      :encounter_status,
      :resource_status,
      :visit_count,
      :entered_at,
      :last_seen_at,
      :run_id,
      :node_id
    ])
    |> validate_number(:visit_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:node_id, name: :dungeon_node_states_run_node_index)
  end
end
