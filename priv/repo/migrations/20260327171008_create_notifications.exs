defmodule MMGO.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :scheduled_at, :utc_datetime_usec, null: false
      add :delivered_at, :utc_datetime_usec
      add :payload, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :error, :text
      add :dedupe_key, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notifications, [:character_id])
    create index(:notifications, [:status])
    create unique_index(:notifications, [:dedupe_key], where: "dedupe_key IS NOT NULL")
  end
end
