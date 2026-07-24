defmodule MMGO.BasesOwnershipTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Inventory
  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Survival
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "shared-base-realm",
        name: "Shared Base Realm",
        is_default: true
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "shared-base-city",
        name: "Shared Base City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    owner = character_fixture(realm, city, "base-owner", "Base Owner")
    custodian = character_fixture(realm, city, "base-custodian", "Base Custodian")
    member = character_fixture(realm, city, "base-member", "Base Member")

    fund_base_acquisition!(realm, owner)

    {:ok, template} =
      Inventory.create_item_template(%{
        code: "shared_base_ration",
        name: "Shared Base Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, base} = Bases.purchase_city_base(owner, city, %{name: "Shared Hall"})

    {:ok, %{organization: organization, member_role: member_role}} =
      Organizations.create_organization(owner, :company, "Shared Hall Company")

    {:ok, custodian_role} =
      Organizations.add_role(organization, owner, %{
        code: "store-custodian",
        title: "Store Custodian",
        rank: 50,
        permissions: ["manage_treasury"]
      })

    {:ok, custodian_invitation} =
      Organizations.invite_member(organization, owner, custodian, custodian_role)

    assert {:ok, _membership} = Organizations.accept_invitation(custodian_invitation, custodian)

    {:ok, member_invitation} =
      Organizations.invite_member(organization, owner, member, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(member_invitation, member)

    %{
      realm: realm,
      city: city,
      owner: owner,
      custodian: custodian,
      member: member,
      base: base,
      organization: organization,
      template: template
    }
  end

  test "an organization share gives only live treasury custodians real shared-base access", %{
    owner: owner,
    custodian: custodian,
    member: member,
    base: base,
    organization: organization,
    template: template
  } do
    assert {:ok, shared_base} =
             Bases.configure_organization_share(base, owner, organization, 6_000)

    assert %{owner_character_id: owner_id, owner_share_bps: 4_000} =
             Bases.ownership_state(shared_base)

    assert owner_id == owner.id
    assert Bases.ownership_state(shared_base).organization_share_bps[organization.id] == 6_000
    assert Bases.can_access?(shared_base, custodian)
    refute Bases.can_access?(shared_base, member)

    {:ok, ration} = Inventory.grant_item(custodian, template, %{quantity: 2})

    assert {:ok, %{storage_item: stored_ration}} =
             Bases.deposit_item(custodian, shared_base, ration, 2)

    assert {:ok, starved_custodian} =
             Survival.apply_starvation_consequences(Repo, custodian, %{
               "food_shortage_days" => 2,
               "movement_penalty_days" => 1
             })

    assert {:ok, %{character: recovered_custodian, food_units_consumed: 1}} =
             Bases.rest_at_base(starved_custodian, shared_base)

    refute Survival.summary(recovered_custodian).starving?

    assert {:error, _changeset} = Bases.withdraw_item(member, shared_base, stored_ration, 1)

    assert {:ok, %{inventory_item: recovered_ration}} =
             Bases.withdraw_item(custodian, shared_base, stored_ration, 1)

    assert recovered_ration.character_id == custodian.id

    assert {:ok, unshared_base} =
             Bases.configure_organization_share(shared_base, owner, organization, 0)

    refute Bases.can_access?(unshared_base, custodian)

    assert {:error, _changeset} =
             Bases.deposit_item(custodian, unshared_base, recovered_ration, 1)
  end

  test "the scoped facade requires an explicit accessible base and leaves personal building available",
       %{
         owner: owner,
         custodian: custodian,
         base: base,
         organization: organization,
         template: template
       } do
    assert {:ok, shared_base} =
             Bases.configure_organization_share(base, owner, organization, 5_000)

    assert {:ok, state} = Play.base_state(custodian, shared_base.id)
    assert state.active_base.id == shared_base.id
    assert state.ownership.via_organization?
    assert state.can_establish?

    assert {:error, :base_not_accessible} = Play.base_state(custodian, "not-a-base")

    assert {:error, :base_ownership_organization_not_found} =
             Play.configure_current_base_organization_share(
               owner,
               shared_base.id,
               "not-an-organization-id",
               100
             )

    {:ok, ration} = Inventory.grant_item(custodian, template, %{quantity: 1})

    assert {:ok, refreshed_state} =
             Play.deposit_to_current_base(custodian, ration.id, 1, shared_base.id)

    assert refreshed_state.active_base.id == shared_base.id
  end

  test "several shared bases at one location require an explicit selection", %{
    realm: realm,
    city: city,
    owner: owner,
    custodian: custodian,
    base: first_base,
    organization: first_organization
  } do
    assert {:ok, first_shared_base} =
             Bases.configure_organization_share(first_base, owner, first_organization, 5_000)

    second_owner = character_fixture(realm, city, "second-base-owner", "Second Base Owner")
    fund_base_acquisition!(realm, second_owner)

    {:ok, second_base} =
      Bases.purchase_city_base(second_owner, city, %{name: "Second Shared Hall"})

    {:ok, %{organization: second_organization}} =
      Organizations.create_organization(second_owner, :guild, "Second Shared Guild")

    {:ok, custodian_role} =
      Organizations.add_role(second_organization, second_owner, %{
        code: "second-store-custodian",
        title: "Second Store Custodian",
        rank: 50,
        permissions: ["manage_treasury"]
      })

    {:ok, invitation} =
      Organizations.invite_member(second_organization, second_owner, custodian, custodian_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, custodian)

    assert {:ok, second_shared_base} =
             Bases.configure_organization_share(
               second_base,
               second_owner,
               second_organization,
               4_000
             )

    assert {:ok, ambiguous_state} = Play.base_state(custodian)
    assert ambiguous_state.active_base == nil
    assert ambiguous_state.requires_base_selection?

    assert {:ok, selected_state} = Play.base_state(custodian, second_shared_base.id)
    assert selected_state.active_base.id == second_shared_base.id
    refute selected_state.active_base.id == first_shared_base.id
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
