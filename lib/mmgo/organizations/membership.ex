defmodule MMGO.Organizations.Membership do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Organizations.{Organization, Role}

  @statuses [:active, :left, :removed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization
    belongs_to :character, Character
    belongs_to :role, Role

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :status,
      :joined_at,
      :left_at,
      :metadata,
      :organization_id,
      :character_id,
      :role_id
    ])
    |> validate_required([:status, :joined_at, :organization_id, :character_id, :role_id])
    |> unique_constraint(:character_id, name: :organization_memberships_active_member_index)
  end
end
