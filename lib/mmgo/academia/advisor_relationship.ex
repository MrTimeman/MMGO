defmodule MMGO.Academia.AdvisorRelationship do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Academia.Project
  alias MMGO.Worlds.Realm

  @statuses [:active, :ended]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "advisor_relationships" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :professor_character, Character, foreign_key: :professor_character_id
    belongs_to :student_character, Character, foreign_key: :student_character_id
    belongs_to :project, Project
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :status,
      :started_at,
      :ended_at,
      :metadata,
      :professor_character_id,
      :student_character_id,
      :project_id,
      :realm_id
    ])
    |> validate_required([
      :status,
      :started_at,
      :professor_character_id,
      :student_character_id,
      :realm_id
    ])
    |> unique_constraint(:student_character_id,
      name: :advisor_relationships_active_student_index
    )
  end
end
