defmodule MMGO.Combat.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Combat.{Combat, Turn}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combat_events" do
    field :turn_number, :integer
    field :sequence, :integer
    field :event_type, :string
    field :payload, :map, default: %{}

    belongs_to :combat, Combat
    belongs_to :combat_turn, Turn

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:combat_id, :combat_turn_id, :turn_number, :sequence, :event_type, :payload])
    |> validate_required([:combat_id, :combat_turn_id, :turn_number, :sequence, :event_type])
    |> validate_number(:turn_number, greater_than_or_equal_to: 1)
    |> validate_number(:sequence, greater_than_or_equal_to: 1)
  end
end
