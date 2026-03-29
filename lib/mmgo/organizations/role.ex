defmodule MMGO.Organizations.Role do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_roles" do
    field :code, :string
    field :title, :string
    field :rank, :integer
    field :permissions, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:code, :title, :rank, :permissions, :metadata, :organization_id])
    |> validate_required([:code, :title, :rank, :organization_id])
    |> validate_length(:code, min: 2, max: 80)
    |> validate_length(:title, min: 2, max: 120)
    |> validate_number(:rank, greater_than_or_equal_to: 0)
    |> unique_constraint(:code, name: :organization_roles_org_code_index)
  end
end
