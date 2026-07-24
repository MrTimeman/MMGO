defmodule MMGO.EventsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Events
  alias MMGO.Events.Option
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "tower",
        name: "Tower",
        kind: :tower,
        x: 20,
        y: 20,
        safe_zone: false
      })

    {:ok, dungeon_entrance} =
      Worlds.create_location(realm, %{
        slug: "depths",
        name: "Depths",
        kind: :dungeon_entrance,
        x: 30,
        y: 30,
        safe_zone: false
      })

    character = character_fixture(realm, city, "eventer", "Eventer")
    fund_base_acquisition!(realm, character)

    %{
      realm: realm,
      city: city,
      tower: tower,
      dungeon_entrance: dungeon_entrance,
      character: character
    }
  end

  test "current_event/1 creates a city arrival event and resolves options", %{
    character: character
  } do
    event = Events.current_event(character)
    assert event.template.code == "city_arrival"

    assert {:ok, %{instance: updated_instance, option: option}} =
             Events.resolve_option(event, "shops")

    assert updated_instance.status == :resolved
    assert option.action_key == "npc_shops"
  end

  test "current_event/1 returns base arrival when character is at their base", %{
    character: character,
    city: city
  } do
    {:ok, _base} = Bases.purchase_city_base(character, city)
    event = Events.current_event(character)
    assert event.template.code == "base_arrival"
  end

  test "current_event/1 returns tower arrival at the tower", %{character: character, tower: tower} do
    character =
      character |> Character.travel_changeset(%{current_location_id: tower.id}) |> Repo.update!()

    event = Events.current_event(character)
    assert event.template.code == "tower_arrival"
  end

  test "current_event/1 returns a dungeon entrance event", %{
    character: character,
    dungeon_entrance: dungeon_entrance
  } do
    character =
      character
      |> Character.travel_changeset(%{current_location_id: dungeon_entrance.id})
      |> Repo.update!()

    event = Events.current_event(character)

    assert event.template.code == "dungeon_arrival"
    assert Enum.any?(event.template.options, &(&1.code == "dungeon"))
  end

  test "current_event/1 resolves a stale arrival before creating the new location event", %{
    character: character,
    tower: tower
  } do
    city_event = Events.current_event(character)

    character =
      character |> Character.travel_changeset(%{current_location_id: tower.id}) |> Repo.update!()

    tower_event = Events.current_event(character)

    assert tower_event.template.code == "tower_arrival"
    assert Events.get_instance(city_event.id).status == :resolved
    assert Events.get_instance(city_event.id).selected_option_code == "departed"
  end

  test "refreshes only exact stale seeded arrival copy", %{realm: realm} do
    Events.ensure_defaults_for_realm(realm.id)

    shops = Repo.get_by!(Option, code: "shops")

    shops
    |> Option.changeset(%{result_text: "Торговая книга этой локации ещё готовится."})
    |> Repo.update!()

    Events.ensure_defaults_for_realm(realm.id)

    assert Repo.get!(Option, shops.id).result_text ==
             "Торговая книга открыта: сравните предложения и выставьте свой товар."

    shops.id
    |> then(&Repo.get!(Option, &1))
    |> Option.changeset(%{result_text: "Собственный текст торговой гильдии."})
    |> Repo.update!()

    Events.ensure_defaults_for_realm(realm.id)

    assert Repo.get!(Option, shops.id).result_text == "Собственный текст торговой гильдии."
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
