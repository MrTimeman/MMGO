defmodule MMGO.Telegram.UpdateHandlerTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Notifications
  alias MMGO.Overworld
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Telegram.UpdateHandler
  alias MMGO.Telegram.ReleaseAnnouncements
  alias MMGO.Worlds

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, MMGO.Telegram)

    Application.put_env(:mmgo, MMGO.Telegram,
      api_base_url: "http://localhost:#{bypass.port}",
      bot_token: "test-bot-token",
      webhook_secret: "test-webhook-secret",
      webhook_path: "/api/telegram/webhook",
      mini_app_url: "https://mmgo.test/play"
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

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 30,
        y: 30,
        safe_zone: false
      })

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    %{bypass: bypass, realm: realm, city: city, tower: tower}
  end

  test "/start opens mode choice without provisioning the MMO character", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "выберите путь"
      assert body =~ "https://mmgo.test/play"
      assert body =~ "web_app"
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

    account = Accounts.get_account_by_telegram_user_id(777_001)
    [character] = Accounts.list_characters_for_account(account.id)
    assert character.status == :new
    assert character.current_location_id == nil
    assert Inventory.list_inventory_for_character(character.id) == []
    assert Spells.list_spells_for_character(character.id) == []
    assert Grimoires.active_grimoire_for_character(character.id) == nil
  end

  test "/help remains safe before mode selection", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "Сначала выберите режим"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":8}}))
    end)

    update = %{
      "update_id" => 8,
      "message" => %{
        "message_id" => 8,
        "chat" => %{"id" => 777_008},
        "text" => "/help",
        "from" => %{
          "id" => 777_008,
          "username" => "newcomer",
          "first_name" => "Newcomer"
        }
      }
    }

    assert {:ok, %{handled: true, type: "message"}} = UpdateHandler.handle(update)

    account = Accounts.get_account_by_telegram_user_id(777_008)
    [character] = Accounts.list_characters_for_account(account.id)
    assert character.status == :new
    assert Inventory.list_inventory_for_character(character.id) == []
  end

  test "world commands remain available to an existing active world character", %{
    bypass: bypass,
    city: city
  } do
    _character = telegram_character_fixture(city, 777_009, "returning", "Returning")

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "· уровень"
      assert body =~ "Локация: Capital City"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":9}}))
    end)

    update = %{
      "update_id" => 9,
      "message" => %{
        "message_id" => 9,
        "chat" => %{"id" => 777_009},
        "text" => "/status",
        "from" => %{
          "id" => 777_009,
          "username" => "returning",
          "first_name" => "Returning"
        }
      }
    }

    assert {:ok, %{handled: true, type: "message"}} = UpdateHandler.handle(update)
  end

  test "later text commands resolve the persisted default instead of the provision result", %{
    bypass: bypass,
    city: city
  } do
    first = telegram_character_fixture(city, 777_011, "realm_hopper", "Realm Hopper")

    {:ok, second_realm} =
      Worlds.create_realm(%{slug: "telegram-second-realm", name: "Second Realm"})

    {:ok, second_city} =
      Worlds.create_location(second_realm, %{
        slug: "second-capital",
        name: "Second Capital",
        kind: :city,
        x: 40,
        y: 40,
        safe_zone: true
      })

    second =
      %Character{account_id: first.account_id, realm_id: second_realm.id}
      |> Character.changeset(%{name: "Chosen Wanderer", status: :active})
      |> Repo.insert!()
      |> Character.travel_changeset(%{current_location_id: second_city.id})
      |> Repo.update!()

    assert {:ok, _second} =
             Accounts.set_default_world_character(first.account_id, second.id)

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "Chosen Wanderer"
      assert body =~ "Локация: Second Capital"
      refute body =~ "Локация: Capital City"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":11}}))
    end)

    update = %{
      "update_id" => 11,
      "message" => %{
        "message_id" => 11,
        "chat" => %{"id" => 777_011},
        "text" => "/status",
        "from" => %{
          "id" => 777_011,
          "username" => "realm_hopper",
          "first_name" => "Realm Hopper"
        }
      }
    }

    assert {:ok, %{character_id: character_id, type: "message"}} = UpdateHandler.handle(update)
    assert character_id == second.id
  end

  test "callbacks cannot activate an unselected world profile", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/answerCallbackQuery", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "pre-mode-callback"
      assert body =~ "выберите режим"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    update = %{
      "update_id" => 10,
      "callback_query" => %{
        "id" => "pre-mode-callback",
        "data" => "road:accept:unavailable",
        "from" => %{
          "id" => 777_010,
          "username" => "callback_newcomer",
          "first_name" => "Callback Newcomer"
        }
      }
    }

    assert {:ok, %{callback_result: %{ok?: false}, type: "callback_query"}} =
             UpdateHandler.handle(update)

    account = Accounts.get_account_by_telegram_user_id(777_010)
    [character] = Accounts.list_characters_for_account(account.id)
    assert character.status == :new
    assert character.current_location_id == nil
    assert Inventory.list_inventory_for_character(character.id) == []
  end

  test "the release administrator can select an updates group through the webhook path", %{
    bypass: bypass
  } do
    Application.put_env(:mmgo, MMGO.Telegram,
      api_base_url: "http://localhost:#{bypass.port}",
      bot_token: "test-bot-token",
      webhook_secret: "test-webhook-secret",
      webhook_path: "/api/telegram/webhook",
      mini_app_url: "https://mmgo.test/play",
      release_admin_user_id: 1_265_881_543
    )

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "-1001234567890"
      assert body =~ "будет получать сообщения"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":{"message_id":2}}))
    end)

    update = %{
      "update_id" => 2,
      "message" => %{
        "message_id" => 2,
        "chat" => %{"id" => -1_001_234_567_890, "title" => "MMGO Updates"},
        "text" => "/updates_here",
        "from" => %{
          "id" => 1_265_881_543,
          "username" => "owner",
          "first_name" => "Owner"
        }
      }
    }

    assert {:ok, %{handled: true, type: "message"}} = UpdateHandler.handle(update)
    assert ReleaseAnnouncements.current_channel().chat_id == -1_001_234_567_890

    account = Accounts.get_account_by_telegram_user_id(1_265_881_543)
    characters = Accounts.list_characters_for_account(account.id)
    albert = Enum.find(characters, &(&1.name == "Альберт Латыпов"))
    tamiorn = Enum.find(characters, &(&1.name == "Тамиорн Найло"))
    assert albert.status == :frozen
    assert tamiorn.status == :new
  end

  test "a traveler can accept a contact request from its Telegram callback", %{
    bypass: bypass,
    city: city
  } do
    requester = telegram_character_fixture(city, 777_101, "callback_requester", "Проситель")
    target = telegram_character_fixture(city, 777_102, "callback_target", "Собеседник")

    assert {:ok, %{encounter: encounter}} =
             Play.request_traveler_contact(requester, target.id)

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/answerCallbackQuery", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "contact-accept-1"
      assert body =~ "Запрос принят"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    update = %{
      "update_id" => 3,
      "callback_query" => %{
        "id" => "contact-accept-1",
        "data" => "road:accept:#{encounter.id}",
        "from" => %{
          "id" => 777_102,
          "username" => "callback_target",
          "first_name" => "Собеседник"
        }
      }
    }

    assert {:ok,
            %{
              handled: true,
              type: "callback_query",
              callback_result: %{ok?: true}
            }} = UpdateHandler.handle(update)

    assert Overworld.get_encounter!(encounter.id).status == :greeted

    requester_contact =
      requester.id
      |> Notifications.list_notifications()
      |> Enum.find(&(&1.kind == "overworld_contact_accepted" and &1.channel == :telegram))

    assert requester_contact.payload["telegram_username"] == "callback_target"
  end

  test "a traveler can reject a contact request from its Telegram callback", %{
    bypass: bypass,
    city: city
  } do
    requester = telegram_character_fixture(city, 777_201, "reject_requester", "Проситель")
    target = telegram_character_fixture(city, 777_202, "reject_target", "Собеседник")

    assert {:ok, %{encounter: encounter}} =
             Play.request_traveler_contact(requester, target.id)

    Bypass.expect_once(bypass, "POST", "/bottest-bot-token/answerCallbackQuery", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "contact-reject-1"
      assert body =~ "Запрос отклонён"
      Plug.Conn.resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    update = %{
      "update_id" => 4,
      "callback_query" => %{
        "id" => "contact-reject-1",
        "data" => "road:reject:#{encounter.id}",
        "from" => %{
          "id" => 777_202,
          "username" => "reject_target",
          "first_name" => "Собеседник"
        }
      }
    }

    assert {:ok, %{callback_result: %{ok?: true}}} = UpdateHandler.handle(update)
    assert Overworld.get_encounter!(encounter.id).status == :avoided

    rejected_notification =
      requester.id
      |> Notifications.list_notifications()
      |> Enum.find(&(&1.kind == "overworld_contact_rejected"))

    refute Map.has_key?(rejected_notification.payload, "telegram_username")
  end

  defp telegram_character_fixture(city, telegram_user_id, username, first_name) do
    assert {:ok, %{character: character}} =
             Accounts.provision_from_telegram(%{
               "id" => telegram_user_id,
               "username" => username,
               "first_name" => first_name
             })

    character =
      character
      |> Character.changeset(%{status: :active})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: city.id})
      |> Repo.update!()

    assert {:ok, default_character} =
             Accounts.set_default_world_character(character.account_id, character.id)

    default_character
  end
end
