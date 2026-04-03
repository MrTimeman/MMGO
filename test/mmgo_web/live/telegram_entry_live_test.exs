defmodule MMGOWeb.TelegramEntryLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
end
