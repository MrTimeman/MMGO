defmodule MMGOWeb.BaseLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Inventory
  alias MMGO.Organizations
  alias MMGO.Repo
  alias MMGO.Survival
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

    character = character_fixture(realm, city)

    {:ok, template} =
      Inventory.create_item_template(%{
        code: "base_live_ore",
        name: "Base Live Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, item} = Inventory.grant_item(character, template, %{quantity: 3})

    %{character: character, city: city, item: item}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/base")
  end

  test "buys the current city base and transfers only owned carried items", %{
    conn: conn,
    character: character,
    item: item
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/base")
    assert has_element?(view, "#base-establish-form")

    view
    |> form("#base-establish-form", %{"base_establish" => %{"name" => "Quiet Rooms"}})
    |> render_submit()

    base = Bases.list_bases_for_character(character.id) |> List.first()
    assert base.name == "Quiet Rooms"
    assert has_element?(view, "#base-active")
    assert has_element?(view, "#base-open-spellbook")
    assert has_element?(view, "#base-open-craft")
    assert has_element?(view, "#base-open-alchemy")

    view
    |> form("#base-deposit-form", %{
      "base_deposit" => %{"inventory_item_id" => item.id, "quantity" => "2"}
    })
    |> render_submit()

    [stored] = Bases.list_storage_items(base.id)
    assert stored.quantity == 2
    assert has_element?(view, "#base-storage-#{stored.id}")

    view
    |> form("#base-withdraw-form", %{
      "base_withdraw" => %{"storage_item_id" => stored.id, "quantity" => "1"}
    })
    |> render_submit()

    assert Inventory.get_inventory_item!(item.id).quantity == 2
  end

  test "recovers real hunger by consuming a stored ration through the scoped base screen", %{
    conn: conn,
    character: character,
    city: city
  } do
    {:ok, base} = Bases.purchase_city_base(character, city)

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "base_live_ration",
        name: "Base Live Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, ration_item} = Inventory.grant_item(character, ration_template, %{quantity: 2})

    assert {:ok, %{storage_item: stored_ration}} =
             Bases.deposit_item(character, base, ration_item, 2)

    assert {:ok, _starved_character} =
             Survival.apply_starvation_consequences(Repo, character, %{
               "food_shortage_days" => 2,
               "movement_penalty_days" => 1
             })

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/base")
    assert has_element?(view, "#base-rest-submit")

    view |> element("#base-rest-submit") |> render_click()

    refute Survival.summary(Repo.get!(Character, character.id)).starving?
    assert MMGO.Bases.get_storage_item!(stored_ration.id).quantity == 1
    refute has_element?(view, "#base-rest-submit")
  end

  test "an organization custodian opens an explicitly selected shared base without personal workbench access",
       %{conn: conn, character: owner, city: city} do
    {:ok, base} = Bases.purchase_city_base(owner, city, %{name: "Company Store"})

    {:ok, %{organization: organization}} =
      Organizations.create_organization(owner, :company, "Company Storekeepers")

    {:ok, custodian_role} =
      Organizations.add_role(organization, owner, %{
        code: "store-custodian",
        title: "Store Custodian",
        rank: 50,
        permissions: ["manage_treasury"]
      })

    custodian = character_fixture(realm_for(city), city, "base-live-custodian", "Base Custodian")

    {:ok, invitation} =
      Organizations.invite_member(organization, owner, custodian, custodian_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, custodian)

    {:ok, owner_view, _html} = live(session_conn(conn, owner), ~p"/base")
    assert has_element?(owner_view, "#base-organization-ownership-form")

    owner_view
    |> form("#base-organization-ownership-form", %{
      "base_ownership" => %{"organization_id" => organization.id, "share_bps" => "6000"}
    })
    |> render_submit()

    {:ok, custodian_view, _html} =
      live(session_conn(conn, custodian), ~p"/base/#{base.id}")

    assert has_element?(custodian_view, "#base-active")
    assert has_element?(custodian_view, "#base-access-via-organization")
    assert has_element?(custodian_view, "#base-shared-workbench-notice")
    refute has_element?(custodian_view, "#base-workbench")
  end

  defp character_fixture(realm, location, handle \\ "base-live", name \\ "Base Live") do
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

  defp realm_for(city), do: Worlds.get_realm!(city.realm_id)

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
