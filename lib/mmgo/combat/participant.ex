defmodule MMGO.Combat.Participant do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Actors.ActorTemplate
  alias MMGO.Accounts.Character
  alias MMGO.Arena.Ladder
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
    # The ladder division this caster brings to the fight. It gates which spells
    # they may wield; it never changes how strong those spells are.
    field :rank, Ecto.Enum, values: Ladder.keys(), default: :initiate
    # The mana pool. `max_mana` is set by rank and seat when the fight starts;
    # `locked_mana` is the share committed to a standing earth manifestation,
    # which is neither spent nor available until that manifestation ends.
    field :max_mana, :integer, default: 100
    field :mana, :integer, default: 100
    field :locked_mana, :integer, default: 0
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
      :rank,
      :max_mana,
      :mana,
      :locked_mana,
      :cooldowns,
      :active_states,
      :metadata,
      :grimoire_id
    ])
    |> validate_required([:combat_id, :side, :position, :status, :display_name, :combat_level])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:combat_level, greater_than: 0)
    |> validate_number(:max_mana, greater_than: 0)
    |> validate_number(:locked_mana, greater_than_or_equal_to: 0)
    |> fill_pool()
    |> validate_identity()
    |> unique_constraint([:combat_id, :character_id])
    |> check_constraint(:mana, name: :combat_participants_mana_range)
  end

  # A caster walks in with a full pool, and nothing may take them past it.
  defp fill_pool(changeset) do
    max_mana = get_field(changeset, :max_mana) || 100

    case {get_change(changeset, :mana), changeset.data.id} do
      {nil, nil} -> put_change(changeset, :mana, max_mana)
      {nil, _existing} -> changeset
      {mana, _id} -> put_change(changeset, :mana, mana |> max(0) |> min(max_mana))
    end
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
