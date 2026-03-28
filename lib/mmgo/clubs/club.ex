defmodule MMGO.Clubs.Club do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Clubs.{Invitation, Membership}
  alias MMGO.Worlds.Realm

  @club_types [:general_interest, :dueling, :research, :expedition_planning]
  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_clubs" do
    field :name, :string
    field :club_type, Ecto.Enum, values: @club_types
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :founder_character, Character
    has_many :memberships, Membership
    has_many :invitations, Invitation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(club, attrs) do
    club
    |> cast(attrs, [:name, :club_type, :status, :metadata, :realm_id, :founder_character_id])
    |> validate_required([:name, :club_type, :status, :realm_id, :founder_character_id])
    |> validate_length(:name, min: 3, max: 120)
  end
end
