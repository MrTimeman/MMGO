defmodule MMGO.Telegram.UpdateHandlerTest do
  use MMGO.DataCase, async: false

  alias MMGO.Telegram.UpdateHandler
  alias MMGO.Worlds

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, MMGO.Telegram)

    Application.put_env(:mmgo, MMGO.Telegram,
      api_base_url: "http://localhost:#{bypass.port}",
      bot_token: "test-bot-token",
      webhook_secret: "test-webhook-secret",
      webhook_path: "/api/telegram/webhook"
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.Telegram, original)
      else
        Application.delete_env(:mmgo, MMGO.Telegram)
      end
    end)

    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    %{bypass: bypass, city: city}
  end

  test "command messages trigger Telegram sendMessage delivery", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "Welcome to MMGO"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":1}}))
    end)

    update = %{
      "update_id" => 1,
      "message" => %{
        "message_id" => 1,
        "chat" => %{"id" => 777_001},
        "text" => "/start",
        "from" => %{
          "id" => 777_001,
          "username" => "wizard",
          "first_name" => "Wizard"
        }
      }
    }

    assert {:ok, %{handled: true, type: "message"}} = UpdateHandler.handle(update)
  end
end
