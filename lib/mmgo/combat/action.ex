defmodule MMGO.Combat.Action do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Combat.{Participant, Turn}
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Spells.Spell

  @action_types [:wait, :cast_spell, :use_item]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "combat_actions" do
    field :action_type, Ecto.Enum, values: @action_types
    field :target_side, :string
    field :payload, :map, default: %{}
    field :submitted_at, :utc_datetime_usec

    belongs_to :combat_turn, Turn
    belongs_to :participant, Participant
    belongs_to :spell, Spell
    belongs_to :inventory_item, InventoryItem
    belongs_to :target_participant, Participant

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :combat_turn_id,
      :participant_id,
      :spell_id,
      :inventory_item_id,
      :action_type,
      :target_side,
      :target_participant_id,
      :payload,
      :submitted_at
    ])
    |> validate_required([:combat_turn_id, :participant_id, :action_type, :submitted_at])
    |> validate_spell_requirements()
    |> unique_constraint([:combat_turn_id, :participant_id])
  end

  defp validate_spell_requirements(changeset) do
    case get_field(changeset, :action_type) do
      :cast_spell -> validate_required(changeset, [:spell_id])
      :use_item -> validate_required(changeset, [:inventory_item_id])
      _ -> changeset
    end
  end
end
