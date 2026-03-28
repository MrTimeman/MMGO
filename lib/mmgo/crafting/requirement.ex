defmodule MMGO.Crafting.Requirement do
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field :item_template_id, :binary_id
    field :quantity, :integer
  end

  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, [:item_template_id, :quantity])
    |> validate_required([:item_template_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
