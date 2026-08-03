defmodule MMGO.Repo.Migrations.AddReadAtToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :read_at, :utc_datetime_usec
    end

    create index(:notifications, [:character_id, :read_at])
  end
end
