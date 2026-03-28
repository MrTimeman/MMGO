defmodule MMGO.BasesTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Bases.{Base, CompleteBaseBuildWorker}
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Spells
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

    {:ok, wilderness} =
      Worlds.create_location(realm, %{
        slug: "wild-post",
        name: "Wild Post",
        kind: :wilderness,
        x: 50,
        y: 50,
        safe_zone: false
      })

    character = character_fixture(realm, city, "baser", "Baser")

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "base_ore",
        name: "Base Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "base_sword",
        name: "Base Sword",
        item_type: :weapon,
        stackable: false,
        weight: 4,
        max_durability: 10,
        nutrition_units: 0,
        actions: [
          %{
            key: "strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 1,
            effects: [
              %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
            ]
          }
        ]
      })

    {:ok, ore_item} = Inventory.grant_item(character, ore_template, %{quantity: 5})
    {:ok, sword_item} = Inventory.grant_item(character, sword_template)

    spell =
      spell_fixture(character, %{
        name: "Base Spell",
        formula: "Ignis Minor",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
      })

    _grimoire = grimoire_fixture(character, spell, "Travel Grimoire", 7)

    %{
      character: character,
      city: city,
      wilderness: wilderness,
      ore_item: ore_item,
      sword_item: sword_item
    }
  end

  test "purchase_city_base/3 creates an active city base", %{character: character, city: city} do
    assert {:ok, %Base{} = base} = Bases.purchase_city_base(character, city)
    assert base.status == :active
    assert base.kind == :city_purchase
  end

  test "start_custom_base_build/4 schedules base construction and completion", %{
    character: character,
    wilderness: wilderness
  } do
    assert {:ok, %{base: base, worker_job: worker_job}} =
             Bases.start_custom_base_build(character, wilderness, %{}, build_days: 1)

    assert base.status == :building
    assert worker_job.args == %{"base_id" => base.id}

    assert :ok = CompleteBaseBuildWorker.perform(%Oban.Job{args: %{"base_id" => base.id}})

    updated_base = Bases.get_base!(base.id)
    assert updated_base.status == :active
  end

  test "deposit and withdraw move stackable and non-stackable items between inventory and storage",
       %{character: character, city: city, ore_item: ore_item, sword_item: sword_item} do
    {:ok, base} = Bases.purchase_city_base(character, city)

    assert {:ok, %{storage_item: ore_storage}} = Bases.deposit_item(character, base, ore_item, 3)
    assert ore_storage.quantity == 3

    updated_ore_item = Inventory.get_inventory_item!(ore_item.id)
    assert updated_ore_item.quantity == 2

    assert {:ok, %{storage_item: sword_storage}} =
             Bases.deposit_item(character, base, sword_item, 1)

    assert sword_storage.quantity == 1

    refute Repo.get(Inventory.InventoryItem, sword_item.id)

    assert {:ok, %{inventory_item: ore_back}} =
             Bases.withdraw_item(character, base, ore_storage, 2)

    assert ore_back.quantity >= 4

    assert {:ok, %{inventory_item: sword_back}} =
             Bases.withdraw_item(character, base, sword_storage, 1)

    assert sword_back.character_id == character.id
    assert sword_back.durability == 10
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

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name, weight) do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: weight})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
