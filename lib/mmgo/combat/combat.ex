defmodule MMGO.Combat.Combat do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Combat.{Event, Participant, Turn}
  alias MMGO.Worlds.Realm

  @kinds [:duel, :dungeon_encounter, :overworld_encounter]
  @statuses [:forming, :active_turn, :locked, :resolving, :resolved, :finished]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combats" do
    field :kind, Ecto.Enum, values: @kinds, default: :duel
    field :status, Ecto.Enum, values: @statuses, default: :forming
    field :turn_number, :integer, default: 1
    field :seed, :integer
    field :environment_tags, {:array, :string}, default: []
    field :sides, :map, default: %{}
    field :winner_side, :string
    field :finished_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    has_many :participants, Participant
    has_many :turns, Turn
    has_many :events, Event

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(combat, attrs) do
    combat
    |> cast(attrs, [
      :kind,
      :status,
      :turn_number,
      :seed,
      :environment_tags,
      :sides,
      :winner_side,
      :finished_at,
      :metadata,
      :realm_id
    ])
    |> validate_required([:kind, :status, :turn_number, :seed, :sides, :realm_id])
    |> validate_number(:turn_number, greater_than_or_equal_to: 1)
    |> validate_number(:seed, greater_than: 0)
    |> validate_sides()
  end

  defp validate_sides(changeset) do
    sides = get_field(changeset, :sides, %{})

    if map_size(sides) < 2 do
      add_error(changeset, :sides, "must define at least two combat sides")
    else
      changeset
    end
  end
end
