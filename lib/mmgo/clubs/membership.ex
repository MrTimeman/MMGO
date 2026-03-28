defmodule MMGO.Clubs.Membership do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Clubs.Club

  @roles [:leader, :member]
  @statuses [:active, :left, :removed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_club_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :club, Club
    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status, :joined_at, :left_at, :metadata, :club_id, :character_id])
    |> validate_required([:role, :status, :joined_at, :club_id, :character_id])
    |> unique_constraint(:character_id, name: :academy_club_memberships_active_member_index)
  end
end
