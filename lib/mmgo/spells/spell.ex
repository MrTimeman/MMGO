defmodule MMGO.Spells.Spell do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Spells.{FailureProfile, InteractionRule, SpellEffect}
  alias MMGO.Worlds.Realm

  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]
  @spell_types [:active, :passive, :utility]
  @delivery_forms [
    :single_target,
    :beam,
    :cone,
    :sphere,
    :wall,
    :zone,
    :self,
    :link,
    :delayed_trigger
  ]
  @targeting_modes [:self, :ally, :enemy, :zone]
  @environment_modes [:none, :add, :replace]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spells" do
    field :name, :string
    field :formula, :string
    field :school, Ecto.Enum, values: @schools
    field :spell_type, Ecto.Enum, values: @spell_types, default: :active
    field :mana_reservation, :integer, default: 0
    field :description, :string
    field :level_requirement, :integer, default: 1
    field :fatigue_cost, :integer, default: 0
    field :cooldown_turns, :integer, default: 0
    field :targeting, Ecto.Enum, values: @targeting_modes
    field :delivery_form, Ecto.Enum, values: @delivery_forms
    field :tags, {:array, :string}, default: []
    field :narrative_tags, {:array, :string}, default: []
    field :environment_tags, {:array, :string}, default: []
    field :environment_mode, Ecto.Enum, values: @environment_modes, default: :none

    embeds_many :effects, SpellEffect, on_replace: :delete
    embeds_many :interaction_rules, InteractionRule, on_replace: :delete
    embeds_one :failure_profile, FailureProfile, on_replace: :update

    belongs_to :creator_character, Character
    belongs_to :realm, Realm
    belongs_to :source_spell, __MODULE__

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(spell, attrs) do
    spell
    |> cast(attrs, [
      :name,
      :formula,
      :school,
      :spell_type,
      :mana_reservation,
      :description,
      :level_requirement,
      :fatigue_cost,
      :cooldown_turns,
      :targeting,
      :delivery_form,
      :tags,
      :narrative_tags,
      :environment_tags,
      :environment_mode,
      :creator_character_id,
      :realm_id,
      :source_spell_id
    ])
    |> validate_required([
      :name,
      :formula,
      :school,
      :targeting,
      :delivery_form,
      :creator_character_id,
      :realm_id
    ])
    |> validate_length(:name, min: 3, max: 120)
    |> validate_length(:formula, min: 3, max: 180)
    |> validate_number(:level_requirement, greater_than_or_equal_to: 1)
    |> validate_number(:fatigue_cost, greater_than_or_equal_to: 0)
    |> validate_number(:cooldown_turns, greater_than_or_equal_to: 0)
    |> validate_number(:mana_reservation, greater_than_or_equal_to: 0)
    |> validate_mana_reservation()
    |> cast_embed(:effects, required: true, with: &SpellEffect.changeset/2)
    |> cast_embed(:interaction_rules, with: &InteractionRule.changeset/2)
    |> cast_embed(:failure_profile, required: true, with: &FailureProfile.changeset/2)
    |> validate_spell_mode_rules()
    |> validate_length(:tags, max: 12)
    |> validate_length(:narrative_tags, max: 12)
    |> validate_length(:environment_tags, max: 8)
    |> validate_effect_budget()
  end

  def effect_states do
    SpellEffect.supported_states()
  end

  def spell_types, do: @spell_types

  defp validate_mana_reservation(changeset) do
    spell_type = get_field(changeset, :spell_type, :active)
    reservation = get_field(changeset, :mana_reservation, 0)

    if spell_type != :passive and reservation > 0 do
      add_error(changeset, :mana_reservation, "must be 0 for non-passive spells")
    else
      changeset
    end
  end

  defp validate_spell_mode_rules(changeset) do
    case get_field(changeset, :spell_type, :active) do
      :passive ->
        changeset
        |> validate_mode_targeting(:passive)
        |> validate_passive_reservation()
        |> validate_passive_fatigue()
        |> validate_passive_effects()

      :utility ->
        changeset
        |> validate_mode_targeting(:utility)
        |> validate_utility_effects()

      _other ->
        changeset
    end
  end

  defp validate_mode_targeting(changeset, spell_type) do
    targeting = get_field(changeset, :targeting)

    if targeting in [:self, :zone] do
      changeset
    else
      add_error(changeset, :targeting, "#{spell_type} spells must target self or zone")
    end
  end

  defp validate_passive_reservation(changeset) do
    reservation = get_field(changeset, :mana_reservation, 0)

    if reservation > 0 do
      changeset
    else
      add_error(changeset, :mana_reservation, "passive spells must reserve mana")
    end
  end

  defp validate_passive_fatigue(changeset) do
    fatigue_cost = get_field(changeset, :fatigue_cost, 0)

    if fatigue_cost == 0 do
      changeset
    else
      add_error(changeset, :fatigue_cost, "passive spells must not cost fatigue")
    end
  end

  defp validate_passive_effects(changeset) do
    effects = get_field(changeset, :effects, [])

    if Enum.any?(effects, &(&1.state == "impact")) do
      add_error(changeset, :effects, "passive spells cannot deal direct impact damage")
    else
      changeset
    end
  end

  defp validate_utility_effects(changeset) do
    utility_states = MapSet.new(SpellEffect.utility_states())
    effects = get_field(changeset, :effects, [])

    if Enum.all?(effects, &MapSet.member?(utility_states, &1.state)) do
      changeset
    else
      add_error(changeset, :effects, "utility spells may use only utility states")
    end
  end

  defp validate_effect_budget(changeset) do
    effects = get_field(changeset, :effects, [])
    total_intensity = Enum.reduce(effects, 0, fn effect, acc -> acc + effect.intensity end)

    if total_intensity > 240 do
      add_error(changeset, :effects, "total spell intensity exceeds the current engine budget")
    else
      changeset
    end
  end
end
