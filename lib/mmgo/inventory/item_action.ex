defmodule MMGO.Inventory.ItemAction do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Spells.SpellEffect

  @action_kinds [:strike, :sweep, :raise_shield, :throw, :deploy, :repair]
  @targeting_modes [:self, :ally, :enemy, :zone]

  embedded_schema do
    field :key, :string
    field :action_kind, Ecto.Enum, values: @action_kinds
    field :targeting, Ecto.Enum, values: @targeting_modes
    field :quantity_cost, :integer, default: 0
    field :durability_cost, :integer, default: 0
    field :tags, {:array, :string}, default: []

    embeds_many :effects, SpellEffect, on_replace: :delete
  end

  def changeset(item_action, attrs) do
    item_action
    |> cast(attrs, [:key, :action_kind, :targeting, :quantity_cost, :durability_cost, :tags])
    |> validate_required([:key, :action_kind, :targeting])
    |> validate_format(:key, ~r/^[a-z0-9_\-]+$/)
    |> validate_number(:quantity_cost, greater_than_or_equal_to: 0)
    |> validate_number(:durability_cost, greater_than_or_equal_to: 0)
    |> cast_embed(:effects, required: true, with: &SpellEffect.changeset/2)
  end
end
