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

  test "renders traveler contact correspondence in Russian", %{conn: conn, owner: owner} do
    request =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "overworld_contact_request",
        status: :sent,
        payload: %{
          "encounter_id" => "request-1",
          "requester_name" => "Тамиорн Найло"
        }
      })

    accepted =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "overworld_contact_accepted",
        status: :sent,
        payload: %{
          "encounter_id" => "request-2",
          "counterpart_name" => "Альберт Латыпов",
          "telegram_username" => "mmgo_mage"
        }
      })

    rejected =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "overworld_contact_rejected",
        status: :sent,
        payload: %{
          "encounter_id" => "request-3",
          "counterpart_name" => "Путник",
          "decision" => "decline"
        }
      })

    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/notifications")

    assert has_element?(
             view,
             "#notification-#{request.id}",
             "Запрос Telegram-контакта"
           )

    assert has_element?(view, "#notification-#{request.id}", "путник: Тамиорн Найло")
    assert has_element?(view, "#notification-#{accepted.id}", "Контактами обменялись")
    assert has_element?(view, "#notification-#{accepted.id}", "Telegram: @mmgo_mage")
    assert has_element?(view, "#notification-#{rejected.id}", "Запрос контакта закрыт")
    assert has_element?(view, "#notification-#{rejected.id}", "решение: отклонено")
  end

  test "translates internal payload codes and conceals unknown codes and delivery errors", %{
    conn: conn,
    owner: owner
  } do
    academy =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "academy_completed",
        status: :sent,
        payload: %{
          "program_type" => "basic_education",
          "outcome_tier" => "capstone_incomplete"
        }
      })

    extraction =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "dungeon_extraction_completed",
        status: :sent,
        payload: %{"extraction_type" => "return_ritual"}
      })

    unknown =
      notification_fixture(owner, %{
        channel: :in_app,
        kind: "unknown_internal_event",
        status: :failed,
        payload: %{"internal_mode" => "deep_internal_code"},
        error: "raw transport failure"
      })

    {:ok, view, _html} = live(session_conn(conn, owner), ~p"/notifications")

    assert has_element?(view, "#notification-#{academy.id}", "программа: Базовое образование")

    assert has_element?(
             view,
             "#notification-#{academy.id}",
             "итог: не пройден итоговый проект"
           )

    assert has_element?(view, "#notification-#{extraction.id}", "ритуал возвращения")
    assert has_element?(view, "#notification-#{unknown.id}", "сведения: записано")

    assert has_element?(
             view,
             "#notification-error-#{unknown.id}",
             "Послание не удалось доставить"
           )

    refute has_element?(view, "#notification-#{unknown.id}", "deep_internal_code")
    refute has_element?(view, "#notification-#{unknown.id}", "raw transport failure")
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
