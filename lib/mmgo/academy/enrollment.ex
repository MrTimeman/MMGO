defmodule MMGO.Academy.Enrollment do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.Realm

  @program_types [:basic_education, :academy_core, :extended_study, :academia]
  @tracks [:wizardry, :alchemy, :mastery]
  @statuses [:active, :completed, :withdrawn, :failed]
  @funding_types [:none, :grant, :self_funded]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_enrollments" do
    field :program_type, Ecto.Enum, values: @program_types
    field :track, Ecto.Enum, values: @tracks
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :funding_type, Ecto.Enum, values: @funding_types, default: :none
    field :started_at, :utc_datetime_usec
    field :expected_completion_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [
      :program_type,
      :track,
      :status,
      :funding_type,
      :started_at,
      :expected_completion_at,
      :completed_at,
      :metadata,
      :character_id,
      :realm_id
    ])
    |> validate_required([
      :program_type,
      :status,
      :funding_type,
      :started_at,
      :expected_completion_at,
      :character_id,
      :realm_id
    ])
    |> validate_program_track()
    |> unique_constraint(:character_id, name: :academy_enrollments_single_active_character_index)
  end

  defp validate_program_track(changeset) do
    case {get_field(changeset, :program_type), get_field(changeset, :track)} do
      {:academy_core, nil} ->
        add_error(changeset, :track, "is required for academy core study")

      {:basic_education, track} when not is_nil(track) ->
        add_error(changeset, :track, "must be empty for basic education")

      _other ->
        changeset
    end
  end
end
