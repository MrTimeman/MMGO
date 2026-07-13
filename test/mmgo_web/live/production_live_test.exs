defmodule MMGOWeb.ProductionLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Specialization
  alias MMGO.Alchemy
  alias MMGO.Bases
  alias MMGO.Crafting
  alias MMGO.Inventory
  alias MMGO.Repo
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

    %{realm: realm, city: city}
  end

  test "starts a real alchemy brew from an owned base workshop", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "alch-live", "Alchemy Live")
    specialize(character, :alchemy)
    {:ok, _base} = Bases.purchase_city_base(character, city)

    {:ok, cauldron} = item_template("alch-live-cauldron", "Cauldron", :tool)
    {:ok, herb} = item_template("alch-live-herb", "Herb", :ingredient)
    {:ok, potion} = item_template("alch-live-potion", "Potion", :potion)
    {:ok, _tool} = Inventory.grant_item(character, cauldron)
    {:ok, _herbs} = Inventory.grant_item(character, herb, %{quantity: 2})

    {:ok, recipe} =
      Alchemy.create_recipe(%{
        code: "alch-live-recipe",
        name: "Live Draught",
        result_item_template_id: potion.id,
        brew_time_game_days: 1,
        difficulty: 1,
        required_tool_codes: ["alch-live-cauldron"],
        result_quantity: 1,
        requirements: [%{item_template_id: herb.id, quantity: 1}]
      })

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/alchemy")
    assert has_element?(view, "#alchemy-workshop-form")

    view
    |> form("#alchemy-workshop-form", %{"alchemy_workshop" => %{"name" => "Live Lab"}})
    |> render_submit()

    assert has_element?(view, "#alchemy-brew-form")

    view
    |> form("#alchemy-brew-form", %{"brew" => %{"recipe_id" => recipe.id, "quantity" => "1"}})
    |> render_submit()

    [job] = Alchemy.list_brew_jobs_for_character(character.id)
    assert job.recipe_id == recipe.id
    assert has_element?(view, "#alchemy-job-#{job.id}")
  end

  test "starts a real crafting job from an owned base workshop", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "craft-live", "Craft Live")
    specialize(character, :mastery)
    {:ok, _base} = Bases.purchase_city_base(character, city)

    {:ok, forge} = item_template("craft-live-forge", "Forge", :tool)
    {:ok, ore} = item_template("craft-live-ore", "Ore", :ingredient)
    {:ok, result} = item_template("craft-live-result", "Tool", :tool)
    {:ok, _tool} = Inventory.grant_item(character, forge)
    {:ok, _ore} = Inventory.grant_item(character, ore, %{quantity: 2})

    {:ok, recipe} =
      Crafting.create_recipe(%{
        code: "craft-live-recipe",
        name: "Live Tool",
        result_item_template_id: result.id,
        craft_time_game_days: 1,
        difficulty: 1,
        required_tool_codes: ["craft-live-forge"],
        result_quantity: 1,
        result_durability: 0,
        requirements: [%{item_template_id: ore.id, quantity: 1}]
      })

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/craft")
    assert has_element?(view, "#craft-workshop-form")

    view
    |> form("#craft-workshop-form", %{"craft_workshop" => %{"name" => "Live Forge"}})
    |> render_submit()

    assert has_element?(view, "#craft-form")

    view
    |> form("#craft-form", %{"craft" => %{"recipe_id" => recipe.id, "quantity" => "1"}})
    |> render_submit()

    [job] = Crafting.list_craft_jobs_for_character(character.id)
    assert job.recipe_id == recipe.id
    assert has_element?(view, "#craft-job-#{job.id}")
  end

  defp item_template(code, name, item_type) do
    Inventory.create_item_template(%{
      code: code,
      name: name,
      item_type: item_type,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 0,
      actions: template_actions(item_type)
    })
  end

  defp specialize(character, track) do
    %Specialization{}
    |> Specialization.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      track: track,
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp template_actions(:ingredient), do: []

  defp template_actions(_item_type) do
    [
      %{
        key: "deploy",
        action_kind: :deploy,
        targeting: :self,
        quantity_cost: 0,
        durability_cost: 0,
        effects: [
          %{applies_to: :caster, state: "shielded", intensity: 1, variance: 0, duration: 1}
        ]
      }
    ]
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

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
