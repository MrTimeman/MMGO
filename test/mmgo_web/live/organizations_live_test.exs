defmodule MMGOWeb.OrganizationsLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Organizations
  alias MMGO.Organizations.Membership
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    {:ok, the_tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 100,
        y: 100,
        safe_zone: false
      })

    {:ok, %{challenger: challenger, opponent: opponent}} = Play.setup_demo_session()

    %{
      realm: realm,
      city: city,
      challenger: challenger,
      opponent: opponent,
      the_tower: the_tower
    }
  end

  defp session_conn(conn, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, character.account_id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  test "unauthenticated visitors are redirected to /play", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/orgs")
  end

  test "a character at the Tower (not a city) is redirected to the map with an in-world flash", %{
    conn: conn,
    challenger: challenger,
    the_tower: the_tower
  } do
    challenger
    |> Character.travel_changeset(%{current_location_id: the_tower.id})
    |> Repo.update!()

    conn = session_conn(conn, challenger)

    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} = live(conn, ~p"/orgs")
    assert flash["error"] =~ "нужно находиться в городе"
  end

  test "a character in a city (the demo starting location) mounts normally", %{
    conn: conn,
    challenger: challenger
  } do
    conn = session_conn(conn, challenger)

    {:ok, _view, html} = live(conn, ~p"/orgs")

    assert html =~ "Организации"
  end

  test "index renders after a demo session with the create form", %{
    conn: conn,
    challenger: challenger
  } do
    conn = session_conn(conn, challenger)

    {:ok, view, html} = live(conn, ~p"/orgs")

    assert html =~ "Организации"
    assert has_element?(view, "#org-create-form")
    assert has_element?(view, "#org-invitations")
  end

  test "founding an organization shows it in the list", %{conn: conn, challenger: challenger} do
    conn = session_conn(conn, challenger)
    {:ok, view, _html} = live(conn, ~p"/orgs")

    view
    |> form("#org-create-form-body", %{
      "organization" => %{"name" => "Order of the Ember", "kind" => "guild"}
    })
    |> render_submit()

    assert has_element?(view, "#org-list", "Order of the Ember")
    assert has_element?(view, "#org-list", "Гильдия")
  end

  test "detail page shows members and roles", %{conn: conn, challenger: challenger} do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    conn = session_conn(conn, challenger)
    {:ok, view, html} = live(conn, ~p"/orgs/#{organization.id}")

    assert html =~ "Silver Hand"
    assert has_element?(view, "#org-members", challenger.name)
    assert has_element?(view, "#org-roles", "Guildmaster")
  end

  test "a scoped founder can fund and pay from the real organization treasury", %{
    conn: conn,
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Ledger Keepers")

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, challenger, 50)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    opponent_balance = Economy.get_account!(opponent_account.id).current_balance
    opponent_handle = Accounts.get_account!(opponent.account_id).handle

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-treasury-balance", "0")
    assert has_element?(view, "#org-treasury-deposit-form")
    assert has_element?(view, "#org-treasury-withdrawal-form")

    view
    |> form("#org-treasury-deposit-form", %{"treasury_deposit" => %{"amount" => "20"}})
    |> render_submit()

    assert has_element?(view, "#org-treasury-balance", "20")
    assert has_element?(view, "#org-treasury-last-entry", "вклад")

    view
    |> form("#org-treasury-withdrawal-form", %{
      "treasury_withdrawal" => %{"handle" => opponent_handle, "amount" => "7"}
    })
    |> render_submit()

    assert has_element?(view, "#org-treasury-balance", "13")
    assert has_element?(view, "#org-treasury-last-entry", "выплата")
    assert Economy.get_account!(opponent_account.id).current_balance == opponent_balance + 7
  end

  test "a treasury manager configures a visible, taxed organization fast-travel toll", %{
    conn: conn,
    city: city,
    challenger: challenger,
    the_tower: the_tower
  } do
    challenger =
      challenger
      |> Character.travel_changeset(%{current_location_id: city.id})
      |> Repo.update!()

    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(challenger, :guild, "Toll Keepers", %{
               fast_travel_enabled: true,
               linked_location_ids: [city.id, the_tower.id]
             })

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-fast-travel")
    assert has_element?(view, "#org-fast-travel-toll-config")
    assert has_element?(view, "#org-fast-travel-toll-form")

    view
    |> form("#org-fast-travel-toll-form", %{
      "fast_travel_toll" => %{
        "origin_location_id" => city.id,
        "destination_location_id" => the_tower.id,
        "amount" => "20"
      }
    })
    |> render_submit()

    assert has_element?(view, "#org-fast-travel-toll-#{city.id}-#{the_tower.id}", "20")
    assert has_element?(view, "#org-fast-travel-#{the_tower.id}", "20")
  end

  test "scoped members approve a treasury referendum before its real payout", %{
    conn: conn,
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization, member_role: member_role}} =
      Organizations.create_organization(challenger, :council, "Referendum Council")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, challenger, opponent, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, opponent)
    assert {:ok, _grant} = Economy.grant_from_treasury(realm, challenger, 50)

    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    opponent_balance = Economy.get_account!(opponent_account.id).current_balance
    opponent_handle = Accounts.get_account!(opponent.account_id).handle

    {:ok, founder_view, _html} =
      live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(founder_view, "#org-treasury-policy-form")

    founder_view
    |> form("#org-treasury-policy-form", %{
      "treasury_policy" => %{"decision" => "member_referendum"}
    })
    |> render_submit()

    assert has_element?(founder_view, "#org-treasury-decision-mode", "референдум участников")

    founder_view
    |> form("#org-treasury-deposit-form", %{"treasury_deposit" => %{"amount" => "20"}})
    |> render_submit()

    founder_view
    |> form("#org-treasury-withdrawal-form", %{
      "treasury_withdrawal" => %{"handle" => opponent_handle, "amount" => "7"}
    })
    |> render_submit()

    assert has_element?(founder_view, "#org-treasury-referendum")
    assert has_element?(founder_view, "#org-treasury-referendum-summary", opponent.name)
    assert has_element?(founder_view, "#org-treasury-referendum-approve")

    founder_view
    |> element("#org-treasury-referendum-approve")
    |> render_click()

    assert has_element?(founder_view, "#org-treasury-referendum-vote-recorded")

    {:ok, opponent_view, _html} =
      live(session_conn(build_conn(), opponent), ~p"/orgs/#{organization.id}")

    assert has_element?(opponent_view, "#org-treasury-referendum-approve")

    opponent_view
    |> element("#org-treasury-referendum-approve")
    |> render_click()

    assert has_element?(opponent_view, "#org-treasury-balance", "13")
    assert has_element?(opponent_view, "#org-treasury-last-entry", "референдум")
    refute has_element?(opponent_view, "#org-treasury-referendum")
    assert Economy.get_account!(opponent_account.id).current_balance == opponent_balance + 7
  end

  test "a treasury role limit routes an oversized scoped payout into a referendum", %{
    conn: conn,
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :council, "Limited Council")

    leader_role = Enum.max_by(organization.roles, & &1.rank)
    assert {:ok, _grant} = Economy.grant_from_treasury(realm, challenger, 30)
    opponent_handle = Accounts.get_account!(opponent.account_id).handle

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-treasury-role-limit-form")

    view
    |> form("#org-treasury-role-limit-form", %{
      "treasury_role_limit" => %{"role_id" => leader_role.id, "limit" => "5"}
    })
    |> render_submit()

    assert has_element?(view, "#org-treasury-role-limit-#{leader_role.id}", "до 5")
    assert has_element?(view, "#org-treasury-actor-limit", "до 5")

    view
    |> form("#org-treasury-deposit-form", %{"treasury_deposit" => %{"amount" => "20"}})
    |> render_submit()

    view
    |> form("#org-treasury-withdrawal-form", %{
      "treasury_withdrawal" => %{"handle" => opponent_handle, "amount" => "7"}
    })
    |> render_submit()

    assert has_element?(view, "#org-treasury-referendum", "7")
    assert has_element?(view, "#org-treasury-balance", "20")
  end

  test "a leader can add a bounded role through the scoped organization page", %{
    conn: conn,
    challenger: challenger
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    view
    |> form("#org-role-form", %{
      "role" => %{
        "title" => "Scout",
        "rank" => "25",
        "permissions" => ["invite_members"]
      }
    })
    |> render_submit()

    updated_organization = Organizations.get_organization!(organization.id)
    scout = Enum.find(updated_organization.roles, &(&1.title == "Scout"))

    assert scout.rank == 25
    assert scout.permissions == ["invite_members"]
    assert has_element?(view, "#org-role-#{scout.id}", "Scout")
  end

  test "members can select and elect a new organization leader through the scoped UI", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :council, "Elective Council")

    assert {:ok, member_role} =
             Organizations.add_role(organization, challenger, %{
               code: "delegate",
               title: "Delegate",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, challenger, opponent, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, opponent)

    {:ok, founder_view, _html} =
      live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(founder_view, "#org-governance")
    assert has_element?(founder_view, "#org-governance-form")

    founder_view
    |> form("#org-governance-form", %{"leadership" => %{"selection" => "member_election"}})
    |> render_submit()

    assert has_element?(founder_view, "#org-leadership-mode", "выборы участников")
    assert has_element?(founder_view, "#org-election-nominations")

    founder_view
    |> element("#org-nominate-#{opponent.id}")
    |> render_click()

    assert has_element?(founder_view, "#org-open-election")
    assert has_element?(founder_view, "#org-election-candidate", opponent.name)

    founder_view
    |> element("#org-election-approve")
    |> render_click()

    assert has_element?(founder_view, "#org-election-vote-recorded")

    {:ok, opponent_view, _html} =
      live(session_conn(build_conn(), opponent), ~p"/orgs/#{organization.id}")

    assert has_element?(opponent_view, "#org-election-approve")

    opponent_view
    |> element("#org-election-approve")
    |> render_click()

    assert has_element?(opponent_view, "#org-current-leader", opponent.name)

    assert Organizations.leadership_state(Organizations.get_organization!(organization.id)).leader_character_id ==
             opponent.id
  end

  test "the founder appoints a new organization leader through the scoped UI", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    assert {:ok, %{organization: organization, member_role: member_role}} =
             Organizations.create_organization(challenger, :guild, "Founder Registry")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, challenger, opponent, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, opponent)

    {:ok, founder_view, _html} =
      live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(founder_view, "#org-founder-appointments")

    founder_view
    |> element("#org-appoint-#{opponent.id}")
    |> render_click()

    assert has_element?(founder_view, "#org-current-leader", opponent.name)

    assert Organizations.leadership_state(Organizations.get_organization!(organization.id)).leader_character_id ==
             opponent.id
  end

  test "a manager configures the visible leader-exit succession through the scoped UI", %{
    conn: conn,
    challenger: challenger
  } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(challenger, :guild, "Succession Registry")

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-succession-form")

    view
    |> form("#org-succession-form", %{"succession" => %{"on_leader_exit" => "vacant"}})
    |> render_submit()

    assert has_element?(view, "#org-succession-mode", "пост остаётся вакантным")

    assert Organizations.succession_state(Organizations.get_organization!(organization.id)).on_leader_exit ==
             "vacant"
  end

  test "a founder can open enrollment and another scoped player can join from the registry", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Open Registry")

    {:ok, founder_view, _html} =
      live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(founder_view, "#org-membership-form")

    founder_view
    |> form("#org-membership-form", %{"membership" => %{"admission" => "open"}})
    |> render_submit()

    assert has_element?(founder_view, "#org-membership-mode", "открытое вступление")

    {:ok, opponent_view, _html} = live(session_conn(build_conn(), opponent), ~p"/orgs")

    assert has_element?(opponent_view, "#org-join-#{organization.id}")

    opponent_view
    |> element("#org-join-#{organization.id}")
    |> render_click()

    assert has_element?(opponent_view, "#org-list", "Open Registry")

    reloaded_organization = Organizations.get_organization!(organization.id)

    assert Enum.any?(
             reloaded_organization.memberships,
             &(&1.character_id == opponent.id and &1.role.code == "open-member")
           )
  end

  test "a treasury manager can assign shares and select weighted leadership elections", %{
    conn: conn,
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization, member_role: member_role}} =
      Organizations.create_organization(challenger, :company, "Share Company")

    assert {:ok, invitation} =
             Organizations.invite_member(organization, challenger, opponent, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, opponent)

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-treasury-ownership")
    assert has_element?(view, "#org-treasury-share-form")

    view
    |> form("#org-treasury-share-form", %{
      "treasury_share" => %{"character_id" => opponent.id, "percent" => "60"}
    })
    |> render_submit()

    assert has_element?(view, "#org-treasury-share-#{opponent.id}", "60%")

    assert {:ok, _grant} = Economy.grant_from_treasury(realm, challenger, 50)

    view
    |> form("#org-treasury-deposit-form", %{"treasury_deposit" => %{"amount" => "50"}})
    |> render_submit()

    assert has_element?(view, "#org-treasury-balance", "50")
    assert has_element?(view, "#org-treasury-dividend-form")

    view
    |> form("#org-treasury-dividend-form", %{"treasury_dividend" => %{"amount" => "50"}})
    |> render_submit()

    assert has_element?(view, "#org-treasury-balance", "20")

    view
    |> form("#org-governance-form", %{
      "leadership" => %{"selection" => "share_weighted_election"}
    })
    |> render_submit()

    assert has_element?(view, "#org-leadership-mode", "выборы по долям казны")
  end

  test "organization managers negotiate and accept an alliance through the scoped UI", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: source_organization}} =
      Organizations.create_organization(challenger, :guild, "Source Guild")

    {:ok, %{organization: target_organization}} =
      Organizations.create_organization(opponent, :company, "Target Company")

    {:ok, source_view, _html} =
      live(session_conn(conn, challenger), ~p"/orgs/#{source_organization.id}")

    assert has_element?(source_view, "#org-diplomacy-form")

    source_view
    |> form("#org-diplomacy-form", %{
      "diplomacy" => %{
        "target_organization_id" => target_organization.id,
        "kind" => "alliance"
      }
    })
    |> render_submit()

    target_state =
      Organizations.diplomacy_state(Organizations.get_organization!(target_organization.id))

    [proposal] = target_state.incoming_requests

    {:ok, target_view, _html} =
      live(session_conn(build_conn(), opponent), ~p"/orgs/#{target_organization.id}")

    assert has_element?(target_view, "#org-diplomacy-request-#{proposal["id"]}")

    target_view
    |> element("#org-diplomacy-accept-#{proposal["id"]}")
    |> render_click()

    assert has_element?(target_view, "#org-diplomacy-relationships", "Source Guild")

    assert Organizations.diplomacy_state(Organizations.get_organization!(source_organization.id)).relationships !=
             []
  end

  test "a member without organization permissions cannot see management forms", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    assert {:ok, member_role} =
             Organizations.add_role(organization, challenger, %{
               code: "member",
               title: "Member",
               rank: 10,
               permissions: []
             })

    assert {:ok, invitation} =
             Organizations.invite_member(organization, challenger, opponent, member_role)

    assert {:ok, _membership} = Organizations.accept_invitation(invitation, opponent)

    {:ok, view, _html} = live(session_conn(conn, opponent), ~p"/orgs/#{organization.id}")

    refute has_element?(view, "#org-role-management")
    refute has_element?(view, "#org-invite-form")
    assert has_element?(view, "#org-treasury-deposit-form")
    refute has_element?(view, "#org-treasury-withdrawal-form")
  end

  test "non-members are redirected away from a detail page", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    conn = session_conn(conn, opponent)

    assert {:error, {:live_redirect, %{to: "/orgs"}}} = live(conn, ~p"/orgs/#{organization.id}")
  end

  test "invite flow: founder invites another character, invitee sees and accepts it", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    opponent_account = Accounts.get_account!(opponent.account_id)

    founder_conn = session_conn(conn, challenger)
    {:ok, founder_view, _html} = live(founder_conn, ~p"/orgs/#{organization.id}")

    founder_view
    |> form("#org-invite-form-body", %{
      "invite" => %{
        "handle" => opponent_account.handle,
        "role_id" => hd(organization.roles).id
      }
    })
    |> render_submit()

    invitee_conn = session_conn(build_conn(), opponent)
    {:ok, invitee_view, html} = live(invitee_conn, ~p"/orgs")

    assert html =~ "Silver Hand"
    assert has_element?(invitee_view, "#org-invitations", "Silver Hand")

    invitation =
      Organizations.pending_invitations_for_character(opponent.id) |> List.first()

    invitee_view
    |> element(
      "button[phx-click='accept_invitation'][phx-value-invitation_id='#{invitation.id}']"
    )
    |> render_click()

    assert has_element?(invitee_view, "#org-list", "Silver Hand")

    reloaded = Organizations.get_organization!(organization.id)

    assert Enum.any?(
             reloaded.memberships,
             &(&1.character_id == opponent.id and &1.status == :active)
           )
  end

  test "leaving from the organization detail durably closes the scoped membership", %{
    conn: conn,
    challenger: challenger
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Leaving Hand")

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")
    assert has_element?(view, "#org-leave")

    assert {:error, {:live_redirect, %{to: "/orgs"}}} =
             view |> element("#org-leave") |> render_click()

    assert Repo.get_by!(Membership,
             organization_id: organization.id,
             character_id: challenger.id
           ).status == :left
  end

  test "an eligible member can use a linked organization fast-travel route", %{
    conn: conn,
    challenger: challenger,
    city: city,
    the_tower: the_tower
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Wayfarers", %{
        fast_travel_enabled: true,
        linked_location_ids: [city.id, the_tower.id]
      })

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/orgs/#{organization.id}")

    assert has_element?(view, "#org-fast-travel-#{the_tower.id}")

    assert {:error, {:live_redirect, %{to: "/map"}}} =
             view |> element("#org-fast-travel-#{the_tower.id}") |> render_click()

    assert Repo.get!(Character, challenger.id).current_location_id == the_tower.id
  end
end
