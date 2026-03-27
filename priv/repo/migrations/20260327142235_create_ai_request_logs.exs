defmodule MMGO.Repo.Migrations.CreateAiRequestLogs do
  use Ecto.Migration

  def change do
    create table(:ai_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :status, :string, null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :prompt_version, :string, null: false
      add :request_payload, :map, null: false, default: %{}
      add :response_payload, :map, null: false, default: %{}
      add :latency_ms, :integer, null: false
      add :error, :text
      add :metadata, :map, null: false, default: %{}
      add :character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
      add :spell_id, references(:spells, type: :binary_id, on_delete: :nilify_all)
      add :combat_id, references(:combats, type: :binary_id, on_delete: :nilify_all)
      add :combat_turn_id, references(:combat_turns, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ai_requests, [:kind])
    create index(:ai_requests, [:status])
    create index(:ai_requests, [:character_id])
    create index(:ai_requests, [:spell_id])
    create index(:ai_requests, [:combat_id])
    create index(:ai_requests, [:combat_turn_id])
  end
end
