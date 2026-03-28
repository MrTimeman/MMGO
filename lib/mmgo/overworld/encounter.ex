defmodule MMGO.Overworld.Encounter do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Combat.Combat
  alias MMGO.Overworld.Response
  alias MMGO.Worlds.{Location, Realm}

  @kinds [:player]
  @statuses [:pending, :active, :greeted, :trading, :avoided, :escalated]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "overworld_encounters" do
    field :encounter_kind, Ecto.Enum, values: @kinds, default: :player
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :started_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :location, Location
    belongs_to :initiator_character, Character
    belongs_to :target_character, Character
    belongs_to :combat, Combat
    has_many :responses, Response

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(encounter, attrs) do
    encounter
    |> cast(attrs, [
      :encounter_kind,
      :status,
      :started_at,
      :resolved_at,
      :metadata,
      :realm_id,
      :location_id,
      :initiator_character_id,
      :target_character_id,
      :combat_id
    ])
    |> validate_required([
      :encounter_kind,
      :status,
      :started_at,
      :realm_id,
      :location_id,
      :initiator_character_id,
      :target_character_id
    ])
    |> validate_distinct_characters()
  end

  defp validate_distinct_characters(changeset) do
    if get_field(changeset, :initiator_character_id) == get_field(changeset, :target_character_id) do
      add_error(changeset, :target_character_id, "must differ from the initiator")
    else
      changeset
    end
  end
end
