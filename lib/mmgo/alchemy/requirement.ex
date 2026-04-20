defmodule MMGO.Alchemy.Requirement do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Inventory.ItemTemplate

  embedded_schema do
    field :item_template_id, :binary_id
    field :quantity, :integer
    field :qualities, {:array, :string}, default: []
  end

  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, [:item_template_id, :quantity, :qualities])
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_requirement_selector()
    |> validate_supported_qualities()
  end

  defp validate_requirement_selector(changeset) do
    template_id = get_field(changeset, :item_template_id)
    qualities = get_field(changeset, :qualities, [])

    if is_binary(template_id) or qualities != [] do
      changeset
    else
      add_error(changeset, :item_template_id, "must specify an ingredient template or qualities")
    end
  end

  defp validate_supported_qualities(changeset) do
    qualities = get_field(changeset, :qualities, [])
    invalid = Enum.reject(qualities, &(&1 in ItemTemplate.supported_qualities()))

    if invalid == [] do
      changeset
    else
      add_error(changeset, :qualities, "contains unsupported values: #{Enum.join(invalid, ", ")}")
    end
  end
end
