defmodule MMGOWeb.TelegramEntryLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts
  alias MMGO.Worlds
  alias MMGOWeb.TelegramEntryLive

  setup do
    {:ok, _realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    :ok
  end

  test "renders the first-open entry state for a new Telegram player", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TelegramEntryLive,
        session: %{
          "telegram_entry" => %{
            "telegram_user" => %{
              "id" => 9001,
              "username" => "aurora",
              "first_name" => "Aurora",
              "language_code" => "en"
            }
          }
        }
      )

    assert has_element?(view, "#telegram-entry-live")
    assert has_element?(view, "#entry-first-open")
    assert has_element?(view, "#entry-character-preview")
    assert has_element?(view, "#entry-primary-cta")
  end

  test "renders the recovery state when Telegram identity cannot be restored", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TelegramEntryLive, session: %{})

    assert has_element?(view, "#telegram-entry-live")
    assert has_element?(view, "#entry-recovery")
    assert has_element?(view, "#entry-retry")
    assert has_element?(view, "#entry-bot-fallback")
  end

  test "GET / serves quick resume for a returning Telegram player", %{conn: conn} do
    assert {:ok, _player} =
             Accounts.provision_from_telegram(%{
               "id" => 9101,
               "username" => "returner",
               "first_name" => "Returner"
             })

    {:ok, view, _html} = live(conn, "/?telegram_user_id=9101")

    assert has_element?(view, "#telegram-entry-live")
    assert has_element?(view, "#entry-resume")
    assert has_element?(view, "#entry-primary-cta")
  end

  test "GET / with a deep-link target bypasses the normal resume gate", %{conn: conn} do
    assert {:ok, _player} =
             Accounts.provision_from_telegram(%{
               "id" => 9102,
               "username" => "linkwalker",
               "first_name" => "Link"
             })

    {:ok, view, _html} = live(conn, "/?telegram_user_id=9102&target=journey")

    assert has_element?(view, "#telegram-entry-live")
    assert has_element?(view, "#entry-deep-link")
    refute has_element?(view, "#entry-resume")
  end
end
