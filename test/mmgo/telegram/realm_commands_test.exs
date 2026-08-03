defmodule MMGO.Telegram.RealmCommandsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  setup do
    bypass = Bypass.open()
    original_operator_config = Application.get_env(:mmgo, MMGO.Operator)
    Application.put_env(:mmgo, MMGO.Operator, handles: ["traveler"])

    on_exit(fn ->
      if original_operator_config do
        Application.put_env(:mmgo, MMGO.Operator, original_operator_config)
      else
        Application.delete_env(:mmgo, MMGO.Operator)
      end
    end)

    {:ok, origin_realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        allow_migration: true,
        public_endpoint: "http://localhost:4002"
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

    origin_realm =
      origin_realm
      |> Realm.changeset(%{entry_location_id: origin_city.id})
      |> Repo.update!()

    {:ok, _origin_treasury} = Economy.ensure_treasury_account(origin_realm, 1_000)
    character = character_fixture(origin_realm, origin_city, "traveler", "Traveler")
    {:ok, _funding} = Economy.grant_from_treasury(origin_realm, character, 200)

    remote_manifest = %{
      "slug" => "silver-sea",
      "name" => "Silver Sea",
      "status" => "active",
      "ruleset_version" => 1,
      "currency_code" => "SLV",
      "public_endpoint" => "http://localhost:#{bypass.port}",
      "public_description" => "A test destination realm",
      "operator_name" => "Silver Keeper",
      "allow_migration" => true,
      "population_hint" => 42,
      "entry_location_slug" => "arrival-city",
      "ruleset" => %{"magic_scope" => "global"},
      "metadata" => %{}
    }

    Bypass.stub(bypass, "GET", "/manifest", fn conn ->
      Plug.Conn.resp(conn, 200, Jason.encode!(remote_manifest))
    end)

    Bypass.stub(bypass, "POST", "/api/federation/import-migration", fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer remote-token"]

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "destination_character_id" => "remote-char-1",
          "destination_character_name" => "Traveler Remote",
          "destination_character_ref" => "remote-ref-1"
        })
      )
    end)

    {:ok, _remote_realm} =
      Federation.register_remote_realm("http://localhost:#{bypass.port}/manifest", "remote-token")

    %{character: character, bypass: bypass}
  end

  test "/realms commands expose discovery, quote, and migration", %{character: character} do
    assert {:ok, list_text} = Commands.process_message(character, %{"text" => "/realms list"})
    assert list_text =~ "silver-sea"

    assert {:ok, quote_text} =
             Commands.process_message(character, %{"text" => "/realms quote silver-sea 100"})

    assert quote_text =~ "100 GLD"
    assert quote_text =~ "SLV"

    assert {:ok, migrate_text} =
             Commands.process_message(character, %{"text" => "/realms migrate silver-sea 100"})

    assert migrate_text =~ "Переселение"

    assert {:ok, migrations_text} =
             Commands.process_message(character, %{"text" => "/realms migrations"})

    assert migrations_text =~ "canonical → silver-sea"
  end

  test "/admin federation commands register sync and show manifest", %{character: character} do
    assert {:ok, manifest_text} =
             Commands.process_message(character, %{"text" => "/admin federation manifest"})

    assert manifest_text =~ "Манифест локального мира"

    assert {:ok, sync_text} =
             Commands.process_message(character, %{"text" => "/admin federation sync silver-sea"})

    assert sync_text =~ "Удалённый мир silver-sea синхронизирован"
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
