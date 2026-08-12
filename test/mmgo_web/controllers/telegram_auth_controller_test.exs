defmodule MMGOWeb.TelegramAuthControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Federation.{Migration, RemoteRealm}
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

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 1200,
        y: 800,
        safe_zone: false
      })

    %{city: city, tower: tower}
  end

  test "POST /auth/telegram opens mode choice without provisioning world starter systems",
       %{
         conn: conn
       } do
    conn =
      post(conn, ~p"/auth/telegram", %{"telegram_auth" => %{"init_data" => signed_init_data()}})

    assert redirected_to(conn) == ~p"/mode"
    assert account_id = get_session(conn, :current_account_id)
    assert character_id = get_session(conn, :current_character_id)
    refute get_session(conn, :demo_character_id)
    refute get_session(conn, :demo_opponent_id)

    account = Accounts.get_account!(account_id)
    character = Accounts.get_character!(character_id) |> Repo.preload(:current_location)

    assert account.handle =~ ~r/^towerwalker-/
    assert character.account_id == account.id
    assert character.status == :new
    assert character.current_location_id == nil
    assert get_session(conn, :game_mode) == nil
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

  test "special account is prepared and redirected to mode choice", %{
    conn: conn,
    tower: tower
  } do
    conn =
      post(conn, ~p"/auth/telegram", %{
        "telegram_auth" => %{"init_data" => signed_init_data(1_265_881_543)}
      })

    assert redirected_to(conn) == ~p"/mode"
    assert account_id = get_session(conn, :current_account_id)
    assert selected_id = get_session(conn, :current_character_id)

    characters = Accounts.list_characters_for_account(account_id)
    assert length(characters) == 2

    albert = Enum.find(characters, &(&1.name == "Альберт Латыпов"))
    tamiorn = Enum.find(characters, &(&1.name == "Тамиорн Найло"))

    assert albert.status == :frozen
    assert albert.current_location_id == tower.id
    assert tamiorn.status == :new
    assert selected_id == tamiorn.id
  end

  test "a local migration destination can continue through the dossier", %{
    conn: conn
  } do
    init_data = signed_init_data(404_001)
    first_conn = post(conn, ~p"/auth/telegram", %{"init_data" => init_data})
    account_id = get_session(first_conn, :current_account_id)
    origin = Accounts.get_character!(get_session(first_conn, :current_character_id))

    {:ok, destination_realm} =
      Worlds.create_realm(%{slug: "amber-march", name: "Янтарная марка"})

    {:ok, destination_location} =
      Worlds.create_location(destination_realm, %{
        slug: "arrival-gate",
        name: "Врата прибытия",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    origin = origin |> Character.changeset(%{status: :frozen}) |> Repo.update!()

    destination =
      %Character{account_id: account_id, realm_id: destination_realm.id}
      |> Character.changeset(%{name: "Путник Янтарной марки", status: :active})
      |> Repo.insert!()
      |> Character.travel_changeset(%{current_location_id: destination_location.id})
      |> Repo.update!()

    insert_migration!(origin, destination,
      destination_realm_id: destination_realm.id,
      mode: :local
    )

    auth_conn =
      first_conn
      |> recycle()
      |> post(~p"/auth/telegram", %{"init_data" => init_data})

    assert redirected_to(auth_conn) == ~p"/mode"
    assert get_session(auth_conn, :current_character_id) == destination.id

    dossier_conn = auth_conn |> recycle() |> get(~p"/characters")
    assert html_response(dossier_conn, 200) =~ ~s(id="select-character-#{destination.id}")

    continue_conn =
      dossier_conn
      |> recycle()
      |> post(~p"/characters/#{destination.id}/select")

    assert redirected_to(continue_conn) == ~p"/map"
    assert get_session(continue_conn, :current_character_id) == destination.id
    assert Accounts.get_character!(destination.id).status == :active
    assert Accounts.get_character!(origin.id).current_location_id == nil
  end

  test "a frozen remote migrant receives a migration session after fresh authentication", %{
    conn: conn
  } do
    init_data = signed_init_data(404_002)
    first_conn = post(conn, ~p"/auth/telegram", %{"init_data" => init_data})
    account_id = get_session(first_conn, :current_account_id)

    origin =
      get_session(first_conn, :current_character_id)
      |> Accounts.get_character!()
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()

    remote_realm =
      %RemoteRealm{}
      |> RemoteRealm.changeset(%{
        slug: "silver-sea-remote",
        name: "Серебряное море",
        status: :active,
        manifest_url: "https://silver.example/manifest",
        public_endpoint: "https://silver.example",
        currency_code: "SLV",
        allow_migration: true,
        population_hint: 12,
        ruleset_version: 1,
        ruleset: %{}
      })
      |> Repo.insert!()

    insert_migration!(origin, nil, remote_realm_id: remote_realm.id, mode: :remote)

    auth_conn =
      first_conn
      |> recycle()
      |> post(~p"/auth/telegram", %{"init_data" => init_data})

    assert redirected_to(auth_conn) == ~p"/mode"
    assert get_session(auth_conn, :current_account_id) == account_id
    assert get_session(auth_conn, :current_character_id) == origin.id

    realms_conn =
      auth_conn
      |> recycle()
      |> post(~p"/mode/world")
      |> recycle()
      |> get(~p"/realms")

    assert html_response(realms_conn, 200) =~ ~s(id="realms-screen")
  end

  defp insert_migration!(origin, destination, opts) do
    now = DateTime.utc_now()
    mode = Keyword.fetch!(opts, :mode)

    %Migration{}
    |> Migration.changeset(%{
      account_id: origin.account_id,
      mode: mode,
      status: :active,
      origin_realm_id: origin.realm_id,
      destination_realm_id: Keyword.get(opts, :destination_realm_id),
      remote_realm_id: Keyword.get(opts, :remote_realm_id),
      origin_character_id: origin.id,
      destination_character_id: destination && destination.id,
      destination_character_name: (destination && destination.name) || origin.name,
      currency_amount: 100,
      converted_currency_amount: 80,
      source_level: origin.level,
      destination_level: origin.level,
      source_xp: origin.xp,
      destination_xp: origin.xp,
      freeze_started_at: now,
      freeze_ends_at: DateTime.add(now, 86_400, :second),
      passive_xp_awarded: 0,
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp signed_init_data(user_id \\ 101_001) do
    fields = %{
      "auth_date" => Integer.to_string(DateTime.utc_now() |> DateTime.to_unix()),
      "query_id" => "AAEAAA",
      "user" =>
        Jason.encode!(%{
          "id" => user_id,
          "first_name" => "Tower",
          "username" => "towerwalker",
          "language_code" => "ru"
        })
    }

    secret_key = :crypto.mac(:hmac, :sha256, "WebAppData", @bot_token)

    hash =
      fields
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
      |> then(&:crypto.mac(:hmac, :sha256, secret_key, &1))
      |> Base.encode16(case: :lower)

    URI.encode_query(Map.put(fields, "hash", hash))
  end
end
