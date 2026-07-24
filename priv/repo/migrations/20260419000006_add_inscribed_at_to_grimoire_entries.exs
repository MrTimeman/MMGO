defmodule MMGO.Repo.Migrations.AddInscribedAtToGrimoireEntries do
  use Ecto.Migration

  def change do
    alter table(:grimoire_entries) do
      add :inscribed_at, :utc_datetime_usec
    end
  end
end
