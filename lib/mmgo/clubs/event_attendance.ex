defmodule MMGO.Clubs.EventAttendance do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Clubs.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "club_event_attendance" do
    field :attended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :event, Event
    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attendance, attrs) do
    attendance
    |> cast(attrs, [:attended_at, :metadata, :event_id, :character_id])
    |> validate_required([:attended_at, :event_id, :character_id])
    |> unique_constraint([:event_id, :character_id],
      name: :club_event_attendance_event_character_index
    )
  end
end
