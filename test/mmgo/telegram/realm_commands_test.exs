defmodule MMGO.Telegram.RealmCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
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

    character = character_fixture(origin_realm, origin_city, "traveler", "Traveler")
    {:ok, _funding} = Economy.grant_from_treasury(origin_realm, character, 200)

    %{character: character}
  end

  test "/realms commands expose discovery, quote, and migration", %{character: character} do
    assert {:ok, list_text} = Commands.process_message(character, %{"text" => "/realms list"})
    assert list_text =~ "silver-sea"

    assert {:ok, quote_text} =
             Commands.process_message(character, %{"text" => "/realms quote silver-sea 100"})

    assert quote_text =~ "100 GLD -> 75 SLV"

    assert {:ok, migrate_text} =
             Commands.process_message(character, %{"text" => "/realms migrate silver-sea 100"})

    assert migrate_text =~ "Migration started"

    assert {:ok, migrations_text} =
             Commands.process_message(character, %{"text" => "/realms migrations"})

    assert migrations_text =~ "canonical -> silver-sea"
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
