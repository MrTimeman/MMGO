defmodule MMGO.Dungeons.LinkState do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Dungeon, Link}

  @statuses [:active, :blocked]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_link_states" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :dungeon, Dungeon
    belongs_to :link, Link

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link_state, attrs) do
    link_state
    |> cast(attrs, [:status, :metadata, :dungeon_id, :link_id])
    |> validate_required([:status, :dungeon_id, :link_id])
    |> unique_constraint(:link_id, name: :dungeon_link_states_dungeon_link_index)
  end
end
