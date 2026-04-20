defmodule MMGO.AlchemyTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Specialization
  alias MMGO.Alchemy
  alias MMGO.Alchemy.{BrewJob, CompleteBrewJobWorker}
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

    alchemist = character_fixture(realm, tower, "alchemist", "Alchemist")
    novice = character_fixture(realm, tower, "novice", "Novice")

    specialize_alchemy(alchemist)

    {:ok, herb_template} =
      Inventory.create_item_template(%{
        code: "alch_herb",
        name: "Alchemy Herb",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, flask_template} =
      Inventory.create_item_template(%{
        code: "healing_draught",
        name: "Healing Draught",
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
                intensity: 4,
                variance: 0,
                duration: 2
              }
            ]
          }
        ]
      })

    {:ok, _ingredients} = Inventory.grant_item(alchemist, herb_template, %{quantity: 5})

    {:ok, workspace} =
      Alchemy.create_workshop(alchemist, %{
        name: "Tower Lab",
        location_id: tower.id,
        installed_tool_codes: ["cauldron", "retort"]
      })

    {:ok, recipe} =
      Alchemy.create_recipe(%{
        code: "healing_draught",
        name: "Healing Draught",
        result_item_template_id: flask_template.id,
        brew_time_game_days: 2,
        difficulty: 3,
        required_tool_codes: ["cauldron"],
        result_quantity: 1,
        requirements: [%{item_template_id: herb_template.id, quantity: 2}]
      })

    %{
      realm: realm,
      tower: tower,
      alchemist: alchemist,
      novice: novice,
      herb_template: herb_template,
      flask_template: flask_template,
      workspace: workspace,
      recipe: recipe
    }
  end

  test "brew/5 consumes ingredients, creates an active job, and schedules completion", %{
    alchemist: alchemist,
    workspace: workspace,
    recipe: recipe,
    herb_template: herb_template
  } do
    assert {:ok, %{brew_job: brew_job, worker_job: worker_job}} =
             Alchemy.brew(alchemist, workspace, recipe, 2, started_at: ~U[2026-03-28 12:00:00Z])

    assert brew_job.status == :active
    assert brew_job.quantity == 2
    assert worker_job.args == %{"brew_job_id" => brew_job.id}

    ingredient_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: alchemist.id,
        item_template_id: herb_template.id
      )

    assert ingredient_stack.quantity == 1
  end

  test "complete_brew_job_by_id/2 grants potion output and XP", %{
    alchemist: alchemist,
    workspace: workspace,
    recipe: recipe,
    flask_template: flask_template
  } do
    {:ok, %{brew_job: brew_job}} =
      Alchemy.brew(alchemist, workspace, recipe, 1, started_at: ~U[2026-03-28 12:00:00Z])

    assert {:ok, %{brew_job: completed_brew_job, character: updated_character}} =
             Alchemy.complete_brew_job_by_id(brew_job.id, force: true)

    assert completed_brew_job.status == :completed
    assert completed_brew_job.yielded_quantity == 1
    assert updated_character.xp == 6

    potion_stack =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: alchemist.id,
        item_template_id: flask_template.id
      )

    assert potion_stack.quantity == 1
  end

  test "brew/5 rejects characters without alchemy specialization", %{
    novice: novice,
    workspace: workspace,
    recipe: recipe
  } do
    workspace =
      workspace
      |> Alchemy.update_workshop(%{owner_character_id: novice.id})
      |> case do
        {:ok, workspace} -> workspace
        {:error, _changeset} -> workspace
      end

    assert {:error, changeset} = Alchemy.brew(novice, workspace, recipe, 1)
    assert %{status: ["character must be specialized in alchemy"]} = errors_on(changeset)
  end

  test "brew/5 rejects workspaces missing required tools", %{
    alchemist: alchemist,
    workspace: workspace,
    recipe: recipe
  } do
    {:ok, workspace} = Alchemy.update_workshop(workspace, %{installed_tool_codes: ["retort"]})

    assert {:error, changeset} = Alchemy.brew(alchemist, workspace, recipe, 1)
    assert %{status: ["workshop lacks required alchemy tools"]} = errors_on(changeset)
  end

  test "worker completes due brew jobs", %{
    alchemist: alchemist,
    workspace: workspace,
    recipe: recipe
  } do
    {:ok, %{brew_job: brew_job}} =
      Alchemy.brew(alchemist, workspace, recipe, 1, started_at: ~U[2026-03-28 12:00:00Z])

    assert :ok = CompleteBrewJobWorker.perform(%Oban.Job{args: %{"brew_job_id" => brew_job.id}})

    updated_brew_job = Repo.get!(BrewJob, brew_job.id)
    assert updated_brew_job.status == :completed
  end

  test "brew/5 matches ingredient requirements by qualities, not only exact template ids", %{
    alchemist: alchemist,
    workspace: workspace,
    flask_template: flask_template
  } do
    {:ok, ember_moss} =
      Inventory.create_item_template(%{
        code: "ember_moss_test",
        name: "Ember Moss",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        qualities: ["fire_catalyst", "volatile"],
        actions: []
      })

    {:ok, magma_shard} =
      Inventory.create_item_template(%{
        code: "magma_shard_test",
        name: "Magma Shard",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        qualities: ["fire_catalyst", "corrosive"],
        actions: []
      })

    {:ok, _ember_stack} = Inventory.grant_item(alchemist, ember_moss, %{quantity: 1})
    {:ok, _magma_stack} = Inventory.grant_item(alchemist, magma_shard, %{quantity: 1})

    {:ok, quality_recipe} =
      Alchemy.create_recipe(%{
        code: "caustic_fire_test",
        name: "Caustic Fire",
        result_item_template_id: flask_template.id,
        brew_time_game_days: 1,
        difficulty: 4,
        required_tool_codes: ["cauldron"],
        result_quantity: 1,
        requirements: [
          %{qualities: ["fire_catalyst"], quantity: 1},
          %{qualities: ["corrosive"], quantity: 1}
        ]
      })

    assert {:ok, %{brew_job: brew_job}} = Alchemy.brew(alchemist, workspace, quality_recipe, 1)

    consumed = brew_job.metadata["consumed_ingredients"]
    assert Enum.any?(consumed, &(&1["qualities"] == ["fire_catalyst"]))
    assert Enum.any?(consumed, &(&1["qualities"] == ["corrosive"]))

    refute Repo.get_by(Inventory.InventoryItem,
             character_id: alchemist.id,
             item_template_id: magma_shard.id
           )
  end

  test "brew/5 rejects quality-based recipes when no matching ingredient qualities are present",
       %{
         alchemist: alchemist,
         workspace: workspace,
         flask_template: flask_template
       } do
    {:ok, quality_recipe} =
      Alchemy.create_recipe(%{
        code: "luminous_tonic_test",
        name: "Luminous Tonic",
        result_item_template_id: flask_template.id,
        brew_time_game_days: 1,
        difficulty: 2,
        required_tool_codes: ["cauldron"],
        result_quantity: 1,
        requirements: [%{qualities: ["luminous"], quantity: 1}]
      })

    assert {:error, changeset} = Alchemy.brew(alchemist, workspace, quality_recipe, 1)
    assert %{status: ["missing required ingredients"]} = errors_on(changeset)
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

  defp specialize_alchemy(character) do
    %Specialization{}
    |> Specialization.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      track: :alchemy,
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
