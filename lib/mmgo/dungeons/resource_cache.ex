defmodule MMGO.Dungeons.ResourceCache do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Dungeons.{Node, Run}
  alias MMGO.Inventory.ItemTemplate

  @statuses [:available, :depleted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_resource_caches" do
    field :resource_code, :string
    field :status, Ecto.Enum, values: @statuses, default: :available
    field :quantity_total, :integer, default: 0
    field :quantity_remaining, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :node, Node
    belongs_to :item_template, ItemTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(resource_cache, attrs) do
    resource_cache
    |> cast(attrs, [
      :resource_code,
      :status,
      :quantity_total,
      :quantity_remaining,
      :metadata,
      :run_id,
      :node_id,
      :item_template_id
    ])
    |> validate_required([
      :resource_code,
      :status,
      :quantity_total,
      :quantity_remaining,
      :run_id,
      :node_id
    ])
    |> validate_length(:resource_code, min: 2, max: 64)
    |> validate_number(:quantity_total, greater_than_or_equal_to: 0)
    |> validate_number(:quantity_remaining, greater_than_or_equal_to: 0)
    |> validate_remaining_bound()
    |> unique_constraint(:node_id, name: :dungeon_resource_caches_run_node_resource_index)
  end

  defp validate_remaining_bound(changeset) do
    total = get_field(changeset, :quantity_total, 0)
    remaining = get_field(changeset, :quantity_remaining, 0)

    if remaining > total do
      add_error(changeset, :quantity_remaining, "must not exceed the total quantity")
    else
      changeset
    end
  end
end
