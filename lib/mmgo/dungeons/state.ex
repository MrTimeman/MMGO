defmodule MMGO.Dungeons.State do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.Dungeon

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_states" do
    field :cycle_number, :integer, default: 0
    field :active_run_count_snapshot, :integer, default: 0
    field :pressure_level, :integer, default: 0
    field :anomaly_level, :integer, default: 0
    field :last_maintained_at, :utc_datetime_usec
    field :next_maintenance_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :dungeon, Dungeon

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :cycle_number,
      :active_run_count_snapshot,
      :pressure_level,
      :anomaly_level,
      :last_maintained_at,
      :next_maintenance_at,
      :metadata,
      :dungeon_id
    ])
    |> validate_required([
      :cycle_number,
      :active_run_count_snapshot,
      :pressure_level,
      :anomaly_level,
      :dungeon_id
    ])
    |> validate_number(:cycle_number, greater_than_or_equal_to: 0)
    |> validate_number(:active_run_count_snapshot, greater_than_or_equal_to: 0)
    |> validate_number(:pressure_level, greater_than_or_equal_to: 0)
    |> validate_number(:anomaly_level, greater_than_or_equal_to: 0)
    |> unique_constraint(:dungeon_id)
  end
end
