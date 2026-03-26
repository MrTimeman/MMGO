defmodule MMGO.Telegram.ClientTest do
  use ExUnit.Case, async: false

  alias MMGO.Telegram.Client

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, MMGO.Telegram)

    Application.put_env(:mmgo, MMGO.Telegram,
      api_base_url: "http://localhost:#{bypass.port}",
      bot_token: "test-bot-token",
      webhook_secret: "test-webhook-secret"
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.Telegram, original)
      else
        Application.delete_env(:mmgo, MMGO.Telegram)
      end
    end)

    %{bypass: bypass}
  end

  test "get_me/0 hits the Telegram Bot API", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/bottest-bot-token/getMe", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"id":42,"username":"mmgo_bot"}}))
    end)

    assert {:ok, %{"id" => 42, "username" => "mmgo_bot"}} = Client.get_me()
  end

  test "set_webhook/1 sends the configured webhook secret", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/setWebhook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "https://mmgo.test/api/telegram/webhook"
      assert body =~ "test-webhook-secret"

      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    assert {:ok, true} = Client.set_webhook("https://mmgo.test/api/telegram/webhook")
  end

  test "missing bot token returns an error" do
    original = Application.get_env(:mmgo, MMGO.Telegram)

    Application.put_env(:mmgo, MMGO.Telegram,
      api_base_url: "https://api.telegram.org",
      bot_token: nil
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.Telegram, original)
      else
        Application.delete_env(:mmgo, MMGO.Telegram)
      end
    end)

    assert {:error, :missing_bot_token} = Client.get_me()
  end
end
