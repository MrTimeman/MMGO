defmodule MMGO.FederationRemoteTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  setup do
    bypass = Bypass.open()

    {:ok, origin_realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        allow_migration: true,
        public_endpoint: "http://localhost:4002",
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
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

    character = character_fixture(origin_realm, origin_city, "migrant", "Migrant")
    {:ok, _funding} = Economy.grant_from_treasury(origin_realm, character, 200)

    remote_manifest = %{
      "slug" => "silver-sea",
      "name" => "Silver Sea",
      "status" => "active",
      "ruleset_version" => 1,
      "currency_code" => "SLV",
      "public_endpoint" => "http://localhost:#{bypass.port}",
      "public_description" => "A remote realm",
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
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "migrant"

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "destination_character_id" => "remote-char-1",
          "destination_character_name" => "Migrant Remote",
          "destination_character_ref" => "remote-ref-1"
        })
      )
    end)

    %{bypass: bypass, origin_realm: origin_realm, character: character}
  end

  test "register_remote_realm/2 stores a remote realm from its manifest", %{bypass: bypass} do
    assert {:ok, remote_realm} =
             Federation.register_remote_realm(
               "http://localhost:#{bypass.port}/manifest",
               "remote-token"
             )

    assert remote_realm.slug == "silver-sea"
    assert remote_realm.ruleset["magic_scope"] == "global"
    assert remote_realm.population_hint == 42
  end

  test "quote_remote_exchange/3 discounts small-population realms", %{
    origin_realm: origin_realm,
    bypass: bypass
  } do
    {:ok, remote_realm} =
      Federation.register_remote_realm("http://localhost:#{bypass.port}/manifest", "remote-token")

    assert {:ok, quote} = Federation.quote_remote_exchange(origin_realm, remote_realm, 100)
    assert quote.source_population == 1
    assert quote.destination_population == 42
    assert quote.converted_amount == 2
  end

  test "start_migration/4 to a remote realm freezes the origin character and records a remote migration",
       %{character: character, bypass: bypass} do
    {:ok, remote_realm} =
      Federation.register_remote_realm("http://localhost:#{bypass.port}/manifest", "remote-token")

    assert {:ok,
            %{migration: migration, origin_character: frozen_origin, remote_response: response}} =
             Federation.start_migration(character, remote_realm, 100,
               started_at: ~U[2026-03-28 12:00:00Z],
               freeze_game_days: 1
             )

    assert migration.mode == :remote
    assert migration.remote_realm_id == remote_realm.id
    assert migration.destination_character_name == "Migrant Remote"
    assert migration.destination_external_ref == "remote-ref-1"
    assert frozen_origin.status == :frozen
    assert response["destination_character_ref"] == "remote-ref-1"
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
