defmodule MMGO.Spells.SpellEffect do
  use Ecto.Schema

  import Ecto.Changeset

  @supported_states [
    "impact",
    "burning",
    "frozen",
    "trapped",
    "blinded",
    "silenced",
    "staggered",
    "channeling",
    "shielded",
    "regenerating",
    "empowered",
    "exposed"
  ]

  # State breaks stay deliberately small and server-interpreted. They are
  # persisted with the effect, then copied to the active combat state instead
  # of being inferred from a spell name, free-form tag, or AI narration.
  @supported_break_conditions ["fire_spell", "water_spell", "physical_hit"]

  @applies_to [:target, :caster, :environment]

  embedded_schema do
    field :applies_to, Ecto.Enum, values: @applies_to
    field :state, :string
    field :intensity, :integer
    field :variance, :integer, default: 0
    field :duration, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :break_conditions, {:array, :string}, default: []
  end

  def changeset(effect, attrs) do
    effect
    |> cast(attrs, [
      :applies_to,
      :state,
      :intensity,
      :variance,
      :duration,
      :tags,
      :break_conditions
    ])
    |> validate_required([:applies_to, :state, :intensity, :duration])
    |> validate_inclusion(:state, @supported_states)
    |> validate_number(:intensity, greater_than_or_equal_to: 0)
    |> validate_number(:variance, greater_than_or_equal_to: 0)
    |> validate_number(:duration, greater_than_or_equal_to: 0)
    |> validate_length(:tags, max: 8)
    |> validate_length(:break_conditions, max: 3)
    |> validate_subset(:break_conditions, @supported_break_conditions)
    |> validate_variance_bound()
  end

  def supported_states, do: @supported_states
  def supported_break_conditions, do: @supported_break_conditions

  defp validate_variance_bound(changeset) do
    intensity = get_field(changeset, :intensity, 0)
    variance = get_field(changeset, :variance, 0)

    if variance > intensity do
      add_error(changeset, :variance, "must not exceed the base intensity")
    else
      changeset
    end
  end
end
