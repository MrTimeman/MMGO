defmodule MMGO.Dungeons.Run do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{
    Drop,
    Dungeon,
    Encounter,
    Extraction,
    Floor,
    LootDrop,
    Node,
    NodeState,
    ResourceCache
  }

  alias MMGO.Parties.Expedition

  @statuses [:active, :completed, :retreated, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_runs" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :steps_taken, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :last_progressed_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :expedition, Expedition
    belongs_to :dungeon, Dungeon
    belongs_to :current_floor, Floor
    belongs_to :current_node, Node
    has_many :drops, Drop
    has_many :extractions, Extraction
    has_many :encounters, Encounter
    has_many :node_states, NodeState
    has_many :resource_caches, ResourceCache
    has_many :loot_drops, LootDrop

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :steps_taken,
      :started_at,
      :last_progressed_at,
      :ended_at,
      :metadata,
      :expedition_id,
      :dungeon_id,
      :current_floor_id,
      :current_node_id
    ])
    |> validate_required([
      :status,
      :steps_taken,
      :started_at,
      :last_progressed_at,
      :expedition_id,
      :dungeon_id,
      :current_floor_id,
      :current_node_id
    ])
    |> validate_number(:steps_taken, greater_than_or_equal_to: 0)
    |> unique_constraint(:expedition_id, name: :dungeon_runs_single_active_expedition_index)
  end
end
