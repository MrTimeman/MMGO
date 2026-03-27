defmodule MMGO.Dungeons.Floor do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Dungeon, Node}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_floors" do
    field :number, :integer
    field :name, :string
    field :metadata, :map, default: %{}

    belongs_to :dungeon, Dungeon
    has_many :nodes, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(floor, attrs) do
    floor
    |> cast(attrs, [:number, :name, :metadata, :dungeon_id])
    |> validate_required([:number, :name, :dungeon_id])
    |> validate_number(:number, greater_than: 0)
    |> validate_length(:name, min: 2, max: 120)
    |> unique_constraint(:number, name: :dungeon_floors_number_index)
  end
end
