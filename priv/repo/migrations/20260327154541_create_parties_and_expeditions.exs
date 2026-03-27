defmodule MMGO.Repo.Migrations.CreatePartiesAndExpeditions do
  use Ecto.Migration

  def change do
    create table(:parties, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :leader_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:parties, [:realm_id])
    create index(:parties, [:leader_character_id])

    create table(:party_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :party_id, references(:parties, type: :binary_id, on_delete: :delete_all), null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:party_memberships, [:party_id])
    create index(:party_memberships, [:character_id])

    create unique_index(:party_memberships, [:character_id],
             where: "status = 'active'",
             name: :party_memberships_single_active_character_index
           )

    create unique_index(:party_memberships, [:party_id, :character_id],
             where: "status = 'active'",
             name: :party_memberships_active_party_character_index
           )

    create table(:expeditions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :party_id, references(:parties, type: :binary_id, on_delete: :restrict), null: false
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :expedition_type, :string, null: false, default: "dungeon"
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:expeditions, [:party_id])
    create index(:expeditions, [:realm_id])
    create index(:expeditions, [:location_id])

    create unique_index(:expeditions, [:party_id],
             where: "status = 'active'",
             name: :expeditions_single_active_party_index
           )

    create table(:expedition_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :expedition_id, references(:expeditions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :party_membership_id,
          references(:party_memberships, type: :binary_id, on_delete: :restrict), null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:expedition_members, [:expedition_id])
    create index(:expedition_members, [:character_id])

    create unique_index(:expedition_members, [:character_id],
             where: "status = 'active'",
             name: :expedition_members_single_active_character_index
           )

    create unique_index(:expedition_members, [:expedition_id, :character_id],
             where: "status = 'active'",
             name: :expedition_members_active_expedition_character_index
           )
  end
end
