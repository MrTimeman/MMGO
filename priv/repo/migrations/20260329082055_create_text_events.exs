defmodule MMGO.Repo.Migrations.CreateTextEvents do
  use Ecto.Migration

  def change do
    create table(:event_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :location_kind, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_templates, [:realm_id, :code],
             name: :event_templates_realm_code_index
           )

    create table(:event_options, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :template_id, references(:event_templates, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :label, :string, null: false
      add :position, :integer, null: false, default: 0
      add :action_key, :string, null: false
      add :result_text, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_options, [:template_id, :code],
             name: :event_options_template_code_index
           )

    create table(:event_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :delete_all), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, references(:event_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "active"
      add :selected_option_code, :string
      add :started_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_instances, [:character_id])
    create index(:event_instances, [:location_id])
  end
end
