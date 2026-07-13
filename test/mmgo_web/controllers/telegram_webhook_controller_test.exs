defmodule MMGOWeb.TelegramWebhookControllerTest do
  use MMGOWeb.ConnCase, async: false

  alias MMGO.Accounts.Account
  alias MMGO.Repo
  alias MMGO.Telegram
  alias MMGO.Worlds

  setup do
    original_telegram_config = Application.get_env(:mmgo, Telegram)

    on_exit(fn ->
      Application.put_env(:mmgo, Telegram, original_telegram_config)
    end)

    {:ok, _realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    :ok
  end

  test "POST /api/telegram/webhook accepts a valid Telegram update", %{conn: conn} do
    update = %{
      "update_id" => 10,
      "message" => %{
        "message_id" => 20,
        "from" => %{
          "id" => 3003,
          "username" => "towerwalker",
          "first_name" => "Tower"
        }
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-telegram-bot-api-secret-token", "test-webhook-secret")
      |> post(~p"/api/telegram/webhook", update)

    assert json_response(conn, 200) == %{"ok" => true}
    assert Repo.aggregate(Account, :count, :id) == 1
  end

  test "POST /api/telegram/webhook rejects invalid secrets", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-telegram-bot-api-secret-token", "wrong-secret")
      |> post(~p"/api/telegram/webhook", %{"update_id" => 99})

    assert json_response(conn, 401) == %{"ok" => false, "error" => "unauthorized"}
  end

  test "POST /api/telegram/webhook rejects a missing secret in production-style config", %{
    conn: conn
  } do
    Application.put_env(:mmgo, Telegram,
      api_base_url: "http://localhost:8081",
      bot_token: "test-bot-token",
      webhook_secret: nil,
      allow_insecure_webhook?: false
    )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/telegram/webhook", %{"update_id" => 100})

    assert json_response(conn, 401) == %{"ok" => false, "error" => "unauthorized"}
  end
end
