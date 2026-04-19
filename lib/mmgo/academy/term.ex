defmodule MMGO.Academy.Term do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Academy.{CourseEnrollment, Enrollment}
  alias MMGO.Worlds.Realm

  @statuses [:pending, :active, :completed, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academy_terms" do
    field :term_number, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :exam_score, :integer
    field :metadata, :map, default: %{}

    belongs_to :enrollment, Enrollment
    belongs_to :realm, Realm
    has_many :course_enrollments, CourseEnrollment, foreign_key: :term_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(term, attrs) do
    term
    |> cast(attrs, [
      :term_number,
      :status,
      :started_at,
      :ended_at,
      :exam_score,
      :metadata,
      :enrollment_id,
      :realm_id
    ])
    |> validate_required([:term_number, :status, :enrollment_id, :realm_id])
    |> validate_number(:term_number, greater_than: 0)
    |> validate_number(:exam_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:enrollment_id, :term_number],
      name: :academy_terms_enrollment_term_number_index
    )
  end
end
