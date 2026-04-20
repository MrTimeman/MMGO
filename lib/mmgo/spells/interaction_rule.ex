defmodule MMGO.Spells.InteractionRule do
  use Ecto.Schema

  import Ecto.Changeset

  @trigger_types [:environment_tag, :target_state, :spell_tag]
  @outcomes [:negate, :amplify, :replace_environment, :apply_bonus_state, :spread, :transform]

  embedded_schema do
    field :trigger_type, Ecto.Enum, values: @trigger_types
    field :trigger, :string
    field :outcome, Ecto.Enum, values: @outcomes
    field :modifier, :integer, default: 0
    field :state, :string
    field :replacement_tags, {:array, :string}, default: []
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:trigger_type, :trigger, :outcome, :modifier, :state, :replacement_tags])
    |> validate_required([:trigger_type, :trigger, :outcome])
    |> validate_length(:trigger, min: 1, max: 80)
    |> validate_length(:replacement_tags, max: 8)
    |> validate_bonus_state()
    |> validate_replacement_tags()
  end

  defp validate_bonus_state(changeset) do
    case get_field(changeset, :outcome) do
      :apply_bonus_state ->
        changeset
        |> validate_required([:state])
        |> validate_inclusion(:state, MMGO.Spells.Spell.effect_states())

      _ ->
        changeset
    end
  end

  defp validate_replacement_tags(changeset) do
    case get_field(changeset, :outcome) do
      outcome when outcome in [:replace_environment, :spread, :transform] ->
        validate_required(changeset, [:replacement_tags])

      _other ->
        changeset
    end
  end
end
