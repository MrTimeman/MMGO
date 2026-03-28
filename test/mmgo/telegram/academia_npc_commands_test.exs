defmodule MMGO.Telegram.AcademiaNpcCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.NPCShops
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    scholar = character_fixture(realm, city, "scholarbot", "Scholar Bot")
    vendor = character_fixture(realm, city, "vendorbot", "Vendor Bot")
    complete_academia_enrollment(scholar, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, scholar, 100)

    {:ok, potion_template} =
      Inventory.create_item_template(%{
        code: "shop_potion",
        name: "Shop Potion",
        item_type: :potion,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: [
          %{
            key: "throw",
            action_kind: :throw,
            targeting: :ally,
            quantity_cost: 1,
            effects: [
              %{
                applies_to: :target,
                state: "regenerating",
                intensity: 3,
                variance: 0,
                duration: 2
              }
            ]
          }
        ]
      })

    {:ok, ingredient_template} =
      Inventory.create_item_template(%{
        code: "shop_ingredient",
        name: "Shop Ingredient",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, seller_stack} = Inventory.grant_item(vendor, ingredient_template, %{quantity: 3})
    {:ok, shop} = NPCShops.create_shop(city, %{code: "general-store", name: "General Store"})

    {:ok, offer_buy} =
      NPCShops.add_offer(shop, %{
        item_template_id: potion_template.id,
        buy_price: 10,
        sell_price: 0,
        item_durability: 0
      })

    {:ok, offer_sell} =
      NPCShops.add_offer(shop, %{
        item_template_id: ingredient_template.id,
        buy_price: 0,
        sell_price: 4,
        item_durability: 0
      })

    %{
      scholar: scholar,
      vendor: vendor,
      offer_buy: offer_buy,
      offer_sell: offer_sell,
      seller_stack: seller_stack
    }
  end

  test "/academia and /npc commands exercise core flows", %{
    scholar: scholar,
    vendor: vendor,
    offer_buy: offer_buy,
    offer_sell: offer_sell,
    seller_stack: seller_stack
  } do
    assert {:ok, project_text} =
             Commands.process_message(scholar, %{"text" => "/academia start spell Fire Study"})

    assert project_text =~ "Research started"

    assert {:ok, projects_text} =
             Commands.process_message(scholar, %{"text" => "/academia projects"})

    assert projects_text =~ "Fire Study"

    assert {:ok, shops_text} = Commands.process_message(scholar, %{"text" => "/npc shops"})
    assert shops_text =~ "general-store"

    assert {:ok, browse_text} =
             Commands.process_message(scholar, %{"text" => "/npc browse general-store"})

    assert browse_text =~ "Shop Potion"

    assert {:ok, buy_text} =
             Commands.process_message(scholar, %{"text" => "/npc buy #{offer_buy.id} 1"})

    assert buy_text =~ "Bought"

    assert {:ok, tuition_text} =
             Commands.process_message(scholar, %{"text" => "/academy tuition 10"})

    assert tuition_text =~ "Paid academy tuition"

    assert {:ok, charity_text} =
             Commands.process_message(scholar, %{"text" => "/charity donate 10"})

    assert charity_text =~ "Donated 10"

    assert {:ok, sell_text} =
             Commands.process_message(vendor, %{
               "text" => "/npc sell #{offer_sell.id} #{seller_stack.id} 2"
             })

    assert sell_text =~ "Sold 2"
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

  defp complete_academia_enrollment(character, realm) do
    %MMGO.Academy.Enrollment{}
    |> MMGO.Academy.Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academia,
      status: :completed,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
