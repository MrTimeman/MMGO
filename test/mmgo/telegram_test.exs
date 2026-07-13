defmodule MMGO.TelegramTest do
  use ExUnit.Case, async: false

  alias MMGO.Telegram

  setup do
    original = Application.get_env(:mmgo, MMGO.Telegram)

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.Telegram, original)
      else
        Application.delete_env(:mmgo, MMGO.Telegram)
      end
    end)

    :ok
  end

  test "rejects a missing webhook secret unless insecure mode is explicit" do
    Application.put_env(:mmgo, MMGO.Telegram,
      webhook_secret: nil,
      allow_insecure_webhook?: false
    )

    refute Telegram.authorized_webhook_secret?(nil)

    Application.put_env(:mmgo, MMGO.Telegram,
      webhook_secret: nil,
      allow_insecure_webhook?: true
    )

    assert Telegram.authorized_webhook_secret?(nil)
  end

  test "compares configured webhook secrets safely" do
    Application.put_env(:mmgo, MMGO.Telegram,
      webhook_secret: "test-webhook-secret",
      allow_insecure_webhook?: false
    )

    assert Telegram.authorized_webhook_secret?("test-webhook-secret")
    refute Telegram.authorized_webhook_secret?("wrong-secret")
    refute Telegram.authorized_webhook_secret?(nil)
  end
end
