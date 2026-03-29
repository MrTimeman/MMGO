defmodule MMGO.Events.Option do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Events.Template

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_options" do
    field :code, :string
    field :label, :string
    field :position, :integer, default: 0
    field :action_key, :string
    field :result_text, :string
    field :metadata, :map, default: %{}

    belongs_to :template, Template

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:code, :label, :position, :action_key, :result_text, :metadata, :template_id])
    |> validate_required([:code, :label, :position, :action_key, :result_text, :template_id])
    |> validate_length(:code, min: 2, max: 80)
    |> validate_length(:label, min: 2, max: 120)
    |> validate_length(:result_text, min: 2, max: 500)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint(:code, name: :event_options_template_code_index)
  end
end
