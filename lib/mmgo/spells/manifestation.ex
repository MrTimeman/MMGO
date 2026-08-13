defmodule MMGO.Spells.Manifestation do
  @moduledoc """
  A bounded, duel-local construct produced by a spell.

  Manifestations are part of the spell definition and combat snapshot. They
  never create inventory records and disappear with the combat.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds [:held_shield, :summoned_weapon, :creature_ally]
  # What a construct does beyond plain hits and absorption — one bounded word,
  # matched to its school at compile time.
  @traits [:ignite, :chill, :gale, :bastion, :mending, :drain, :rupture, :ward]
  @max_display_name_bytes 96
  @max_hp 120
  @max_power 60
  @max_duration_turns 8
  @cyrillic_pattern ~r/[А-Яа-яЁё]/u
  @latin_pattern ~r/[A-Za-z]/u
  @control_character_pattern ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u

  embedded_schema do
    field :kind, Ecto.Enum, values: @kinds
    field :display_name, :string
    field :hp, :integer
    field :power, :integer
    field :duration_turns, :integer
    field :trait, Ecto.Enum, values: @traits
  end

  def changeset(manifestation, attrs) do
    manifestation
    |> cast(attrs, [:kind, :display_name, :hp, :power, :duration_turns, :trait])
    |> validate_required([:kind, :display_name, :duration_turns])
    |> validate_number(:hp, greater_than: 0, less_than_or_equal_to: @max_hp)
    |> validate_number(:power, greater_than: 0, less_than_or_equal_to: @max_power)
    |> validate_number(:duration_turns,
      greater_than: 0,
      less_than_or_equal_to: @max_duration_turns
    )
    |> validate_display_name()
    |> validate_kind_fields()
  end

  def kinds, do: @kinds
  def traits, do: @traits
  def max_hp, do: @max_hp
  def max_power, do: @max_power
  def max_duration_turns, do: @max_duration_turns

  @doc """
  Converts construct stats into the same finite budget used by spell effects.

  HP is a construct's duel-local durability, power is more expensive because
  it can repeat, and duration accounts for how long the construct can shape a
  fight.
  """
  def effect_budget(nil), do: 0

  def effect_budget(%__MODULE__{} = manifestation) do
    (manifestation.hp || 0) + (manifestation.power || 0) * 2 +
      (manifestation.duration_turns || 0) * 5
  end

  defp validate_display_name(changeset) do
    case get_field(changeset, :display_name) do
      display_name when is_binary(display_name) ->
        if String.valid?(display_name) and display_name == String.trim(display_name) and
             display_name != "" and byte_size(display_name) <= @max_display_name_bytes and
             Regex.match?(@cyrillic_pattern, display_name) and
             not Regex.match?(@latin_pattern, display_name) and
             not Regex.match?(@control_character_pattern, display_name) do
          changeset
        else
          add_error(changeset, :display_name, "must be a bounded Russian display name")
        end

      _other ->
        changeset
    end
  end

  defp validate_kind_fields(changeset) do
    case get_field(changeset, :kind) do
      :held_shield ->
        changeset
        |> validate_required([:hp])
        |> reject_present(:power)

      :summoned_weapon ->
        changeset
        |> validate_required([:power])
        |> reject_present(:hp)

      :creature_ally ->
        validate_required(changeset, [:hp, :power])

      _other ->
        changeset
    end
  end

  defp reject_present(changeset, field) do
    if is_nil(get_field(changeset, field)) do
      changeset
    else
      add_error(changeset, field, "is not used by this manifestation kind")
    end
  end
end
