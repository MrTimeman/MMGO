defmodule MMGO.Repo.Migrations.CreateSpellAndCombatTables do
  use Ecto.Migration

  def change do
    create table(:spells, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :creator_character_id,
          references(:characters, type: :binary_id, on_delete: :delete_all), null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :source_spell_id, references(:spells, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :formula, :string, null: false
      add :school, :string, null: false
      add :description, :text
      add :level_requirement, :integer, null: false, default: 1
      add :fatigue_cost, :integer, null: false, default: 0
      add :cooldown_turns, :integer, null: false, default: 0
      add :targeting, :string, null: false
      add :delivery_form, :string, null: false
      add :tags, {:array, :string}, null: false, default: []
      add :narrative_tags, {:array, :string}, null: false, default: []
      add :environment_tags, {:array, :string}, null: false, default: []
      add :environment_mode, :string, null: false, default: "none"
      add :effects, :map, null: false, default: fragment("'[]'::jsonb")
      add :interaction_rules, :map, null: false, default: fragment("'[]'::jsonb")
      add :failure_profile, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spells, [:creator_character_id])
    create index(:spells, [:realm_id])
    create index(:spells, [:school])

    create table(:combats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string, null: false, default: "duel"
      add :status, :string, null: false, default: "forming"
      add :turn_number, :integer, null: false, default: 1
      add :seed, :bigint, null: false
      add :environment_tags, {:array, :string}, null: false, default: []
      add :sides, :map, null: false, default: %{}
      add :winner_side, :string
      add :finished_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:combats, [:realm_id])
    create index(:combats, [:status])

    create table(:combat_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :combat_id, references(:combats, type: :binary_id, on_delete: :delete_all), null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :side, :string, null: false
      add :position, :integer, null: false, default: 0
      add :status, :string, null: false, default: "ready"
      add :fatigue, :integer, null: false, default: 0
      add :cooldowns, :map, null: false, default: %{}
      add :active_states, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:combat_participants, [:combat_id, :character_id])
    create index(:combat_participants, [:combat_id, :side])

    create table(:combat_turns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :combat_id, references(:combats, type: :binary_id, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :status, :string, null: false, default: "open"
      add :resolution, :map, null: false, default: %{}
      add :narration, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:combat_turns, [:combat_id, :number])

    create table(:combat_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :combat_turn_id, references(:combat_turns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :participant_id,
          references(:combat_participants, type: :binary_id, on_delete: :delete_all), null: false

      add :spell_id, references(:spells, type: :binary_id, on_delete: :nilify_all)
      add :action_type, :string, null: false
      add :target_side, :string

      add :target_participant_id,
          references(:combat_participants, type: :binary_id, on_delete: :nilify_all)

      add :payload, :map, null: false, default: %{}
      add :submitted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:combat_actions, [:combat_turn_id, :participant_id])

    create table(:combat_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :combat_id, references(:combats, type: :binary_id, on_delete: :delete_all), null: false

      add :combat_turn_id, references(:combat_turns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :turn_number, :integer, null: false
      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:combat_events, [:combat_id, :turn_number])
    create unique_index(:combat_events, [:combat_turn_id, :sequence])
  end
end
