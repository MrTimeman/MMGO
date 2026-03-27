defmodule MMGO.Operator.AuditEvent do
  use Ecto.Schema

  import Ecto.Changeset

  @results [:ok, :error]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "operator_audit_events" do
    field :actor_handle, :string
    field :action, :string
    field :result, Ecto.Enum, values: @results
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [:actor_handle, :action, :result, :metadata])
    |> validate_required([:actor_handle, :action, :result])
    |> validate_length(:actor_handle, min: 2, max: 80)
    |> validate_length(:action, min: 2, max: 120)
  end
end
