defmodule MMGO.Inventory.ItemTemplate do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Inventory.ItemAction

  @item_types [:weapon, :shield, :potion, :tool]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_templates" do
    field :code, :string
    field :name, :string
    field :item_type, Ecto.Enum, values: @item_types
    field :stackable, :boolean, default: false
    field :weight, :integer, default: 1
    field :max_durability, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    embeds_many :actions, ItemAction, on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item_template, attrs) do
    item_template
    |> cast(attrs, [
      :code,
      :name,
      :item_type,
      :stackable,
      :weight,
      :max_durability,
      :tags,
      :metadata
    ])
    |> validate_required([:code, :name, :item_type, :weight, :max_durability])
    |> validate_format(:code, ~r/^[a-z0-9_\-]+$/)
    |> validate_length(:code, min: 3, max: 64)
    |> validate_length(:name, min: 3, max: 120)
    |> validate_number(:weight, greater_than: 0)
    |> validate_number(:max_durability, greater_than_or_equal_to: 0)
    |> cast_embed(:actions, required: true, with: &ItemAction.changeset/2)
    |> unique_constraint(:code)
  end
end
