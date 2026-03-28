defmodule MMGO.Repo.Migrations.CreateClubsSystem do
  use Ecto.Migration

  def change do
    create table(:academy_clubs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :realm_id, references(:realms, type: :binary_id, on_delete: :restrict), null: false

      add :founder_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :club_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_clubs, [:realm_id])
    create index(:academy_clubs, [:founder_character_id])

    create table(:academy_club_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :club_id, references(:academy_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_club_memberships, [:club_id])
    create index(:academy_club_memberships, [:character_id])

    create unique_index(:academy_club_memberships, [:club_id, :character_id],
             where: "status = 'active'",
             name: :academy_club_memberships_active_member_index
           )

    create table(:academy_club_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :club_id, references(:academy_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inviter_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :invitee_character_id, references(:characters, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime_usec, null: false
      add :responded_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:academy_club_invitations, [:club_id])
    create index(:academy_club_invitations, [:invitee_character_id])

    create unique_index(:academy_club_invitations, [:club_id, :invitee_character_id],
             where: "status = 'pending'",
             name: :academy_club_invitations_pending_invitee_index
           )
  end
end
