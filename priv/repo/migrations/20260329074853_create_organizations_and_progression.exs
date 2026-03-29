defmodule MMGO.Repo.Migrations.CreateOrganizationsAndProgression do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :founder_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "active"
      add :hierarchy_rules, :map, null: false, default: %{}
      add :fast_travel_enabled, :boolean, null: false, default: false
      add :linked_location_ids, {:array, :binary_id}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:organizations, [:realm_id])
    create index(:organizations, [:founder_character_id])

    create table(:organization_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :title, :string, null: false
      add :rank, :integer, null: false, default: 0
      add :permissions, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_roles, [:organization_id, :code],
             name: :organization_roles_org_code_index
           )

    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :role_id, references(:organization_roles, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_memberships, [:organization_id, :character_id],
             where: "status = 'active'",
             name: :organization_memberships_active_member_index
           )

    create table(:organization_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inviter_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :invitee_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :role_id, references(:organization_roles, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime_usec, null: false
      add :responded_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_invitations, [:organization_id, :invitee_character_id],
             where: "status = 'pending'",
             name: :organization_invitations_pending_invitee_index
           )

    create table(:progression_milestones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :level, :integer, null: false
      add :code, :string, null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "active"
      add :effects, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:progression_milestones, [:level])
    create unique_index(:progression_milestones, [:code])

    create table(:progression_reward_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :milestone_id,
          references(:progression_milestones, type: :binary_id, on_delete: :restrict), null: false

      add :source, :string, null: false
      add :granted_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:progression_reward_grants, [:character_id, :milestone_id],
             name: :progression_reward_grants_character_milestone_index
           )
  end
end
