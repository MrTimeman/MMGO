defmodule MMGOWeb.CharacterControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Federation.Migration
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "chooser-realm", name: "Княжество Зари", is_default: true})

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Хранитель", handle: "chooser-owner"})
      |> Repo.insert!()

    active = character_fixture(account, realm, "Тамиорн Найло", :active, %{})

    sealed =
      character_fixture(account, realm, "Альберт Латыпов", :frozen, %{
        "profile_kind" => "sealed_spirit",
        "hidden_presence" => true,
        "progression_tier" => "legendary"
      })

    %{account: account, active: active, sealed: sealed, realm: realm}
  end

  test "GET /characters renders a realm-aware Russian paper dossier", %{
    conn: conn,
    account: account,
    active: active,
    sealed: sealed
  } do
    conn = get(session_conn(conn, account, active), ~p"/characters")
    html = html_response(conn, 200)

    assert html =~ ~s(id="character-chooser")
    assert html =~ ~s(id="character-realm-)
    assert html =~ ~s(id="character-card-#{active.id}")
    assert html =~ ~s(id="character-card-#{sealed.id}")
    assert html =~ "Кем вы войдёте в мир?"
    assert html =~ "Запечатанный дух"
    assert html =~ "Княжество Зари"
  end

  test "POST selection activates the owned profile and freezes its sibling", %{
    conn: conn,
    account: account,
    active: active,
    sealed: sealed
  } do
    conn = post(session_conn(conn, account, active), ~p"/characters/#{sealed.id}/select")

    assert redirected_to(conn) == ~p"/map"
    assert get_session(conn, :current_character_id) == sealed.id
    assert Accounts.get_character!(sealed.id).status == :active
    assert Accounts.get_character!(active.id).status == :frozen
  end

  test "POST selection rejects a profile owned by another account", %{
    conn: conn,
    account: account,
    active: active,
    realm: realm
  } do
    other_account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Чужой", handle: "chooser-outsider"})
      |> Repo.insert!()

    other = character_fixture(other_account, realm, "Чужой маг", :active, %{})
    conn = post(session_conn(conn, account, active), ~p"/characters/#{other.id}/select")

    assert redirected_to(conn) == ~p"/characters"
    assert get_session(conn, :current_character_id) == active.id
    assert Accounts.get_character!(active.id).status == :active
  end

  test "an already-active local migration destination remains a safe continuation", %{
    conn: conn,
    account: account,
    active: active,
    sealed: sealed,
    realm: realm
  } do
    now = DateTime.utc_now()

    {:ok, destination_realm} =
      Worlds.create_realm(%{slug: "chooser-destination", name: "Северный предел"})

    active =
      active
      |> Ecto.Changeset.change(realm_id: destination_realm.id)
      |> Repo.update!()

    %Migration{}
    |> Migration.changeset(%{
      account_id: account.id,
      mode: :local,
      status: :active,
      origin_realm_id: realm.id,
      destination_realm_id: destination_realm.id,
      origin_character_id: sealed.id,
      destination_character_id: active.id,
      destination_character_name: active.name,
      currency_amount: 10,
      converted_currency_amount: 10,
      source_level: sealed.level,
      destination_level: active.level,
      source_xp: sealed.xp,
      destination_xp: active.xp,
      freeze_started_at: now,
      freeze_ends_at: DateTime.add(now, 86_400, :second),
      passive_xp_awarded: 0
    })
    |> Repo.insert!()

    dossier_conn = get(session_conn(conn, account, sealed), ~p"/characters")
    html = html_response(dossier_conn, 200)
    assert html =~ ~s(id="select-character-#{active.id}")
    refute html =~ ~s(id="select-character-#{sealed.id}")

    continue_conn =
      dossier_conn
      |> recycle()
      |> post(~p"/characters/#{active.id}/select")

    assert redirected_to(continue_conn) == ~p"/map"
    assert get_session(continue_conn, :current_character_id) == active.id
  end

  defp session_conn(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  defp character_fixture(account, realm, name, status, metadata) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: status, metadata: metadata})
    |> Repo.insert!()
  end
end
