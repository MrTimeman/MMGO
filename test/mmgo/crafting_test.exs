defmodule MMGO.CraftingTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Specialization
  alias MMGO.Crafting
  alias MMGO.Crafting.{CompleteCraftJobWorker, CraftJob}
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 50,
        y: 50,
        safe_zone: false
      })

    crafter = character_fixture(realm, tower, "crafter", "Crafter")
    novice = character_fixture(realm, tower, "novice-mastery", "Novice Mastery")

    specialize_mastery(crafter)

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "craft_ore",
        name: "Craft Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, wood_template} =
      Inventory.create_item_template(%{
        code: "craft_wood",
        name: "Craft Wood",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "tower_sword",
        name: "Tower Sword",
        item_type: :weapon,
        stackable: false,
        weight: 4,
        max_durability: 12,
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

    {:ok, _ore} = Inventory.grant_item(crafter, ore_template, %{quantity: 4})
    {:ok, _wood} = Inventory.grant_item(crafter, wood_template, %{quantity: 3})

    {:ok, workshop} =
      Crafting.create_workshop(crafter, %{
        name: "Tower Forge",
        location_id: tower.id,
        installed_tool_codes: ["forge", "anvil"]
      })

    {:ok, recipe} =
      Crafting.create_recipe(%{
        code: "tower_sword",
        name: "Tower Sword",
        result_item_template_id: sword_template.id,
        craft_time_game_days: 3,
        difficulty: 4,
        required_tool_codes: ["forge"],
        result_quantity: 1,
        result_durability: 12,
        requirements: [
          %{item_template_id: ore_template.id, quantity: 2},
          %{item_template_id: wood_template.id, quantity: 1}
        ]
      })

    %{
      crafter: crafter,
      novice: novice,
      ore_template: ore_template,
      wood_template: wood_template,
      sword_template: sword_template,
      workshop: workshop,
      recipe: recipe
    }
  end

  test "craft/5 consumes materials, creates active jobs, and schedules completion", %{
    crafter: crafter,
    workshop: workshop,
    recipe: recipe,
    ore_template: ore_template,
    wood_template: wood_template
  } do
    assert {:ok, %{craft_job: craft_job, worker_job: worker_job}} =
             Crafting.craft(crafter, workshop, recipe, 1, started_at: ~U[2026-03-28 12:00:00Z])

    assert craft_job.status == :active
    assert craft_job.quantity == 1
    assert worker_job.args == %{"craft_job_id" => craft_job.id}

    ore_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: crafter.id,
        item_template_id: ore_template.id
      )

    wood_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: crafter.id,
        item_template_id: wood_template.id
      )

    assert ore_stack.quantity == 2
    assert wood_stack.quantity == 2
  end

  test "complete_craft_job_by_id/2 grants crafted output with durability and XP", %{
    crafter: crafter,
    workshop: workshop,
    recipe: recipe,
    sword_template: sword_template
  } do
    {:ok, %{craft_job: craft_job}} =
      Crafting.craft(crafter, workshop, recipe, 1, started_at: ~U[2026-03-28 12:00:00Z])

    assert {:ok, %{craft_job: completed_job, character: updated_character}} =
             Crafting.complete_craft_job_by_id(craft_job.id, force: true)

    assert completed_job.status == :completed
    assert completed_job.yielded_quantity == 1
    assert updated_character.xp == 12

    crafted_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: crafter.id,
        item_template_id: sword_template.id
      )

    assert crafted_item.quantity == 1
    assert crafted_item.durability == 12
  end

  test "craft/5 rejects characters without mastery specialization", %{
    novice: novice,
    workshop: workshop,
    recipe: recipe
  } do
    {:ok, workshop} = Crafting.update_workshop(workshop, %{owner_character_id: novice.id})

    assert {:error, changeset} = Crafting.craft(novice, workshop, recipe, 1)
    assert %{status: ["character must be specialized in mastery"]} = errors_on(changeset)
  end

  test "craft/5 rejects workshops missing required tools", %{
    crafter: crafter,
    workshop: workshop,
    recipe: recipe
  } do
    {:ok, workshop} = Crafting.update_workshop(workshop, %{installed_tool_codes: ["anvil"]})

    assert {:error, changeset} = Crafting.craft(crafter, workshop, recipe, 1)
    assert %{status: ["workshop lacks required crafting tools"]} = errors_on(changeset)
  end

  test "worker completes due craft jobs", %{crafter: crafter, workshop: workshop, recipe: recipe} do
    {:ok, %{craft_job: craft_job}} =
      Crafting.craft(crafter, workshop, recipe, 1, started_at: ~U[2026-03-28 12:00:00Z])

    assert :ok =
             CompleteCraftJobWorker.perform(%Oban.Job{args: %{"craft_job_id" => craft_job.id}})

    updated_craft_job = Repo.get!(CraftJob, craft_job.id)
    assert updated_craft_job.status == :completed
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

  defp specialize_mastery(character) do
    %Specialization{}
    |> Specialization.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      track: :mastery,
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
