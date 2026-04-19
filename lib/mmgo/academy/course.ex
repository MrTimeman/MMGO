defmodule MMGO.Academy.Course do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Academia.Publication
  alias MMGO.Worlds.Realm

  @sources [:seeded, :published]
  @tracks [:wizardry, :alchemy, :mastery]
  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]
  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_courses" do
    field :source, Ecto.Enum, values: @sources, default: :seeded
    field :npc_professor_code, :string
    field :title, :string
    field :track, Ecto.Enum, values: @tracks
    field :school, Ecto.Enum, values: @schools
    field :syllabus, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :publication, Publication

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :source,
      :npc_professor_code,
      :title,
      :track,
      :school,
      :syllabus,
      :status,
      :metadata,
      :realm_id,
      :publication_id
    ])
    |> validate_required([:source, :title, :status, :realm_id])
    |> validate_length(:title, min: 3, max: 200)
  end
end
