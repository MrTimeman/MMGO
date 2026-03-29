defmodule MMGO.Progression.Milestone do
  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "progression_milestones" do
    field :level, :integer
    field :code, :string
    field :title, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :effects, :map, default: %{}
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:level, :code, :title, :status, :effects, :metadata])
    |> validate_required([:level, :code, :title, :status])
    |> validate_number(:level, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_length(:code, min: 3, max: 80)
    |> validate_length(:title, min: 3, max: 160)
    |> unique_constraint(:level)
    |> unique_constraint(:code)
  end
end
