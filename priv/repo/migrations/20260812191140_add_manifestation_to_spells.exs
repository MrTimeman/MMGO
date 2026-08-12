defmodule MMGO.Repo.Migrations.AddManifestationToSpells do
  use Ecto.Migration

  def change do
    alter table(:spells) do
      add :manifestation, :map
    end
  end
end
