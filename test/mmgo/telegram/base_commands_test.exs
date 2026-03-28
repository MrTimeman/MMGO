defmodule MMGO.Telegram.BaseCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
  alias MMGO.Worlds

  setup do
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

    {:ok, _wilderness} =
      Worlds.create_location(realm, %{
        slug: "wild-post",
        name: "Wild Post",
        kind: :wilderness,
        x: 50,
        y: 50,
        safe_zone: false
      })

    character = character_fixture(realm, city, "basebot", "Base Bot")

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "bot_base_ore",
        name: "Bot Base Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, ore_item} = Inventory.grant_item(character, ore_template, %{quantity: 3})

    %{character: character, city: city, ore_item: ore_item}
  end

  test "/base commands create, inspect, and use storage", %{
    character: character,
    ore_item: ore_item
  } do
    assert {:ok, buy_text} =
             Commands.process_message(character, %{"text" => "/base buy capital-city"})

    assert buy_text =~ "Base purchased"

    [base] = Bases.list_bases_for_character(character.id)

    assert {:ok, status_text} = Commands.process_message(character, %{"text" => "/base status"})
    assert status_text =~ base.name

    assert {:ok, deposit_text} =
             Commands.process_message(character, %{
               "text" => "/base deposit #{base.id} #{ore_item.id} 2"
             })

    assert deposit_text =~ "Deposited"

    [storage_item] = Bases.list_storage_items(base.id)

    assert {:ok, storage_text} =
             Commands.process_message(character, %{"text" => "/base storage #{base.id}"})

    assert storage_text =~ "Bot Base Ore"

    assert {:ok, withdraw_text} =
             Commands.process_message(character, %{
               "text" => "/base withdraw #{base.id} #{storage_item.id} 1"
             })

    assert withdraw_text =~ "Withdrew"
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
