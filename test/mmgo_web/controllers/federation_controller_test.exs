defmodule MMGOWeb.FederationControllerTest do
  use MMGOWeb.ConnCase, async: false

  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        public_endpoint: "http://localhost:4002",
        allow_migration: true,
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "origin-city",
        name: "Origin City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    realm =
      realm
      |> Realm.changeset(%{entry_location_id: city.id})
      |> Repo.update!()

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    %{realm: realm}
  end

  test "GET /api/federation/realm-manifest exposes the local realm manifest", %{conn: conn} do
    conn = get(conn, ~p"/api/federation/realm-manifest")

    assert %{
             "slug" => "canonical",
             "currency_code" => "GLD",
             "ruleset" => %{"magic_scope" => "tower_and_dungeon"}
           } = json_response(conn, 200)
  end

  test "POST /api/federation/import-migration requires authorization", %{conn: conn} do
    conn = post(conn, ~p"/api/federation/import-migration", %{})
    assert json_response(conn, 401) == %{"ok" => false, "error" => "unauthorized"}
  end

  test "POST /api/federation/import-migration imports a remote character snapshot", %{conn: conn} do
    payload = %{
      "account_handle" => "remote-user",
      "display_name" => "Remote User",
      "character_name" => "Remote Traveler",
      "destination_level" => 8,
      "destination_xp" => 120,
      "converted_currency_amount" => 75,
      "origin_realm_slug" => "silver-sea",
      "migration_reference" => "migration-1"
    }

    conn =
      conn
      |> put_req_header("authorization", "Bearer test-federation-token")
      |> post(~p"/api/federation/import-migration", payload)

    assert %{
             "destination_character_id" => _id,
             "destination_character_name" => "Remote Traveler",
             "destination_character_ref" => "migration-1"
           } = json_response(conn, 200)
  end
end
