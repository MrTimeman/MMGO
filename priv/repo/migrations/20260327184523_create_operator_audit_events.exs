defmodule MMGO.Repo.Migrations.CreateOperatorAuditEvents do
  use Ecto.Migration

  def change do
    create table(:operator_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_handle, :string, null: false
      add :action, :string, null: false
      add :result, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:operator_audit_events, [:inserted_at])
  end
end
