defmodule MMGO.Dungeons.LootDrop do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Dungeons.{Encounter, Node, Run}
  alias MMGO.Inventory.ItemTemplate

  @reward_kinds [:currency, :item_template]
  @statuses [:available, :claimed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_loot_drops" do
    field :reward_kind, Ecto.Enum, values: @reward_kinds
    field :status, Ecto.Enum, values: @statuses, default: :available
    field :amount, :integer, default: 0
    field :metadata, :map, default: %{}
    field :claimed_at, :utc_datetime_usec

    belongs_to :run, Run
    belongs_to :node, Node
    belongs_to :encounter, Encounter
    belongs_to :item_template, ItemTemplate
    belongs_to :claimed_by_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(loot_drop, attrs) do
    loot_drop
    |> cast(attrs, [
      :reward_kind,
      :status,
      :amount,
      :metadata,
      :claimed_at,
      :run_id,
      :node_id,
      :encounter_id,
      :item_template_id,
      :claimed_by_character_id
    ])
    |> validate_required([:reward_kind, :status, :amount, :run_id, :node_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_reward_link()
  end

  defp validate_reward_link(changeset) do
    case get_field(changeset, :reward_kind) do
      :item_template -> validate_required(changeset, [:item_template_id])
      _other -> changeset
    end
  end
end
