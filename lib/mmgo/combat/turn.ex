defmodule MMGO.Combat.Turn do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Combat.{Action, Combat}

  @statuses [:open, :locked, :resolved]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combat_turns" do
    field :number, :integer
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolution, :map, default: %{}
    field :narration, :string

    belongs_to :combat, Combat
    has_many :actions, Action, foreign_key: :combat_turn_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [:combat_id, :number, :status, :resolution, :narration])
    |> validate_required([:combat_id, :number, :status])
    |> validate_number(:number, greater_than_or_equal_to: 1)
    |> unique_constraint([:combat_id, :number])
  end
end
