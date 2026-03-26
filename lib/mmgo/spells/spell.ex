defmodule MMGO.Spells.Spell do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Spells.{FailureProfile, InteractionRule, SpellEffect}
  alias MMGO.Worlds.Realm

  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]
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
    |> cast_embed(:effects, required: true, with: &SpellEffect.changeset/2)
    |> cast_embed(:interaction_rules, with: &InteractionRule.changeset/2)
    |> cast_embed(:failure_profile, required: true, with: &FailureProfile.changeset/2)
    |> validate_length(:tags, max: 12)
    |> validate_length(:narrative_tags, max: 12)
    |> validate_length(:environment_tags, max: 8)
    |> validate_effect_budget()
  end

  def effect_states do
    SpellEffect.supported_states()
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
