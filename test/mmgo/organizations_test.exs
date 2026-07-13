defmodule MMGO.OrganizationsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Notifications.Notification
  alias MMGO.Organizations
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "tower",
        name: "Tower",
        kind: :tower,
        x: 20,
        y: 20,
        safe_zone: false
      })

    founder = character_fixture(realm, city, "archbishop", "Archbishop")
    invitee = character_fixture(realm, city, "acolyte", "Acolyte")

    %{realm: realm, city: city, tower: tower, founder: founder, invitee: invitee}
  end

  test "list_active_organizations_for_realm/1 returns only active orgs in the realm", %{
    founder: founder
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :guild, "Cartographers", %{})

    realm_id = founder.realm_id
    listed = Organizations.list_active_organizations_for_realm(realm_id)
    assert Enum.map(listed, & &1.id) == [organization.id]

    organization
    |> Ecto.Changeset.change(status: :archived)
    |> Repo.update!()

    assert Organizations.list_active_organizations_for_realm(realm_id) == []
  end

  test "create_organization/4 creates a cult with an archbishop role", %{
    founder: founder,
    city: city,
    tower: tower
  } do
    assert {:ok, %{organization: organization, role: role}} =
             Organizations.create_organization(founder, :cult, "Death Cult", %{
               fast_travel_enabled: true,
               linked_location_ids: [city.id, tower.id]
             })

    assert organization.kind == :cult
    assert role.code == "archbishop"
    assert "grant_fast_travel" in role.permissions
  end

  test "invite_member/4 and accept_invitation/2 join a cult and enable fast travel", %{
    founder: founder,
    invitee: invitee,
    city: city,
    tower: tower
  } do
    {:ok, %{organization: organization, role: _leader_role}} =
      Organizations.create_organization(founder, :cult, "Death Cult", %{
        fast_travel_enabled: true,
        linked_location_ids: [city.id, tower.id]
      })

    assert {:ok, role} =
             Organizations.add_role(organization, founder, %{
               code: "member",
               title: "Acolyte",
               rank: 10,
               permissions: ["grant_fast_travel"]
             })

    assert role.rank == 10

    assert {:ok, invitation} = Organizations.invite_member(organization, founder, invitee, role)

    assert Enum.any?(Repo.all(Notification), fn notification ->
             notification.character_id == invitee.id and
               notification.kind == "organization_invitation" and notification.channel == :in_app
           end)

    assert {:ok, membership} = Organizations.accept_invitation(invitation, invitee)
    assert membership.status == :active

    destinations = Organizations.list_available_fast_travel_destinations(invitee)
    assert Enum.map(destinations, & &1.id) == [tower.id]

    assert {:ok, updated_character} = Organizations.use_fast_travel(invitee, organization, tower)
    assert updated_character.current_location_id == tower.id
  end

  test "treasury managers set directional tolls that quote and remit the exact realm tax", %{
    realm: realm,
    city: city,
    tower: tower,
    founder: founder,
    invitee: invitee
  } do
    {:ok, realm_treasury} = Economy.ensure_treasury_account(realm, 1_000)

    %{organization: organization, treasury_account: organization_account} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    assert {:ok, organization} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, 100)

    assert Organizations.fast_travel_toll_state(organization) == %{
             tax_rate_bps: 500,
             route_fees: %{city.id => %{tower.id => 100}}
           }

    assert {:ok, quote} = Organizations.fast_travel_toll_quote(organization, city, tower)

    assert quote == %{
             origin_location_id: city.id,
             destination_location_id: tower.id,
             fee: 100,
             organization_amount: 95,
             tax_amount: 5,
             tax_rate_bps: 500,
             charged?: true
           }

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, invitee, 100)

    assert {:ok, updated_character} = Organizations.use_fast_travel(invitee, organization, tower)
    assert updated_character.current_location_id == tower.id

    {:ok, invitee_account} = Economy.ensure_character_account(invitee)
    assert Economy.get_account!(invitee_account.id).current_balance == 0
    assert Economy.get_account!(organization_account.id).current_balance == 95
    assert Economy.get_account!(realm_treasury.id).current_balance == 905

    organization_entries = Economy.list_ledger_entries_for_account(organization_account.id)

    assert Enum.any?(organization_entries, fn entry ->
             entry.entry_type == :transfer and entry.amount == 95 and
               entry.metadata["source"] == "organization_fast_travel_toll" and
               entry.metadata["organization_id"] == organization.id and
               entry.metadata["traveler_character_id"] == invitee.id
           end)

    realm_entries = Economy.list_ledger_entries_for_account(realm_treasury.id)

    assert Enum.any?(realm_entries, fn entry ->
             entry.entry_type == :tax and entry.amount == 5 and
               entry.metadata["source"] == "organization_fast_travel_toll" and
               entry.metadata["tax_rate_bps"] == 500
           end)
  end

  test "fast-travel toll configuration validates amount and linked locations and requires treasury authority",
       %{realm: realm, city: city, tower: tower, founder: founder, invitee: invitee} do
    %{organization: organization} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    assert {:error, changeset} =
             Organizations.configure_fast_travel_toll(organization, invitee, city, tower, 25)

    assert %{status: ["role lacks required permission manage_treasury"]} = errors_on(changeset)

    assert {:error, changeset} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, -1)

    assert %{status: ["fast travel toll amount must be a non-negative integer"]} =
             errors_on(changeset)

    {:ok, unlinked_location} =
      Worlds.create_location(realm, %{
        slug: "unlinked-outpost",
        name: "Unlinked Outpost",
        kind: :wilderness,
        x: 30,
        y: 30,
        safe_zone: false
      })

    assert {:error, changeset} =
             Organizations.configure_fast_travel_toll(
               organization,
               founder,
               city,
               unlinked_location,
               25
             )

    assert %{status: ["fast travel toll locations must be linked to this organization"]} =
             errors_on(changeset)

    assert Organizations.fast_travel_toll_state(organization).route_fees == %{}
  end

  test "a toll cannot move or charge a traveler with insufficient funds", %{
    realm: realm,
    city: city,
    tower: tower,
    founder: founder,
    invitee: invitee
  } do
    {:ok, realm_treasury} = Economy.ensure_treasury_account(realm, 1_000)

    %{organization: organization, treasury_account: organization_account} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    assert {:ok, organization} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, 100)

    {:ok, invitee_account} = Economy.ensure_character_account(invitee)

    assert {:error, changeset} = Organizations.use_fast_travel(invitee, organization, tower)
    assert %{current_balance: ["is insufficient for this transfer"]} = errors_on(changeset)

    assert Repo.get!(Character, invitee.id).current_location_id == city.id
    assert Economy.get_account!(invitee_account.id).current_balance == 0
    assert Economy.get_account!(organization_account.id).current_balance == 0
    assert Economy.get_account!(realm_treasury.id).current_balance == 1_000
  end

  test "zero-fee routes retain the original free fast-travel behavior", %{
    realm: realm,
    city: city,
    tower: tower,
    founder: founder,
    invitee: invitee
  } do
    %{organization: organization} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    assert {:ok, organization} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, 0)

    assert {:ok, quote} = Organizations.fast_travel_toll_quote(organization, city, tower)
    assert quote.fee == 0
    assert quote.organization_amount == 0
    assert quote.tax_amount == 0
    refute quote.charged?

    assert Economy.treasury_account_for_realm(realm.id) == nil
    assert Repo.get_by(EconomyAccount, character_id: invitee.id, owner_type: :character) == nil

    assert {:ok, updated_character} = Organizations.use_fast_travel(invitee, organization, tower)
    assert updated_character.current_location_id == tower.id

    assert Economy.treasury_account_for_realm(realm.id) == nil
    assert Repo.get_by(EconomyAccount, character_id: invitee.id, owner_type: :character) == nil
  end

  test "invalid destinations and active journeys fail before a configured toll is charged",
       %{realm: realm, city: city, tower: tower, founder: founder, invitee: invitee} do
    {:ok, realm_treasury} = Economy.ensure_treasury_account(realm, 1_000)

    %{organization: organization, treasury_account: organization_account} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    assert {:ok, organization} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, 100)

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, invitee, 100)
    {:ok, invitee_account} = Economy.ensure_character_account(invitee)

    {:ok, unlinked_location} =
      Worlds.create_location(realm, %{
        slug: "blocked-outpost",
        name: "Blocked Outpost",
        kind: :wilderness,
        x: 40,
        y: 40,
        safe_zone: false
      })

    assert {:error, changeset} =
             Organizations.use_fast_travel(invitee, organization, unlinked_location)

    assert %{status: ["destination is not linked to this organization"]} = errors_on(changeset)
    assert Economy.get_account!(invitee_account.id).current_balance == 100
    assert Economy.get_account!(organization_account.id).current_balance == 0
    assert Economy.get_account!(realm_treasury.id).current_balance == 900

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Blocked Toll Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 1,
        risk_level: 0,
        bidirectional: true
      })

    assert {:ok, %{journey: _journey}} = Travel.start_journey(invitee, route)
    assert {:error, changeset} = Organizations.use_fast_travel(invitee, organization, tower)

    assert %{status: ["character cannot use fast travel while travelling"]} = errors_on(changeset)
    assert Economy.get_account!(invitee_account.id).current_balance == 100
    assert Economy.get_account!(organization_account.id).current_balance == 0
    assert Economy.get_account!(realm_treasury.id).current_balance == 900
    assert Repo.get!(Character, invitee.id).current_location_id == city.id
  end

  test "a member without fast-travel permission is rejected before a toll charge", %{
    realm: realm,
    city: city,
    tower: tower,
    founder: founder,
    invitee: invitee
  } do
    {:ok, realm_treasury} = Economy.ensure_treasury_account(realm, 1_000)

    %{organization: organization, treasury_account: organization_account} =
      fast_travel_organization_fixture(founder, invitee, city, tower)

    restricted_member = character_fixture(realm, city, "restricted-passage", "Restricted Passage")

    member_role =
      organization.roles
      |> Enum.find(&(&1.code == "open-member"))

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, restricted_member, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, restricted_member)

    assert {:ok, organization} =
             Organizations.configure_fast_travel_toll(organization, founder, city, tower, 100)

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, restricted_member, 100)
    {:ok, restricted_account} = Economy.ensure_character_account(restricted_member)

    assert {:error, changeset} =
             Organizations.use_fast_travel(restricted_member, organization, tower)

    assert %{status: ["role lacks required permission grant_fast_travel"]} = errors_on(changeset)
    assert Repo.get!(Character, restricted_member.id).current_location_id == city.id
    assert Economy.get_account!(restricted_account.id).current_balance == 100
    assert Economy.get_account!(organization_account.id).current_balance == 0
    assert Economy.get_account!(realm_treasury.id).current_balance == 900
  end

  test "an invitation cannot attach a role from another organization", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :guild, "Role Bound Guild")

    assert {:ok, %{role: foreign_role}} =
             Organizations.create_organization(founder, :company, "Foreign Role Company")

    assert {:error, changeset} =
             Organizations.invite_member(organization, founder, invitee, foreign_role)

    assert %{status: ["invitation role must belong to this organization"]} = errors_on(changeset)
  end

  test "only a member with manage_roles may add organization roles", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :guild, "Cartographers")

    assert {:ok, member_role} =
             Organizations.add_role(organization, founder, %{
               code: "member",
               title: "Member",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:error, changeset} =
             Organizations.add_role(organization, invitee, %{
               code: "officer",
               title: "Officer",
               rank: 20,
               permissions: ["invite_members"]
             })

    assert %{status: ["role lacks required permission manage_roles"]} = errors_on(changeset)
  end

  test "organization hierarchy rules and leader rank constrain custom roles", %{founder: founder} do
    assert {:ok, %{organization: locked_organization}} =
             Organizations.create_organization(founder, :council, "Fixed Charter", %{
               hierarchy_rules: %{"custom_roles_allowed" => false}
             })

    assert {:error, changeset} =
             Organizations.add_role(locked_organization, founder, %{
               code: "scribe",
               title: "Scribe",
               rank: 10,
               permissions: []
             })

    assert %{status: ["organization constitution does not permit custom roles"]} =
             errors_on(changeset)

    assert {:ok, %{organization: open_organization}} =
             Organizations.create_organization(founder, :guild, "Open Charter")

    assert {:error, changeset} =
             Organizations.add_role(open_organization, founder, %{
               code: "counterfeit-leader",
               title: "Counterfeit Leader",
               rank: 100,
               permissions: ["manage_treasury"]
             })

    assert %{status: ["custom role rank must be between 0 and 99"]} = errors_on(changeset)
  end

  test "the membership admission block enforces invitation-only and open enrollment", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :guild, "Open Door")

    assert Organizations.membership_state(organization) == %{
             admission: "invitation_only",
             open?: false
           }

    assert {:error, changeset} = Organizations.join_open_organization(organization, invitee)
    assert %{status: ["organization is invitation-only"]} = errors_on(changeset)

    assert {:ok, configured_organization} =
             Organizations.configure_membership_admission(organization, founder, "open")

    assert Organizations.membership_state(configured_organization) == %{
             admission: "open",
             open?: true
           }

    assert {:ok, membership} =
             Organizations.join_open_organization(configured_organization, invitee)

    assert membership.role_id == member_role.id
    assert membership.metadata["admission"] == "open"

    assert {:error, changeset} =
             Organizations.join_open_organization(configured_organization, invitee)

    assert %{status: ["character is already an active organization member"]} =
             errors_on(changeset)
  end

  test "treasury ownership shares are durable, capped, and role-gated", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :company, "Share Company")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:ok, organization} =
             Organizations.assign_treasury_share(organization, founder, invitee, 6_000)

    assert Organizations.treasury_ownership_state(organization) == %{
             shares: %{"character:#{invitee.id}" => 6_000, "organization" => 4_000},
             member_share_bps: %{invitee.id => 6_000},
             organization_share_bps: 4_000
           }

    assert {:error, changeset} =
             Organizations.assign_treasury_share(organization, invitee, invitee, 7_000)

    assert %{status: ["role lacks required permission manage_treasury"]} = errors_on(changeset)

    assert {:error, changeset} =
             Organizations.assign_treasury_share(organization, founder, invitee, 10_001)

    assert %{status: ["treasury share assignment is invalid"]} = errors_on(changeset)
  end

  test "diplomacy requests require the other organization's real acceptance", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: source_organization}} =
             Organizations.create_organization(founder, :guild, "Source Guild")

    assert {:ok, %{organization: target_organization}} =
             Organizations.create_organization(invitee, :company, "Target Company")

    assert {:ok, %{proposal: proposal}} =
             Organizations.propose_diplomacy(
               source_organization,
               founder,
               target_organization,
               "alliance"
             )

    target_state =
      Organizations.diplomacy_state(Organizations.get_organization!(target_organization.id))

    assert [incoming_request] = target_state.incoming_requests
    assert incoming_request["id"] == proposal["id"]
    assert incoming_request["source_organization_id"] == source_organization.id

    assert {:ok, %{resolution: :accepted}} =
             Organizations.respond_to_diplomacy_request(
               target_organization,
               invitee,
               proposal["id"],
               :accept
             )

    source_state =
      Organizations.diplomacy_state(Organizations.get_organization!(source_organization.id))

    target_state =
      Organizations.diplomacy_state(Organizations.get_organization!(target_organization.id))

    source_organization_id = source_organization.id
    target_organization_id = target_organization.id

    assert [
             %{
               "organization_id" => ^target_organization_id,
               "kind" => "alliance",
               "established_at" => established_at
             }
           ] = source_state.relationships

    assert is_binary(established_at)

    assert [
             %{
               "organization_id" => ^source_organization_id,
               "kind" => "alliance",
               "established_at" => ^established_at
             }
           ] = target_state.relationships

    assert {:error, changeset} =
             Organizations.propose_diplomacy(
               source_organization,
               founder,
               target_organization,
               "alliance"
             )

    assert %{status: ["organizations already have a diplomatic relationship"]} =
             errors_on(changeset)
  end

  test "a mutually accepted war is a durable active-conflict relationship", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: source_organization}} =
             Organizations.create_organization(founder, :guild, "War Source")

    assert {:ok, %{organization: target_organization}} =
             Organizations.create_organization(invitee, :company, "War Target")

    assert {:ok, %{proposal: proposal}} =
             Organizations.propose_diplomacy(
               source_organization,
               founder,
               target_organization,
               "war"
             )

    assert {:ok, %{resolution: :accepted}} =
             Organizations.respond_to_diplomacy_request(
               target_organization,
               invitee,
               proposal["id"],
               :accept
             )

    source_state =
      Organizations.diplomacy_state(Organizations.get_organization!(source_organization.id))

    assert [%{"organization_id" => target_id, "kind" => "war"}] = source_state.relationships
    assert target_id == target_organization.id
  end

  test "role managers cannot create peers or grant permissions they do not hold", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :guild, "Ranked Charter")

    assert {:ok, steward_role} =
             Organizations.add_role(organization, founder, %{
               code: "steward",
               title: "Steward",
               rank: 40,
               permissions: ["manage_roles"]
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, steward_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:error, changeset} =
             Organizations.add_role(organization, invitee, %{
               code: "peer-steward",
               title: "Peer Steward",
               rank: 40,
               permissions: ["manage_roles"]
             })

    assert %{status: ["custom role rank must remain below the creator role"]} =
             errors_on(changeset)

    assert {:error, changeset} =
             Organizations.add_role(organization, invitee, %{
               code: "treasurer",
               title: "Treasurer",
               rank: 10,
               permissions: ["manage_treasury"]
             })

    assert %{status: ["custom role cannot grant permissions the creator does not hold"]} =
             errors_on(changeset)
  end

  test "member-election leadership block durably swaps authority after a majority vote", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :council, "Elective Council")

    assert {:ok, member_role} =
             Organizations.add_role(organization, founder, %{
               code: "delegate",
               title: "Delegate",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:error, changeset} =
             Organizations.open_leadership_election(organization, founder, invitee)

    assert %{status: ["member or share elections are not enabled by this constitution"]} =
             errors_on(changeset)

    assert {:ok, configured_organization} =
             Organizations.configure_leadership_selection(
               organization,
               founder,
               "member_election"
             )

    assert Organizations.leadership_state(configured_organization).selection == "member_election"

    assert {:ok, %{proposal: proposal}} =
             Organizations.open_leadership_election(configured_organization, founder, invitee)

    assert proposal["candidate_character_id"] == invitee.id
    assert Enum.sort(proposal["voter_character_ids"]) == Enum.sort([founder.id, invitee.id])

    assert {:ok, %{resolution: :pending}} =
             Organizations.cast_leadership_vote(
               configured_organization,
               founder,
               proposal["id"],
               :approve
             )

    assert {:ok, %{organization: elected_organization, resolution: :accepted}} =
             Organizations.cast_leadership_vote(
               configured_organization,
               invitee,
               proposal["id"],
               :approve
             )

    assert Organizations.leadership_state(elected_organization).leader_character_id == invitee.id

    reloaded_organization = Organizations.get_organization!(organization.id)
    leader_role = Enum.max_by(reloaded_organization.roles, & &1.rank)

    elected_membership =
      Enum.find(reloaded_organization.memberships, &(&1.character_id == invitee.id))

    former_leader_membership =
      Enum.find(reloaded_organization.memberships, &(&1.character_id == founder.id))

    assert elected_membership.role_id == leader_role.id
    assert former_leader_membership.role_id == member_role.id
  end

  test "the active founder appoints a member when the constitution selects founder appointment",
       %{
         founder: founder,
         invitee: invitee
       } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :guild, "Founder Council")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert Organizations.leadership_state(organization).selection == "founder_appointment"

    assert {:ok, appointed_organization} =
             Organizations.appoint_leader(organization, founder, invitee)

    assert Organizations.leadership_state(appointed_organization).leader_character_id ==
             invitee.id

    reloaded_organization = Organizations.get_organization!(organization.id)
    leader_role = Enum.max_by(reloaded_organization.roles, & &1.rank)

    appointed_membership =
      Enum.find(reloaded_organization.memberships, &(&1.character_id == invitee.id))

    founder_membership =
      Enum.find(reloaded_organization.memberships, &(&1.character_id == founder.id))

    assert appointed_membership.role_id == leader_role.id
    assert founder_membership.role_id == member_role.id

    assert {:error, changeset} =
             Organizations.appoint_leader(appointed_organization, invitee, founder)

    assert %{status: ["only the organization founder can appoint a leader"]} =
             errors_on(changeset)
  end

  test "share-weighted leadership elections use durable treasury ownership weights", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :company, "Weighted Company")

    assert {:ok, member_role} =
             Organizations.add_role(organization, founder, %{
               code: "delegate",
               title: "Delegate",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:ok, organization} =
             Organizations.assign_treasury_share(organization, founder, founder, 4_000)

    assert {:ok, organization} =
             Organizations.assign_treasury_share(organization, founder, invitee, 6_000)

    assert {:ok, organization} =
             Organizations.configure_leadership_selection(
               organization,
               founder,
               "share_weighted_election"
             )

    assert {:ok, %{proposal: proposal}} =
             Organizations.open_leadership_election(organization, founder, invitee)

    assert proposal["voter_weights_bps"] == %{founder.id => 4_000, invitee.id => 6_000}

    assert {:ok, %{resolution: :pending}} =
             Organizations.cast_leadership_vote(
               organization,
               founder,
               proposal["id"],
               :reject
             )

    assert {:ok, %{organization: elected_organization, resolution: :accepted}} =
             Organizations.cast_leadership_vote(
               organization,
               invitee,
               proposal["id"],
               :approve
             )

    assert Organizations.leadership_state(elected_organization).leader_character_id == invitee.id
  end

  test "leader departure cancels an unfinished election and appoints the default successor", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :council, "Succession Council")

    assert {:ok, member_role} =
             Organizations.add_role(organization, founder, %{
               code: "delegate",
               title: "Delegate",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:ok, organization} =
             Organizations.configure_leadership_selection(
               organization,
               founder,
               "member_election"
             )

    assert {:ok, %{proposal: proposal}} =
             Organizations.open_leadership_election(organization, founder, invitee)

    assert {:ok, departing_membership} = Organizations.leave_organization(organization, founder)
    assert departing_membership.status == :left

    reloaded_organization = Organizations.get_organization!(organization.id)
    leadership = Organizations.leadership_state(reloaded_organization)

    assert leadership.leader_character_id == invitee.id
    assert is_nil(leadership.open_election)

    [cancelled_proposal] = reloaded_organization.metadata["governance_proposals"]
    assert cancelled_proposal["id"] == proposal["id"]
    assert cancelled_proposal["status"] == "cancelled"
    assert cancelled_proposal["cancellation_reason"] == "member_departed"

    leader_role = Enum.max_by(reloaded_organization.roles, & &1.rank)
    successor = Enum.find(reloaded_organization.memberships, &(&1.character_id == invitee.id))
    assert successor.role_id == leader_role.id
  end

  test "a configured vacant succession keeps the office empty when its leader leaves", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :guild, "Vacant Succession Guild")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:error, changeset} =
             Organizations.configure_leader_exit_succession(organization, invitee, "vacant")

    assert %{status: ["role lacks required permission manage_roles"]} = errors_on(changeset)

    assert {:error, changeset} =
             Organizations.configure_leader_exit_succession(organization, founder, "rotation")

    assert %{status: ["leader exit succession is invalid"]} = errors_on(changeset)

    assert {:ok, configured_organization} =
             Organizations.configure_leader_exit_succession(organization, founder, "vacant")

    assert Organizations.succession_state(configured_organization) == %{on_leader_exit: "vacant"}

    assert {:ok, departing_membership} = Organizations.leave_organization(organization, founder)
    assert departing_membership.status == :left

    reloaded_organization = Organizations.get_organization!(organization.id)
    assert Organizations.leadership_state(reloaded_organization).leader_character_id == nil

    remaining_membership =
      Enum.find(reloaded_organization.memberships, &(&1.character_id == invitee.id))

    assert remaining_membership.role_id == member_role.id
  end

  test "a sole departing leader leaves a durable vacant leadership state", %{founder: founder} do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(founder, :guild, "Quiet Guild")

    assert {:ok, departing_membership} = Organizations.leave_organization(organization, founder)
    assert departing_membership.status == :left

    reloaded_organization = Organizations.get_organization!(organization.id)
    assert Organizations.leadership_state(reloaded_organization).leader_character_id == nil
  end

  test "treasury dividends split real balances and ledger entries by durable ownership shares", %{
    realm: realm,
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, _realm_treasury} = Economy.ensure_treasury_account(realm, 200)

    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :company, "Dividend Company")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, founder, 100)

    assert {:ok, %{treasury_account: funded_treasury}} =
             Organizations.deposit_to_treasury(organization, founder, 100)

    assert funded_treasury.current_balance == 100

    assert {:ok, organization} =
             Organizations.assign_treasury_share(organization, founder, founder, 2_500)

    assert {:ok, organization} =
             Organizations.assign_treasury_share(organization, founder, invitee, 5_000)

    assert {:ok, %{allocations: allocations, treasury_account: paid_treasury, transfer: transfer}} =
             Organizations.distribute_treasury_dividend(organization, founder, 80)

    assert Enum.sort(Enum.map(allocations, &{&1.character_id, &1.amount})) ==
             Enum.sort([{founder.id, 20}, {invitee.id, 40}])

    assert paid_treasury.current_balance == 40
    assert Enum.sort(Enum.map(transfer.ledger_entries, & &1.amount)) == [20, 40]

    assert Enum.all?(transfer.ledger_entries, fn entry ->
             entry.metadata["source"] == "organization_treasury_dividend" and
               entry.metadata["gross_amount"] == 80 and
               entry.metadata["organization_retained_amount"] == 20
           end)

    {:ok, founder_account} = Economy.ensure_character_account(founder)
    {:ok, invitee_account} = Economy.ensure_character_account(invitee)
    assert Economy.get_account!(founder_account.id).current_balance == 20
    assert Economy.get_account!(invitee_account.id).current_balance == 40
  end

  test "member treasury referendums block direct payouts and settle one real majority-approved transfer",
       %{
         realm: realm,
         founder: founder,
         invitee: invitee
       } do
    assert {:ok, _realm_treasury} = Economy.ensure_treasury_account(realm, 100)

    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :council, "Referendum Council")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)
    assert {:ok, _grant} = Economy.grant_from_treasury(realm, founder, 60)

    assert {:ok, %{treasury_account: funded_treasury}} =
             Organizations.deposit_to_treasury(organization, founder, 40)

    assert funded_treasury.current_balance == 40

    assert {:ok, organization} =
             Organizations.configure_treasury_decision(organization, founder, "member_referendum")

    assert Organizations.treasury_policy_state(organization).decision == "member_referendum"

    assert {:error, changeset} =
             Organizations.withdraw_from_treasury(organization, founder, invitee, 1)

    assert %{status: ["treasury spending requires a member referendum"]} = errors_on(changeset)

    assert {:ok, %{proposal: proposal}} =
             Organizations.propose_treasury_withdrawal(organization, founder, invitee, 15)

    assert proposal["kind"] == "treasury_withdrawal"
    assert Enum.sort(proposal["voter_character_ids"]) == Enum.sort([founder.id, invitee.id])

    assert {:ok, %{resolution: :pending}} =
             Organizations.cast_treasury_vote(organization, founder, proposal["id"], :approve)

    assert {:error, changeset} =
             Organizations.cast_treasury_vote(organization, founder, proposal["id"], :approve)

    assert %{status: ["member has already voted in this treasury referendum"]} =
             errors_on(changeset)

    assert {:ok, %{resolution: :accepted, treasury_account: paid_treasury, transfer: transfer}} =
             Organizations.cast_treasury_vote(organization, invitee, proposal["id"], :approve)

    assert paid_treasury.current_balance == 25
    [ledger_entry] = transfer.ledger_entries
    assert ledger_entry.metadata["source"] == "organization_treasury_referendum"
    assert ledger_entry.metadata["proposal_id"] == proposal["id"]

    reloaded_organization = Organizations.get_organization!(organization.id)
    assert Organizations.treasury_policy_state(reloaded_organization).open_referendum == nil

    [settled_proposal | _rest] = reloaded_organization.metadata["governance_proposals"]
    assert settled_proposal["id"] == proposal["id"]
    assert settled_proposal["status"] == "accepted"
    assert settled_proposal["ledger_entry_ids"] == [ledger_entry.id]

    {:ok, invitee_account} = Economy.ensure_character_account(invitee)
    assert Economy.get_account!(invitee_account.id).current_balance == 15
  end

  test "a member departure cancels their open treasury referendum ballot", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(founder, :council, "Quorum Council")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:ok, organization} =
             Organizations.configure_treasury_decision(organization, founder, "member_referendum")

    assert {:ok, %{proposal: proposal}} =
             Organizations.propose_treasury_withdrawal(organization, founder, invitee, 5)

    assert {:ok, _membership} = Organizations.leave_organization(organization, invitee)

    reloaded_organization = Organizations.get_organization!(organization.id)
    assert Organizations.treasury_policy_state(reloaded_organization).open_referendum == nil

    [cancelled_proposal | _rest] = reloaded_organization.metadata["governance_proposals"]
    assert cancelled_proposal["id"] == proposal["id"]
    assert cancelled_proposal["status"] == "cancelled"
    assert cancelled_proposal["cancellation_reason"] == "member_departed"
  end

  test "a role payout limit routes larger treasury spending through the member referendum", %{
    realm: realm,
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, _realm_treasury} = Economy.ensure_treasury_account(realm, 100)

    assert {:ok, %{organization: organization, role: leader_role, member_role: member_role}} =
             Organizations.create_organization(founder, :council, "Limited Council")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)
    assert {:ok, _grant} = Economy.grant_from_treasury(realm, founder, 30)
    assert {:ok, _funding} = Organizations.deposit_to_treasury(organization, founder, 30)

    assert {:ok, limited_leader_role} =
             Organizations.configure_treasury_role_payout_limit(
               organization,
               founder,
               leader_role,
               10
             )

    assert Organizations.treasury_role_payout_limit(limited_leader_role) == 10

    assert {:ok, %{treasury_account: paid_treasury}} =
             Organizations.withdraw_from_treasury(organization, founder, invitee, 10)

    assert paid_treasury.current_balance == 20

    assert {:error, changeset} =
             Organizations.withdraw_from_treasury(organization, founder, invitee, 11)

    assert %{status: ["treasury spending requires a member referendum"]} = errors_on(changeset)

    assert {:ok, %{proposal: proposal}} =
             Organizations.propose_treasury_withdrawal(organization, founder, invitee, 11)

    assert {:ok, %{resolution: :pending}} =
             Organizations.cast_treasury_vote(organization, founder, proposal["id"], :approve)

    assert {:ok, %{resolution: :accepted, treasury_account: settled_treasury}} =
             Organizations.cast_treasury_vote(organization, invitee, proposal["id"], :approve)

    assert settled_treasury.current_balance == 9
  end

  test "organization treasury is a closed-ledger account with role-gated payouts", %{
    realm: realm,
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, _realm_treasury} = Economy.ensure_treasury_account(realm, 100)

    assert {:ok,
            %{
              organization: organization,
              treasury_account: organization_account,
              role: leader_role
            }} =
             Organizations.create_organization(founder, :guild, "Ledger Keepers")

    assert organization_account.owner_type == :organization
    assert organization_account.current_balance == 0
    assert organization_account.metadata["organization_id"] == organization.id
    assert "manage_treasury" in leader_role.permissions

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, founder, 60)

    assert {:ok, %{treasury_account: funded_treasury, transfer: deposit}} =
             Organizations.deposit_to_treasury(organization, founder, 40)

    assert funded_treasury.current_balance == 40
    assert deposit.credit_account.id == funded_treasury.id
    [deposit_entry] = deposit.ledger_entries
    assert deposit_entry.metadata["source"] == "organization_treasury_deposit"

    assert {:ok, member_role} =
             Organizations.add_role(organization, founder, %{
               code: "member",
               title: "Member",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, founder, invitee, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    assert {:error, changeset} =
             Organizations.withdraw_from_treasury(organization, invitee, invitee, 1)

    assert %{status: ["role lacks required permission manage_treasury"]} = errors_on(changeset)

    assert {:ok, %{treasury_account: paid_treasury, transfer: withdrawal}} =
             Organizations.withdraw_from_treasury(organization, founder, invitee, 15)

    assert paid_treasury.current_balance == 25
    assert withdrawal.debit_account.id == organization_account.id
    [withdrawal_entry] = withdrawal.ledger_entries
    assert withdrawal_entry.metadata["source"] == "organization_treasury_withdrawal"

    {:ok, invitee_account} = Economy.ensure_character_account(invitee)
    assert Economy.get_account!(invitee_account.id).current_balance == 15
  end

  defp fast_travel_organization_fixture(founder, invitee, city, tower) do
    {:ok,
     %{
       organization: organization,
       treasury_account: treasury_account
     }} =
      Organizations.create_organization(founder, :cult, "Toll Passage", %{
        fast_travel_enabled: true,
        linked_location_ids: [city.id, tower.id]
      })

    {:ok, travel_role} =
      Organizations.add_role(organization, founder, %{
        code: "passage-bearer",
        title: "Passage Bearer",
        rank: 10,
        permissions: ["grant_fast_travel"]
      })

    {:ok, invitation} =
      Organizations.invite_member(organization, founder, invitee, travel_role)

    {:ok, _membership} = Organizations.accept_invitation(invitation, invitee)

    %{organization: organization, treasury_account: treasury_account}
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %TelegramIdentity{account_id: account.id}
    |> TelegramIdentity.changeset(%{
      telegram_user_id: System.unique_integer([:positive]),
      telegram_username: handle,
      first_name: name,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
