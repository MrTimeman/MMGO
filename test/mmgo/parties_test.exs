defmodule MMGO.PartiesTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Enrollment
  alias MMGO.Clubs
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Notifications
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

  test "leader invites a nearby member, readiness gates expedition, and loot policy persists", %{
    leader: leader,
    member: member
  } do
    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Tower Delvers"})

    assert {:ok, %{party: invited_party, invitation: invitation}} =
             Parties.invite_member(party, leader, member)

    assert [%{id: invitation_id, party: pending_party}] =
             Parties.pending_invitations_for_character(member.id)

    assert invitation_id == invitation["id"]
    assert pending_party.id == party.id
    assert [stored_invitation | _rest] = invited_party.metadata["invitations"]
    assert stored_invitation["status"] == "pending"

    assert [%{channel: :in_app, kind: "party_invitation", payload: payload}] =
             Notifications.list_notifications(member.id)

    assert payload["party_id"] == party.id
    assert payload["invitation_id"] == invitation_id

    assert {:ok, %{party: accepted_party, membership: membership}} =
             Parties.accept_invitation(invitation_id, member)

    assert membership.status == :active
    assert membership.role == :member
    assert [%{"status" => "accepted"} | _rest] = accepted_party.metadata["invitations"]

    assert {:ok, _membership} = Parties.set_member_ready(accepted_party, leader, false)
    assert {:error, changeset} = Parties.start_expedition(accepted_party)
    assert %{status: ["all party members must be ready"]} = errors_on(changeset)

    assert {:ok, _membership} = Parties.set_member_ready(accepted_party, leader, true)
    assert {:ok, configured_party} = Parties.set_loot_policy(accepted_party, leader, "leader")
    assert configured_party.metadata["loot_policy"] == "leader"
    assert {:ok, %{expedition: expedition}} = Parties.start_expedition(configured_party)
    assert expedition.status == :active
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

  test "start_expedition/2 initializes a durable food reserve and carry snapshot", %{
    leader: leader
  } do
    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "party_survival_ledger_ration",
        name: "Party Survival Ledger Ration",
        item_type: :food,
        stackable: true,
        weight: 41,
        max_durability: 0,
        nutrition_units: 3,
        actions: []
      })

    {:ok, _ration} = Inventory.grant_item(leader, ration_template, %{quantity: 1})
    {:ok, %{party: party}} = Parties.create_party(leader)

    assert {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    assert expedition.food_units_snapshot == 3
    assert expedition.daily_food_demand == 1
    assert expedition.carried_weight == 41
    assert expedition.carry_capacity == 40

    assert %{
             "food_units_initial" => 3,
             "food_units_remaining" => 3,
             "food_units_consumed" => 0,
             "foodless_game_days" => 0,
             "shared_hp_drain" => 0,
             "movement_penalty_days" => 0,
             "encumbered" => true
           } = expedition.metadata["survival"]

    assert %{food_units_remaining: 3, encumbered?: true} =
             Parties.expedition_survival_state(expedition)
  end

  test "shared expedition briefings become a one-use route plan for the full party", %{
    realm: realm,
    leader: leader,
    member: member
  } do
    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    enroll_active_academy_core(leader, realm)
    enroll(member, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, leader, 100)

    {:ok, %{club: club}} =
      Clubs.create_club(leader, %{club_type: :expedition_planning, name: "Route Scouts"})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, leader, member)
    {:ok, _membership} = Clubs.accept_invitation(invitation, member)
    {:ok, briefing} = Clubs.create_event(club, %{kind: :expedition_briefing})
    assert {:ok, _attendance} = Clubs.attend_event(briefing, leader)
    assert {:ok, _attendance} = Clubs.attend_event(briefing, member)

    {:ok, %{party: party}} = Parties.create_party(leader)
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)

    assert {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    assert %{
             "status" => "available",
             "source" => "club_expedition_briefing",
             "participant_character_ids" => participant_ids,
             "xp_bonus_bps" => 1_000
           } = expedition.metadata["club_route_plan"]

    assert Enum.sort(participant_ids) == Enum.sort([leader.id, member.id])

    for character <- [leader, member] do
      membership =
        Repo.get_by!(MMGO.Clubs.Membership, club_id: club.id, character_id: character.id)

      assert Clubs.expedition_plan_contribution(membership).credits == 0
    end
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

  test "a member's committed journey broadcasts a live party refresh", %{
    leader: leader,
    member: member,
    route: route
  } do
    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "party_live_refresh_ration",
        name: "Party Live Refresh Ration",
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
    party_id = party.id

    :ok = Phoenix.PubSub.subscribe(MMGO.PubSub, Parties.party_topic(party_id))

    assert {:ok, %{journey: journey}} = Travel.start_journey(member, route)
    assert_receive {:party_updated, ^party_id}

    assert {:ok, _result} =
             Travel.complete_journey_by_id(journey.id, now: journey.arrival_at, force: true)

    assert_receive {:party_updated, ^party_id}
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

  defp enroll(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :none,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp enroll_active_academy_core(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry,
      status: :active,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
