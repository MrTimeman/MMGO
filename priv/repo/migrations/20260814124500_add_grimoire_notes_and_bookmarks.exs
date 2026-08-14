defmodule MMGO.Repo.Migrations.AddGrimoireNotesAndBookmarks do
  use Ecto.Migration

  # A grimoire that only holds formulas is a list. What makes it the player's
  # own book is what they write in the margins and where they put their ribbons.
  def change do
    alter table(:spells) do
      add :note, :text
    end

    alter table(:grimoires) do
      add :note, :text
    end

    create table(:grimoire_bookmarks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :grimoire_id, references(:grimoires, type: :binary_id, on_delete: :delete_all),
        null: false

      add :label, :string, null: false
      # The page the ribbon is tucked into, one-based.
      add :page, :integer, null: false, default: 1
      # Where the ribbon sits among its siblings along the top of the book.
      add :position, :integer, null: false, default: 0
      add :colour, :string
      add :icon, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:grimoire_bookmarks, [:grimoire_id])
    create unique_index(:grimoire_bookmarks, [:grimoire_id, :label])
  end
end
