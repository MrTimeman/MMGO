defmodule MMGO.FederationTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  setup do
    {:ok, origin_realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        allow_migration: true
      })

    {:ok, destination_realm} =
      Worlds.create_realm(%{
        slug: "silver-sea",
        name: "Silver Sea",
        currency_code: "SLV",
        allow_migration: true
      })

    {:ok, origin_city} =
      Worlds.create_location(origin_realm, %{
        slug: "origin-city",
        name: "Origin City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, destination_city} =
      Worlds.create_location(destination_realm, %{
        slug: "arrival-city",
        name: "Arrival City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    destination_realm =
      destination_realm
      |> Realm.changeset(%{
        entry_location_id: destination_city.id,
        public_endpoint: "https://silver-sea.test",
        public_description: "A test destination realm",
        operator_name: "Silver Keeper",
        population_hint: 42
      })
      |> Repo.update!()

    {:ok, _origin_treasury} = Economy.ensure_treasury_account(origin_realm, 1_000)
    {:ok, _destination_treasury} = Economy.ensure_treasury_account(destination_realm, 2_000)

    {:ok, _rate} =
      Federation.set_exchange_rate(origin_realm, destination_realm, %{
        numerator: 75,
        denominator: 100
      })

    character = character_fixture(origin_realm, origin_city, "migrant", "Migrant")
    {:ok, _funding} = Economy.grant_from_treasury(origin_realm, character, 200)

    %{
      origin_realm: origin_realm,
      destination_realm: destination_realm,
      origin_city: origin_city,
      destination_city: destination_city,
      character: character
    }
  end

  test "list_discoverable_realms/1 returns no remote realms when none are registered", %{
    origin_realm: origin_realm
  } do
    assert Federation.list_discoverable_realms(origin_realm.id) == []
  end

  test "quote_exchange/3 uses configured exchange rates", %{
    origin_realm: origin_realm,
    destination_realm: destination_realm
  } do
    assert {:ok, quote} = Federation.quote_exchange(origin_realm.id, destination_realm.id, 200)
    assert quote.converted_amount == 150
  end

  test "start_migration/4 freezes the origin character and creates a destination character", %{
    character: character,
    destination_realm: destination_realm,
    destination_city: destination_city
  } do
    assert {:ok,
            %{
              migration: migration,
              origin_character: frozen_origin,
              destination_character: destination_character
            }} =
             Federation.start_migration(character, destination_realm, 100,
               started_at: ~U[2026-03-28 12:00:00Z],
               freeze_game_days: 1
             )

    assert migration.status == :active
    assert migration.currency_amount == 100
    assert migration.converted_currency_amount == 75
    assert frozen_origin.status == :frozen
    assert destination_character.realm_id == destination_realm.id
    assert destination_character.current_location_id == destination_city.id
    assert destination_character.level == 8
    assert destination_character.xp == 0

    {:ok, destination_account} = Economy.ensure_character_account(destination_character)
    assert Economy.get_account!(destination_account.id).current_balance == 75
  end

  test "complete_migration_by_id/2 unfreezes the origin character and awards passive XP", %{
    character: character,
    destination_realm: destination_realm
  } do
    {:ok, %{migration: migration}} =
      Federation.start_migration(character, destination_realm, 100,
        started_at: ~U[2026-03-28 12:00:00Z],
        freeze_game_days: 1
      )

    assert {:ok, %{migration: completed_migration, origin_character: restored_origin}} =
             Federation.complete_migration_by_id(migration.id,
               now: migration.freeze_ends_at,
               force: true
             )

    assert completed_migration.status == :completed
    assert restored_origin.status == :active
    assert restored_origin.xp == 10
  end

  test "export_realm_manifest/1 exposes operator-friendly realm metadata", %{
    destination_realm: destination_realm
  } do
    manifest = Federation.export_realm_manifest(destination_realm)
    assert manifest.slug == "silver-sea"
    assert manifest.currency_code == "SLV"
    assert manifest.public_endpoint == "https://silver-sea.test"
    assert manifest.population_hint == 1
    assert manifest.ruleset["magic_scope"] == "tower_and_dungeon"
  end

  test "import_remote_character/2 is idempotent for the same migration reference", %{
    destination_realm: destination_realm
  } do
    payload = %{
      "account_handle" => "remote-migrant",
      "display_name" => "Remote Migrant",
      "character_name" => "Remote Migrant",
      "destination_level" => 7,
      "destination_xp" => 99,
      "converted_currency_amount" => 125,
      "origin_realm_slug" => "emberkeep",
      "migration_reference" => "migration-ref-1"
    }

    account_count_before = Repo.aggregate(Account, :count, :id)
    character_count_before = Repo.aggregate(Character, :count, :id)

    assert {:ok, first_response} =
             Federation.import_remote_character(destination_realm, payload)

    assert {:ok, second_response} =
             Federation.import_remote_character(destination_realm, payload)

    assert first_response == second_response
    assert Repo.aggregate(Account, :count, :id) == account_count_before + 1
    assert Repo.aggregate(Character, :count, :id) == character_count_before + 1

    imported_character = Repo.get!(Character, first_response.destination_character_id)
    assert imported_character.import_reference == "migration-ref-1"

    {:ok, destination_account} = Economy.ensure_character_account(imported_character)
    assert Economy.get_account!(destination_account.id).current_balance == 125
    assert Economy.treasury_account_for_realm(destination_realm.id).current_balance == 1_875
  end

  test "import_remote_character/2 requires a migration reference", %{
    destination_realm: destination_realm
  } do
    assert {:error, changeset} =
             Federation.import_remote_character(destination_realm, %{
               "account_handle" => "remote-migrant",
               "display_name" => "Remote Migrant",
               "character_name" => "Remote Migrant",
               "destination_level" => 7,
               "destination_xp" => 99,
               "converted_currency_amount" => 125,
               "origin_realm_slug" => "emberkeep"
             })

    assert %{status: ["payload is missing migration_reference"]} = errors_on(changeset)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
