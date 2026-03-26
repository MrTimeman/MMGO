defmodule MMGO.Combat.Participant do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat}

  @statuses [:ready, :defeated, :fled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combat_participants" do
    field :side, :string
    field :position, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :ready
    field :fatigue, :integer, default: 0
    field :cooldowns, :map, default: %{}
    field :active_states, {:array, :map}, default: []

    belongs_to :combat, Combat
    belongs_to :character, Character
    has_many :actions, Action

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :combat_id,
      :character_id,
      :side,
      :position,
      :status,
      :fatigue,
      :cooldowns,
      :active_states
    ])
    |> validate_required([:combat_id, :character_id, :side, :position, :status])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:fatigue, greater_than_or_equal_to: 0)
    |> unique_constraint([:combat_id, :character_id])
  end
end
