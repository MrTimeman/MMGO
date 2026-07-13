defmodule MMGOWeb.TelegramAuthControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds

  @bot_token "test-bot-token"
  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    %{city: city}
  end

  test "POST /auth/telegram provisions a playable character and writes only scoped session ids",
       %{
         conn: conn,
         city: city
       } do
    conn =
      post(conn, ~p"/auth/telegram", %{"telegram_auth" => %{"init_data" => signed_init_data()}})

    assert redirected_to(conn) == ~p"/map"
    assert account_id = get_session(conn, :current_account_id)
    assert character_id = get_session(conn, :current_character_id)
    refute get_session(conn, :demo_character_id)
    refute get_session(conn, :demo_opponent_id)

    account = Accounts.get_account!(account_id)
    character = Accounts.get_character!(character_id) |> Repo.preload(:current_location)

    assert account.handle =~ ~r/^towerwalker-/
    assert character.account_id == account.id
    assert character.status == :active
    assert character.current_location_id == city.id
  end

  test "POST /auth/telegram reuses a verified identity instead of creating duplicates", %{
    conn: conn
  } do
    init_data = signed_init_data()

    first_conn = post(conn, ~p"/auth/telegram", %{"telegram_auth" => %{"init_data" => init_data}})

    second_conn =
      first_conn
      |> recycle()
      |> post(~p"/auth/telegram", %{"telegram_auth" => %{"init_data" => init_data}})

    assert get_session(first_conn, :current_account_id) ==
             get_session(second_conn, :current_account_id)

    assert get_session(first_conn, :current_character_id) ==
             get_session(second_conn, :current_character_id)
  end

  test "POST /auth/telegram rejects tampered init data without creating a player", %{conn: conn} do
    init_data = signed_init_data() |> String.replace("Tower", "Impostor")

    conn = post(conn, ~p"/auth/telegram", %{"telegram_auth" => %{"init_data" => init_data}})

    assert redirected_to(conn) == ~p"/play"
    refute get_session(conn, :current_account_id)
    refute get_session(conn, :current_character_id)
    assert Repo.aggregate(MMGO.Accounts.Account, :count, :id) == 0
    refute Repo.get_by(MMGO.Accounts.Account, handle: "demo-player-1")
  end

  defp signed_init_data do
    fields = %{
      "auth_date" => Integer.to_string(DateTime.utc_now() |> DateTime.to_unix()),
      "query_id" => "AAEAAA",
      "user" =>
        Jason.encode!(%{
          "id" => 101_001,
          "first_name" => "Tower",
          "username" => "towerwalker",
          "language_code" => "ru"
        })
    }

    secret_key = :crypto.mac(:hmac, :sha256, @bot_token, "WebAppData")

    hash =
      fields
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
      |> then(&:crypto.mac(:hmac, :sha256, secret_key, &1))
      |> Base.encode16(case: :lower)

    URI.encode_query(Map.put(fields, "hash", hash))
  end
end
