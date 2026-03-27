defmodule MMGO.Repo.Migrations.CreateGrimoiresAndCombatLoadouts do
  use Ecto.Migration

  def change do
    create table(:grimoires, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :capacity, :integer, null: false, default: 5
      add :weight, :integer, null: false, default: 1
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:grimoires, [:owner_character_id])
    create index(:grimoires, [:realm_id])

    create unique_index(:grimoires, [:owner_character_id],
             where: "status = 'active'",
             name: :grimoires_active_owner_index
           )

    create table(:grimoire_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :grimoire_id, references(:grimoires, type: :binary_id, on_delete: :delete_all),
        null: false

      add :spell_id, references(:spells, type: :binary_id, on_delete: :delete_all), null: false
      add :slot_index, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:grimoire_entries, [:grimoire_id, :spell_id],
             name: :grimoire_entries_grimoire_spell_index
           )

    create unique_index(:grimoire_entries, [:grimoire_id, :slot_index],
             name: :grimoire_entries_grimoire_slot_index
           )

    alter table(:combat_participants) do
      add :grimoire_id, references(:grimoires, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:combat_participants, [:grimoire_id])
  end
end
