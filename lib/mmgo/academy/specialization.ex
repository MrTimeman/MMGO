defmodule MMGO.Academy.Specialization do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.Realm

  @tracks [:wizardry, :alchemy, :mastery]
  @statuses [:active, :retired]
  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_specializations" do
    field :track, Ecto.Enum, values: @tracks
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :primary_school, Ecto.Enum, values: @schools
    field :secondary_school, Ecto.Enum, values: @schools
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(specialization, attrs) do
    specialization
    |> cast(attrs, [
      :track,
      :status,
      :primary_school,
      :secondary_school,
      :started_at,
      :ended_at,
      :metadata,
      :character_id,
      :realm_id
    ])
    |> validate_required([:track, :status, :started_at, :character_id, :realm_id])
    |> validate_school_pair()
    |> unique_constraint(:character_id,
      name: :academy_specializations_single_active_character_index
    )
  end

  defp validate_school_pair(changeset) do
    case get_field(changeset, :track) do
      :wizardry ->
        changeset
        |> validate_required([:primary_school, :secondary_school])
        |> validate_distinct_schools()

      _other ->
        changeset
    end
  end

  defp validate_distinct_schools(changeset) do
    if get_field(changeset, :primary_school) == get_field(changeset, :secondary_school) do
      add_error(changeset, :secondary_school, "must differ from the primary school")
    else
      changeset
    end
  end
end
