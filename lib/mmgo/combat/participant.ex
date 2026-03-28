defmodule MMGO.Combat.Participant do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Actors.ActorTemplate
  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat}
  alias MMGO.Grimoires.Grimoire

  @statuses [:ready, :defeated, :fled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combat_participants" do
    field :side, :string
    field :position, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :ready
    field :display_name, :string
    field :combat_level, :integer
    field :fatigue, :integer, default: 0
    field :cooldowns, :map, default: %{}
    field :active_states, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :combat, Combat
    belongs_to :character, Character
    belongs_to :actor_template, ActorTemplate
    belongs_to :grimoire, Grimoire
    has_many :actions, Action

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :combat_id,
      :character_id,
      :actor_template_id,
      :side,
      :position,
      :status,
      :display_name,
      :combat_level,
      :fatigue,
      :cooldowns,
      :active_states,
      :metadata,
      :grimoire_id
    ])
    |> validate_required([:combat_id, :side, :position, :status, :display_name, :combat_level])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:combat_level, greater_than: 0)
    |> validate_number(:fatigue, greater_than_or_equal_to: 0)
    |> validate_identity()
    |> unique_constraint([:combat_id, :character_id])
  end

  defp validate_identity(changeset) do
    case {get_field(changeset, :character_id), get_field(changeset, :actor_template_id)} do
      {nil, nil} ->
        add_error(
          changeset,
          :character_id,
          "either character_id or actor_template_id is required"
        )

      {_character_id, _actor_template_id} ->
        changeset
    end
  end
end
