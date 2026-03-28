defmodule MMGO.Reputation.CrimeRecord do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Reputation.Profile
  alias MMGO.Worlds.Realm

  @statuses [:open, :resolved]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crime_records" do
    field :crime_type, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :severity, :integer
    field :reputation_delta, :integer
    field :fine_amount, :integer
    field :recorded_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :profile, Profile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(crime_record, attrs) do
    crime_record
    |> cast(attrs, [
      :crime_type,
      :status,
      :severity,
      :reputation_delta,
      :fine_amount,
      :recorded_at,
      :resolved_at,
      :metadata,
      :character_id,
      :realm_id,
      :profile_id
    ])
    |> validate_required([
      :crime_type,
      :status,
      :severity,
      :reputation_delta,
      :fine_amount,
      :recorded_at,
      :character_id,
      :realm_id
    ])
    |> validate_length(:crime_type, min: 3, max: 80)
    |> validate_number(:severity, greater_than: 0)
    |> validate_number(:fine_amount, greater_than_or_equal_to: 0)
  end
end
