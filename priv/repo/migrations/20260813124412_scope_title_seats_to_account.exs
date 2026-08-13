defmodule MMGO.Repo.Migrations.ScopeTitleSeatsToAccount do
  use Ecto.Migration

  # Arena players may keep several profiles for different school combinations,
  # so "one seat per profile" would still let one person hold both seats with
  # two characters. The holder's account is denormalised onto the seat purely so
  # the database can forbid that outright.
  def up do
    alter table(:arena_title_seats) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE arena_title_seats
    SET account_id = arena_profiles.account_id
    FROM arena_profiles
    WHERE arena_profiles.id = arena_title_seats.profile_id
    """

    alter table(:arena_title_seats) do
      modify :account_id, :binary_id, null: false
    end

    create index(:arena_title_seats, [:account_id])

    create unique_index(:arena_title_seats, [:season, :account_id],
             where: "status = 'held'",
             name: :arena_title_seats_one_seat_per_account_index
           )
  end

  def down do
    drop index(:arena_title_seats, [:season, :account_id],
           name: :arena_title_seats_one_seat_per_account_index
         )

    drop index(:arena_title_seats, [:account_id])

    alter table(:arena_title_seats) do
      remove :account_id
    end
  end
end
