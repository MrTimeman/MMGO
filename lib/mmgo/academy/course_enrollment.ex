defmodule MMGO.Academy.CourseEnrollment do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Academy.{Course, Term}

  @statuses [:enrolled, :completed, :dropped]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_enrollments" do
    field :status, Ecto.Enum, values: @statuses, default: :enrolled
    field :grade, :integer
    field :enrolled_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :term, Term
    belongs_to :course, Course
    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(course_enrollment, attrs) do
    course_enrollment
    |> cast(attrs, [:status, :grade, :enrolled_at, :metadata, :term_id, :course_id, :character_id])
    |> validate_required([:status, :enrolled_at, :term_id, :course_id, :character_id])
    |> validate_number(:grade, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:term_id, :course_id, :character_id],
      name: :course_enrollments_term_course_character_index
    )
  end
end
