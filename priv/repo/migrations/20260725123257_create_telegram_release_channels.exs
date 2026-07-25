defmodule MMGO.Repo.Migrations.CreateTelegramReleaseChannels do
  use Ecto.Migration

  def change do
    create table(:telegram_release_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :chat_id, :bigint, null: false
      add :chat_title, :string
      add :configured_by_telegram_user_id, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telegram_release_channels, [:key])
  end
end
