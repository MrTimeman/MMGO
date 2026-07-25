defmodule MMGO.Telegram.ReleaseAnnouncementsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Telegram
  alias MMGO.Telegram.ReleaseAnnouncements

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, Telegram)

    Application.put_env(:mmgo, Telegram,
      api_base_url: "http://localhost:#{bypass.port}",
      bot_token: "test-bot-token",
      webhook_secret: "test-webhook-secret",
      release_admin_user_id: 1_265_881_543
    )

    on_exit(fn -> Application.put_env(:mmgo, Telegram, original) end)

    %{bypass: bypass}
  end

  test "the configured administrator can select the current chat" do
    message = %{
      "text" => "/updates_here",
      "from" => %{"id" => 1_265_881_543},
      "chat" => %{"id" => -1_001_234_567_890, "title" => "MMGO Alpha"}
    }

    assert {:ok, response} = ReleaseAnnouncements.process_message(message)
    assert response =~ "-1001234567890"

    channel = ReleaseAnnouncements.current_channel()
    assert channel.chat_id == -1_001_234_567_890
    assert channel.chat_title == "MMGO Alpha"
    assert channel.configured_by_telegram_user_id == 1_265_881_543
  end

  test "the administrator can replace the destination with an explicit chat id" do
    message = %{
      "text" => "/updates_chat -1009876543210",
      "from" => %{"id" => 1_265_881_543},
      "chat" => %{"id" => 1_265_881_543}
    }

    assert {:ok, response} = ReleaseAnnouncements.process_message(message)
    assert response =~ "-1009876543210"
    assert ReleaseAnnouncements.current_channel().chat_id == -1_009_876_543_210
  end

  test "another Telegram user cannot change the destination" do
    message = %{
      "text" => "/updates_here",
      "from" => %{"id" => 42},
      "chat" => %{"id" => -100_000}
    }

    assert {:ok, "Эта команда доступна только владельцу MMGO."} =
             ReleaseAnnouncements.process_message(message)

    assert is_nil(ReleaseAnnouncements.current_channel())
  end

  test "release delivery uses the durable destination", %{bypass: bypass} do
    message = %{
      "text" => "/updates_here",
      "from" => %{"id" => 1_265_881_543},
      "chat" => %{"id" => -1_001_234_567_890}
    }

    assert {:ok, _response} = ReleaseAnnouncements.process_message(message)

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["chat_id"] == -1_001_234_567_890
      assert payload["text"] =~ "Обновление закрытой альфы MMGO"
      assert payload["text"] =~ "Версия 0.1.0-alpha.4"
      assert payload["text"] =~ "Путешествия снова работают"
      refute payload["text"] =~ "Коммит"
      refute payload["text"] =~ "https://"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":7}}))
    end)

    assert {:ok, %{"message_id" => 7}} =
             ReleaseAnnouncements.announce_release(
               "0.1.0-alpha.4",
               "Путешествия снова работают, а карта стала спокойнее."
             )
  end

  test "release delivery requires a useful bounded description" do
    assert {:error, :empty_release_description} =
             ReleaseAnnouncements.announce_release("0.1.0-alpha.4", "  ")

    assert {:error, :release_description_too_long} =
             ReleaseAnnouncements.announce_release("0.1.0-alpha.4", String.duplicate("а", 3_001))
  end
end
