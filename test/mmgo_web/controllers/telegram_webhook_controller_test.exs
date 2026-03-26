defmodule MMGOWeb.TelegramWebhookControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts.Account
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
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
end
