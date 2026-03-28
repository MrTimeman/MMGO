defmodule MMGO.Reputation.Profile do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Reputation.CrimeRecord
  alias MMGO.Worlds.Realm

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reputation_profiles" do
    field :reputation_score, :integer, default: 0
    field :crime_count, :integer, default: 0
    field :outstanding_fine, :integer, default: 0
    field :npc_hostility_level, :integer, default: 0
    field :market_ban_until, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    has_many :crime_records, CrimeRecord

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :reputation_score,
      :crime_count,
      :outstanding_fine,
      :npc_hostility_level,
      :market_ban_until,
      :metadata,
      :character_id,
      :realm_id
    ])
    |> validate_required([
      :reputation_score,
      :crime_count,
      :outstanding_fine,
      :npc_hostility_level,
      :character_id,
      :realm_id
    ])
    |> validate_number(:crime_count, greater_than_or_equal_to: 0)
    |> validate_number(:outstanding_fine, greater_than_or_equal_to: 0)
    |> validate_number(:npc_hostility_level, greater_than_or_equal_to: 0)
    |> unique_constraint(:character_id)
  end
end
