defmodule MMGO.Repo.Migrations.AddSchoolQuirkToSpells do
  use Ecto.Migration

  def change do
    alter table(:spells) do
      add :school_quirk, :string
    end
  end
end
