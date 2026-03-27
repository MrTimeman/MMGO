defmodule MMGO.Parties.ExpeditionMember do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Parties.{Expedition, Membership}

  @statuses [:active, :completed, :left]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "expedition_members" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :expedition, Expedition
    belongs_to :party_membership, Membership
    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(expedition_member, attrs) do
    expedition_member
    |> cast(attrs, [
      :status,
      :joined_at,
      :left_at,
      :metadata,
      :expedition_id,
      :party_membership_id,
      :character_id
    ])
    |> validate_required([
      :status,
      :joined_at,
      :expedition_id,
      :party_membership_id,
      :character_id
    ])
    |> unique_constraint(:character_id, name: :expedition_members_single_active_character_index)
    |> unique_constraint(:character_id,
      name: :expedition_members_active_expedition_character_index
    )
  end
end
