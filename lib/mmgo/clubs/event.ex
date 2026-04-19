defmodule MMGO.Clubs.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Clubs.{Club, EventAttendance}
  alias MMGO.Worlds.Realm

  @kinds [:general_meeting, :duel_tournament, :research_session, :expedition_briefing]
  @statuses [:scheduled, :active, :completed, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "club_events" do
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses, default: :scheduled
    field :scheduled_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :result_metadata, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :club, Club
    belongs_to :realm, Realm
    has_many :attendances, EventAttendance, foreign_key: :event_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :kind,
      :status,
      :scheduled_at,
      :completed_at,
      :result_metadata,
      :metadata,
      :club_id,
      :realm_id
    ])
    |> validate_required([:kind, :status, :scheduled_at, :club_id, :realm_id])
  end
end
