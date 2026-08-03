defmodule MMGO.Spells.CreationAttempt do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Spells.Spell
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:queued, :resolving, :sealed_success, :sealed_failure, :revealed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spell_creation_attempts" do
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :input, :map, default: %{}
    field :outcome, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :revealed_at, :utc_datetime_usec

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    has_one :spell, Spell

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :status,
      :input,
      :outcome,
      :started_at,
      :completes_at,
      :resolved_at,
      :revealed_at
    ])
    |> validate_required([
      :status,
      :input,
      :outcome,
      :started_at,
      :completes_at,
      :character_id,
      :realm_id,
      :location_id
    ])
    |> unique_constraint(:character_id,
      name: :spell_creation_attempts_single_unrevealed_character_index
    )
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:realm_id)
    |> foreign_key_constraint(:location_id)
  end

  def statuses, do: @statuses
end
