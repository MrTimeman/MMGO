defmodule MMGO.Parties.Membership do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Parties.{ExpeditionMember, Party}

  @roles [:leader, :member]
  @statuses [:active, :left, :removed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "party_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :party, Party
    belongs_to :character, Character
    has_many :expedition_memberships, ExpeditionMember, foreign_key: :party_membership_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status, :joined_at, :left_at, :metadata, :party_id, :character_id])
    |> validate_required([:role, :status, :joined_at, :party_id, :character_id])
    |> unique_constraint(:character_id, name: :party_memberships_single_active_character_index)
    |> unique_constraint(:character_id, name: :party_memberships_active_party_character_index)
  end
end
