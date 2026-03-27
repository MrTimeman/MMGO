defmodule MMGO.Dungeons.Node do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.Floor

  @kinds [:entrance, :room, :rest, :hazard, :boss, :stairs_up, :stairs_down, :exit]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_nodes" do
    field :slug, :string
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :x, :integer
    field :y, :integer
    field :threat_level, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :floor, Floor

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:slug, :name, :kind, :x, :y, :threat_level, :metadata, :floor_id])
    |> validate_required([:slug, :name, :kind, :x, :y, :threat_level, :floor_id])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_length(:name, min: 2, max: 120)
    |> validate_number(:threat_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:slug, name: :dungeon_nodes_floor_slug_index)
  end
end
