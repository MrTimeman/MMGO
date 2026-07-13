defmodule MMGOWeb.NotificationsLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Notifications.Notification
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    owner = character_fixture(realm, "notification-owner", "Notification Owner")
    other = character_fixture(realm, "notification-other", "Notification Other")

    %{owner: owner, other: other}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/notifications")
  end

  test "renders only the scoped character's durable delivery history", %{
    conn: conn,
    owner: owner,
    other: other
  } do
    own_notification =
      notification_fixture(owner, %{
        kind: "research_completed",
        status: :sent,
        payload: %{"project_id" => "owned-project"},
        delivered_at: DateTime.utc_now()
      })

    other_notification =
      notification_fixture(other, %{
        kind: "journey_arrived",
        status: :failed,
        payload: %{"to_location_id" => "other-location"},
        error: "other delivery failure"
      })

    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/notifications")

    assert has_element?(view, "#notifications-screen")
    assert has_element?(view, "#notification-#{own_notification.id}")
    assert has_element?(view, "#notification-status-#{own_notification.id}")
    refute has_element?(view, "#notification-#{other_notification.id}")
  end

  defp notification_fixture(character, attrs) do
    suffix = System.unique_integer([:positive])

    defaults = %{
      character_id: character.id,
      channel: :telegram,
      kind: "journey_arrived",
      status: :pending,
      scheduled_at: DateTime.utc_now(),
      payload: %{"journey_id" => "journey-#{suffix}"},
      metadata: %{},
      dedupe_key: "notification-live-#{character.id}-#{suffix}"
    }

    %Notification{}
    |> Notification.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
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
