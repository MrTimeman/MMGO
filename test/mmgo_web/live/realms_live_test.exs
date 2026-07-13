defmodule MMGOWeb.RealmsLiveTest do
  use MMGOWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation
  alias MMGO.Federation.RemoteRealm
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    bypass = Bypass.open()

    Bypass.stub(bypass, "POST", "/api/federation/import-migration", fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer remote-token"]

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "destination_character_id" => "moon-arrival-1",
          "destination_character_name" => "Realm Owner of Moon",
          "destination_character_ref" => "moon-ref-1"
        })
      )
    end)

    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
      })

    owner = character_fixture(realm, "realm-owner", "Realm Owner")
    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    assert {:ok, _funding} = Economy.grant_from_treasury(realm, owner, 200)

    {:ok, remote} =
      %RemoteRealm{}
      |> RemoteRealm.changeset(%{
        slug: "moon-gate",
        name: "Moon Gate",
        status: :active,
        manifest_url: "https://moon.example/manifest",
        public_endpoint: "http://localhost:#{bypass.port}",
        currency_code: "LUN",
        public_description: "A verified remote realm.",
        operator_name: "Moon Operator",
        allow_migration: true,
        population_hint: 42,
        ruleset_version: 1,
        ruleset: %{"magic_scope" => "global"},
        entry_location_slug: "moon-harbor",
        access_token: "remote-token",
        last_synced_at: DateTime.utc_now(),
        metadata: %{}
      })
      |> Repo.insert()

    %{owner: owner, remote: remote, bypass: bypass}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/realms")
  end

  test "renders the active remote manifest with a scoped migration form", %{
    conn: conn,
    owner: owner,
    remote: remote
  } do
    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/realms")

    assert has_element?(view, "#realms-screen")
    assert has_element?(view, "#remote-realm-#{remote.id}")
    assert has_element?(view, "#realm-migrations-empty")
    assert has_element?(view, "#realms-start-migration-#{remote.id}")
  end

  test "starts a remote migration from the browser and keeps its frozen owner on the migration surface",
       %{
         conn: conn,
         owner: owner,
         remote: remote
       } do
    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/realms")

    view
    |> form("#realms-start-migration-#{remote.id}", %{
      "migration" => %{"destination_id" => remote.id, "amount" => "100"}
    })
    |> render_submit()

    assert has_element?(view, "#realms-active-migration")
    assert has_element?(view, "#realms-remote-import-status")
    refute has_element?(view, "#realms-retry-migration")
    assert Repo.get!(Character, owner.id).status == :frozen

    [migration] = Federation.list_migrations_for_account(owner.account_id)
    assert Federation.remote_import_status(migration) == :accepted

    {:ok, frozen_view, _html} = live(session_conn(build_conn(), owner), ~p"/realms")
    assert has_element?(frozen_view, "#realms-active-migration")
  end

  test "keeps a failed remote handoff visible and lets its frozen owner retry it", %{
    conn: conn,
    owner: owner,
    remote: remote,
    bypass: bypass
  } do
    failing_bypass = Bypass.open()

    Bypass.stub(failing_bypass, "POST", "/api/federation/import-migration", fn conn ->
      Plug.Conn.resp(conn, 503, Jason.encode!(%{"ok" => false}))
    end)

    remote
    |> RemoteRealm.changeset(%{public_endpoint: "http://localhost:#{failing_bypass.port}"})
    |> Repo.update!()

    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/realms")

    view
    |> form("#realms-start-migration-#{remote.id}", %{
      "migration" => %{"destination_id" => remote.id, "amount" => "100"}
    })
    |> render_submit()

    assert has_element?(view, "#realms-retry-migration")
    assert Repo.get!(Character, owner.id).status == :frozen

    Repo.get!(RemoteRealm, remote.id)
    |> RemoteRealm.changeset(%{public_endpoint: "http://localhost:#{bypass.port}"})
    |> Repo.update!()

    view
    |> element("#realms-retry-migration")
    |> render_click()

    refute has_element?(view, "#realms-retry-migration")
    assert has_element?(view, "#realms-remote-import-status", "подтвердил")
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
  end

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
