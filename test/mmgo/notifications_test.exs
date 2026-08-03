defmodule MMGO.NotificationsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Notifications
  alias MMGO.Notifications.DeliveryWorker
  alias MMGO.Notifications.Formatter
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

    %{bypass: bypass, realm: realm, character: character}
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

  test "domain notifications create an in-app record even without a Telegram identity", %{
    realm: realm
  } do
    character = character_without_identity_fixture(realm, "in-app-only", "In App Only")

    assert {:ok, %Notification{} = notification} =
             Notifications.notify_journey_arrived(character, %{
               id: "in-app-journey",
               to_location_id: "city-gate",
               status: :arrived
             })

    assert notification.channel == :in_app
    assert notification.status == :sent
    assert notification.delivered_at
    assert Repo.aggregate(Notification, :count, :id) == 1
    assert Repo.aggregate(Oban.Job, :count, :id) == 0
  end

  test "domain notifications retain a Telegram delivery outbox alongside the in-app record", %{
    character: character
  } do
    assert {:ok, %Notification{channel: :in_app}} =
             Notifications.notify_journey_arrived(character, %{
               id: "dual-channel-journey",
               to_location_id: "city-gate",
               status: :arrived
             })

    assert Notifications.list_notifications(character.id)
           |> Enum.map(& &1.channel)
           |> Enum.sort() == [:in_app, :telegram]

    assert Repo.aggregate(Oban.Job, :count, :id) == 1
  end

  test "mail archive can mark everything read and clears only terminal records", %{
    character: character
  } do
    assert {:ok, %Notification{channel: :in_app}} =
             Notifications.notify_journey_arrived(character, %{
               id: "archive-journey",
               to_location_id: "city-gate",
               status: :arrived
             })

    assert [%Notification{channel: :in_app}] =
             Notifications.list_unread_notifications(character.id)

    assert {:ok, 2} = Notifications.mark_all_read(character.id)
    assert Notifications.list_unread_notifications(character.id) == []
    assert {:ok, 1} = Notifications.delete_read_notifications(character.id)

    assert [%Notification{channel: :telegram, status: :pending, read_at: read_at}] =
             Notifications.list_notifications(character.id)

    assert read_at
  end

  test "deliver_notification_by_id/1 sends a Telegram message and marks notification sent", %{
    bypass: bypass,
    character: character
  } do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "Путешествие"
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

  test "delivery worker retries transient Telegram failures before marking notification failed",
       %{
         bypass: bypass,
         character: character
       } do
    Bypass.stub(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      Plug.Conn.resp(conn, 500, ~s({"ok":false,"description":"temporary outage"}))
    end)

    {:ok, notification} =
      Notifications.enqueue(character, :journey_arrived, %{"to_location_id" => "555001"},
        dedupe_key: "journey:3"
      )

    assert {:error, {:telegram_api, 500, _body}} =
             DeliveryWorker.perform(%Oban.Job{
               args: %{"notification_id" => notification.id},
               attempt: 1,
               max_attempts: 5
             })

    assert Repo.get!(Notification, notification.id).status == :pending

    assert {:discard, :delivery_failed} =
             DeliveryWorker.perform(%Oban.Job{
               args: %{"notification_id" => notification.id},
               attempt: 5,
               max_attempts: 5
             })

    assert Repo.get!(Notification, notification.id).status == :failed
  end

  test "academy formatter does not describe a failed capstone as graduation" do
    assert {:ok, %{text: text}} =
             Formatter.render(%Notification{
               kind: "academy_completed",
               payload: %{
                 "program_type" => "academy_core",
                 "track" => "wizardry",
                 "status" => "failed",
                 "outcome_tier" => "capstone_incomplete"
               }
             })

    assert text =~ "без выпуска"
    assert text =~ "итоговое испытание не пройдено"
  end

  test "contact request creates durable in-app and Telegram notifications without a username", %{
    realm: realm
  } do
    requester =
      character_fixture(realm, "requester-secret-handle", "Requesting Traveler", 555_101)

    target = character_fixture(realm, "contact-target", "Contact Target", 555_102)
    encounter = %{id: Ecto.UUID.generate()}

    assert {:ok, %Notification{channel: :in_app}} =
             Notifications.notify_overworld_contact_request(target, encounter, requester)

    notifications = Notifications.list_notifications(target.id)
    assert Enum.map(notifications, & &1.channel) |> Enum.sort() == [:in_app, :telegram]

    assert Enum.all?(notifications, fn notification ->
             notification.kind == "overworld_contact_request" and
               notification.payload["encounter_id"] == encounter.id and
               notification.payload["requester_name"] == requester.name and
               not Map.has_key?(notification.payload, "telegram_username") and
               not String.contains?(inspect(notification.payload), "requester-secret-handle")
           end)
  end

  test "accepted contact notification uses the canonical current Telegram username", %{
    realm: realm
  } do
    recipient = character_fixture(realm, "contact-recipient", "Contact Recipient", 555_201)
    counterpart = character_fixture(realm, "old-contact-name", "Other Traveler", 555_202)

    Account
    |> Repo.get!(counterpart.account_id)
    |> Account.registration_changeset(%{
      settings: %{"telegram_username" => "stale-settings-name"}
    })
    |> Repo.update!()

    TelegramIdentity
    |> Repo.get_by!(account_id: counterpart.account_id)
    |> TelegramIdentity.changeset(%{
      telegram_user_id: 555_202,
      telegram_username: "current_contact_name",
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.update!()

    encounter = %{id: Ecto.UUID.generate()}

    assert {:ok, %Notification{channel: :in_app, payload: payload}} =
             Notifications.notify_overworld_contact_accepted(
               recipient,
               encounter,
               counterpart
             )

    assert payload["telegram_username"] == "current_contact_name"
    refute inspect(payload) =~ "stale-settings-name"
  end

  test "accepted contact notification does not substitute an ID when a public username is missing",
       %{
         realm: realm
       } do
    recipient = character_fixture(realm, "named-recipient", "Named Recipient", 555_251)
    counterpart = character_fixture(realm, "removed-name", "Private Traveler", 555_252)

    TelegramIdentity
    |> Repo.get_by!(account_id: counterpart.account_id)
    |> TelegramIdentity.changeset(%{
      telegram_user_id: 555_252,
      telegram_username: nil,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.update!()

    assert {:ok, %Notification{payload: payload}} =
             Notifications.notify_overworld_contact_accepted(
               recipient,
               %{id: Ecto.UUID.generate()},
               counterpart
             )

    assert is_nil(payload["telegram_username"])
    refute inspect(payload) =~ "555252"
  end

  test "rejected contact notification never stores the counterpart username", %{realm: realm} do
    requester = character_fixture(realm, "rejected-requester", "Rejected Requester", 555_301)
    counterpart = character_fixture(realm, "private-counterpart", "Private Traveler", 555_302)
    encounter = %{id: Ecto.UUID.generate()}

    assert {:ok, %Notification{payload: payload}} =
             Notifications.notify_overworld_contact_rejected(
               requester,
               encounter,
               counterpart
             )

    refute Map.has_key?(payload, "telegram_username")
    refute inspect(payload) =~ "private-counterpart"
  end

  test "contact notification formatter supplies consent callbacks and reveals usernames only after acceptance" do
    encounter_id = Ecto.UUID.generate()

    assert {:ok, %{text: request_text, opts: request_opts}} =
             Formatter.render(%Notification{
               kind: "overworld_contact_request",
               payload: %{
                 "encounter_id" => encounter_id,
                 "requester_name" => "Странник"
               }
             })

    refute request_text =~ "@someone"

    assert %{inline_keyboard: [buttons]} = request_opts[:reply_markup]
    assert Enum.any?(buttons, &(&1.callback_data == "road:accept:#{encounter_id}"))
    assert Enum.any?(buttons, &(&1.callback_data == "road:reject:#{encounter_id}"))

    assert {:ok, %{text: accepted_text, opts: []}} =
             Formatter.render(%Notification{
               kind: "overworld_contact_accepted",
               payload: %{
                 "counterpart_name" => "Странник",
                 "telegram_username" => "someone"
               }
             })

    assert accepted_text =~ "@someone"

    assert {:ok, %{text: rejected_text, opts: []}} =
             Formatter.render(%Notification{
               kind: "overworld_contact_rejected",
               payload: %{"counterpart_name" => "Странник"}
             })

    refute rejected_text =~ "@someone"
    assert rejected_text =~ "не были раскрыты"
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

  defp character_without_identity_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5})
    |> Repo.insert!()
  end
end
