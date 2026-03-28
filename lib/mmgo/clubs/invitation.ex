defmodule MMGO.Clubs.Invitation do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Clubs.Club

  @statuses [:pending, :accepted, :rejected, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_club_invitations" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :sent_at, :utc_datetime_usec
    field :responded_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :club, Club
    belongs_to :inviter_character, Character
    belongs_to :invitee_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :status,
      :sent_at,
      :responded_at,
      :metadata,
      :club_id,
      :inviter_character_id,
      :invitee_character_id
    ])
    |> validate_required([
      :status,
      :sent_at,
      :club_id,
      :inviter_character_id,
      :invitee_character_id
    ])
    |> unique_constraint(:invitee_character_id,
      name: :academy_club_invitations_pending_invitee_index
    )
  end
end
