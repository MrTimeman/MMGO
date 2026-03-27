defmodule MMGO.NotificationsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Notifications
  alias MMGO.Notifications.Notification
  alias MMGO.Repo
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

    character = character_fixture(realm, "notifier", "Notifier", 555_001)

    %{bypass: bypass, character: character}
  end

  test "enqueue/4 stores a pending Telegram notification and schedules delivery", %{
    character: character
  } do
    assert {:ok, %Notification{} = notification} =
             Notifications.enqueue(character, :journey_arrived, %{"to_location_id" => "loc-1"},
               dedupe_key: "journey:1"
             )

    assert notification.channel == :telegram
    assert notification.status == :pending
    assert notification.metadata["telegram_chat_id"] == 555_001
    assert Repo.aggregate(Notification, :count, :id) == 1
    assert Repo.aggregate(Oban.Job, :count, :id) == 1
  end

  test "enqueue/4 rejects duplicate dedupe keys for the same character", %{character: character} do
    assert {:ok, _notification} =
             Notifications.enqueue(character, :journey_arrived, %{"to_location_id" => "loc-1"},
               dedupe_key: "journey:1"
             )

    assert {:error, changeset} =
             Notifications.enqueue(character, :journey_arrived, %{"to_location_id" => "loc-1"},
               dedupe_key: "journey:1"
             )

    assert %{status: ["notification has already been queued"]} = errors_on(changeset)
  end

  test "deliver_notification_by_id/1 sends a Telegram message and marks notification sent", %{
    bypass: bypass,
    character: character
  } do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "journey"
      assert body =~ "555001"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":1}}))
    end)

    {:ok, notification} =
      Notifications.enqueue(character, :journey_arrived, %{"to_location_id" => "555001"},
        dedupe_key: "journey:2"
      )

    assert {:ok, delivered_notification} =
             Notifications.deliver_notification_by_id(notification.id)

    assert delivered_notification.status == :sent
    assert delivered_notification.delivered_at
  end

  defp character_fixture(realm, handle, name, telegram_user_id) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %TelegramIdentity{account_id: account.id}
    |> TelegramIdentity.changeset(%{
      telegram_user_id: telegram_user_id,
      telegram_username: handle,
      first_name: name,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5})
    |> Repo.insert!()
  end
end
