defmodule MMGO.PartiesTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Parties.{ExpeditionMember, Membership}
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 240,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 20,
        bidirectional: true
      })

    leader = character_fixture(realm, city, "leader-mage", "Leader Mage")
    member = character_fixture(realm, city, "member-mage", "Member Mage")
    outsider = character_fixture(realm, tower, "outsider-mage", "Outsider Mage")

    %{
      realm: realm,
      city: city,
      tower: tower,
      route: route,
      leader: leader,
      member: member,
      outsider: outsider
    }
  end

  test "create_party/2 creates an active party and leader membership", %{leader: leader} do
    assert {:ok, %{party: party, membership: membership}} =
             Parties.create_party(leader, %{name: "Tower Delvers"})

    assert party.name == "Tower Delvers"
    assert party.status == :active
    assert membership.role == :leader
    assert Parties.active_party_for_character(leader.id).id == party.id
  end

  test "remove_member/2 transfers leadership to the next active member", %{
    leader: leader,
    member: member
  } do
    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Tower Delvers"})
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)

    assert {:ok, %{party: updated_party}} = Parties.remove_member(party, leader)

    assert updated_party.leader_character_id == member.id
    replacement_leader = Repo.get_by!(Membership, party_id: party.id, character_id: member.id)
    assert replacement_leader.role == :leader
  end

  test "start_expedition/2 snapshots active party members", %{
    leader: leader,
    member: member,
    city: city
  } do
    {:ok, %{party: party}} = Parties.create_party(leader)
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)

    assert {:ok, %{expedition: expedition, members: members}} = Parties.start_expedition(party)

    assert expedition.status == :active
    assert expedition.location_id == city.id
    assert length(members) == 2
    assert Repo.aggregate(ExpeditionMember, :count, :id) == 2
  end

  test "start_expedition/2 rejects parties split across locations", %{
    leader: leader,
    outsider: outsider
  } do
    {:ok, %{party: party}} = Parties.create_party(leader)
    {:ok, %{membership: _membership}} = Parties.add_member(party, outsider)

    assert {:error, changeset} = Parties.start_expedition(party)
    assert %{status: ["all members must be in the same location"]} = errors_on(changeset)
  end

  test "start_expedition/2 rejects parties with travelling members", %{
    leader: leader,
    member: member,
    route: route
  } do
    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "party_travel_ration",
        name: "Party Travel Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, _rations} = Inventory.grant_item(member, ration_template, %{quantity: 20})

    {:ok, %{party: party}} = Parties.create_party(leader)
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)
    assert {:ok, _journey_result} = Travel.start_journey(member, route)

    assert {:error, changeset} = Parties.start_expedition(party)
    assert %{status: ["a member is currently travelling"]} = errors_on(changeset)
  end

  test "end_expedition/2 completes the expedition and its members", %{
    leader: leader,
    member: member
  } do
    {:ok, %{party: party}} = Parties.create_party(leader)
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    assert {:ok, %{expedition: updated_expedition}} =
             Parties.end_expedition(expedition, %{status: :completed})

    assert updated_expedition.status == :completed
    assert Repo.aggregate(ExpeditionMember, :count, :id) == 2
    refute Parties.active_expedition_for_party(party.id)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
