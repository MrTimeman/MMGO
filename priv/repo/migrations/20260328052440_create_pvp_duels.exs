defmodule MMGO.Repo.Migrations.CreatePvpDuels do
  use Ecto.Migration

  def change do
    create table(:pvp_duels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :challenger_character_id,
          references(:characters, type: :binary_id, on_delete: :restrict), null: false

      add :opponent_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :winner_character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)

      add :escrow_account_id,
          references(:economy_accounts, type: :binary_id, on_delete: :nilify_all)

      add :combat_id, references(:combats, type: :binary_id, on_delete: :nilify_all)
      add :stake_amount, :bigint, null: false
      add :pot_amount, :bigint, null: false
      add :tax_rate_bps, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :challenged_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:pvp_duels, [:realm_id])
    create index(:pvp_duels, [:challenger_character_id])
    create index(:pvp_duels, [:opponent_character_id])
    create index(:pvp_duels, [:status])
    create unique_index(:pvp_duels, [:combat_id], where: "combat_id IS NOT NULL")
  end
end
