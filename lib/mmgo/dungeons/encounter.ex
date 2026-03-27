defmodule MMGO.Dungeons.Encounter do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Combat.Combat
  alias MMGO.Dungeons.{Node, Run}

  @statuses [:pending, :active, :cleared, :avoided, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_encounters" do
    field :encounter_kind, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :threat_level, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :node, Node
    belongs_to :combat, Combat

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(encounter, attrs) do
    encounter
    |> cast(attrs, [
      :encounter_kind,
      :status,
      :threat_level,
      :started_at,
      :resolved_at,
      :metadata,
      :run_id,
      :node_id,
      :combat_id
    ])
    |> validate_required([:encounter_kind, :status, :threat_level, :run_id, :node_id])
    |> validate_length(:encounter_kind, min: 2, max: 64)
    |> validate_number(:threat_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:node_id, name: :dungeon_encounters_run_node_index)
  end
end
