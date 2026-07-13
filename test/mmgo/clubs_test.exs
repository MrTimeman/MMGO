defmodule MMGO.ClubsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Enrollment
  alias MMGO.Clubs
  alias MMGO.Clubs.{Club, Membership}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.Resolution
  alias MMGO.Academia.Professor
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Travel.Clock
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

    founder = character_fixture(realm, city, "founder", "Founder")
    invitee = character_fixture(realm, city, "invitee", "Invitee")
    outsider = character_fixture(realm, city, "outsider", "Outsider")

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 10_000)
    enroll_active_academy_core(founder, realm)
    enroll(invitee, realm, :basic_education)
    {:ok, _funding} = Economy.grant_from_treasury(realm, founder, 1_000)

    %{realm: realm, city: city, founder: founder, invitee: invitee, outsider: outsider}
  end

  test "create_club/2 charges an active Academy Core founder into the Academy treasury", %{
    realm: realm,
    founder: founder
  } do
    {:ok, founder_account} = Economy.ensure_character_account(founder)
    academy_treasury = Economy.treasury_account_for_realm(realm.id)
    starting_founder_balance = founder_account.current_balance
    starting_treasury_balance = academy_treasury.current_balance

    assert {:ok, %{club: club, membership: membership}} =
             Clubs.create_club(founder, %{club_type: :general_interest, name: "History Society"})

    assert club.club_type == :general_interest
    assert membership.role == :leader
    assert membership.status == :active
    assert Clubs.list_clubs_for_character(founder.id) |> Enum.any?(&(&1.id == club.id))

    assert Economy.get_account!(founder_account.id).current_balance ==
             starting_founder_balance - Clubs.club_founding_fee()

    assert Economy.get_account!(academy_treasury.id).current_balance ==
             starting_treasury_balance + Clubs.club_founding_fee()

    fee_entry =
      Economy.list_ledger_entries_for_account(academy_treasury.id)
      |> Enum.find(&(&1.metadata["source"] == "academy_club_founding_fee"))

    assert fee_entry.entry_type == :purchase
    assert fee_entry.amount == Clubs.club_founding_fee()
    assert fee_entry.debit_account_id == founder_account.id
    assert fee_entry.credit_account_id == academy_treasury.id
    assert fee_entry.metadata["academy_destination"] == "realm_treasury"
    assert fee_entry.metadata["club_id"] == club.id
  end

  test "create_club/2 rejects founders who are not active Academy Core students or Professors", %{
    realm: realm,
    city: city,
    outsider: outsider
  } do
    assert {:error, changeset} =
             Clubs.create_club(outsider, %{club_type: :dueling, name: "Duelists"})

    assert %{status: ["only active Academy Core students or active Professors can found clubs"]} =
             errors_on(changeset)

    basic_education_alumnus =
      character_fixture(realm, city, "basic-education-alumnus", "Basic Education Alumnus")

    enroll(basic_education_alumnus, realm, :basic_education)

    assert {:error, changeset} =
             Clubs.create_club(basic_education_alumnus, %{
               club_type: :dueling,
               name: "Basic Education Duelists"
             })

    assert %{status: ["only active Academy Core students or active Professors can found clubs"]} =
             errors_on(changeset)
  end

  test "create_club/2 permits an active Professor and charges the same Academy fee", %{
    realm: realm,
    city: city
  } do
    professor = character_fixture(realm, city, "club-professor", "Club Professor")
    professor_fixture(professor, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, professor, Clubs.club_founding_fee())

    assert {:ok, %{club: club}} =
             Clubs.create_club(professor, %{club_type: :research, name: "Faculty Colloquium"})

    assert club.founder_character_id == professor.id
  end

  test "create_club/2 rolls back the club when an eligible founder cannot pay", %{
    realm: realm,
    city: city
  } do
    unfunded_founder = character_fixture(realm, city, "unfunded-founder", "Unfunded Founder")
    enroll_active_academy_core(unfunded_founder, realm)

    assert {:error, changeset} =
             Clubs.create_club(unfunded_founder, %{
               club_type: :general_interest,
               name: "Unfunded Circle"
             })

    assert %{current_balance: ["is insufficient for this transfer"]} = errors_on(changeset)

    refute Repo.get_by(Club,
             realm_id: realm.id,
             founder_character_id: unfunded_founder.id,
             name: "Unfunded Circle"
           )
  end

  test "invite_member/3 and accept_invitation/2 create active membership", %{
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :research, name: "Researchers"})

    assert {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    assert invitation.status == :pending

    assert {:ok, %{membership: membership}} = Clubs.accept_invitation(invitation, invitee)
    assert membership.role == :member
    assert membership.status == :active
    assert Clubs.list_members(club) |> Enum.any?(&(&1.character_id == invitee.id))
  end

  test "reject_invitation/2 marks invitations rejected", %{founder: founder, invitee: invitee} do
    {:ok, %{club: club}} = Clubs.create_club(founder, %{club_type: :dueling, name: "Duelists"})
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)

    assert {:ok, updated_invitation} = Clubs.reject_invitation(invitation, invitee)
    assert updated_invitation.status == :rejected
  end

  test "leave_club/2 archives empty clubs and transfers leadership otherwise", %{
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: solo_club}} =
      Clubs.create_club(founder, %{club_type: :general_interest, name: "Solo Club"})

    assert {:ok, updated_club} = Clubs.leave_club(solo_club, founder)
    assert updated_club.status == :archived

    {:ok, %{club: group_club}} =
      Clubs.create_club(founder, %{club_type: :research, name: "Group Club"})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(group_club, founder, invitee)
    {:ok, _accepted} = Clubs.accept_invitation(invitation, invitee)

    assert {:ok, updated_group_club} = Clubs.leave_club(group_club, founder)
    assert updated_group_club.status == :active
    assert updated_group_club.founder_character_id == founder.id

    new_leader = Repo.get_by!(Membership, club_id: group_club.id, character_id: invitee.id)
    assert new_leader.role == :leader
  end

  test "research-session notes pay a contributor when a club member completes research", %{
    realm: realm,
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :research, name: "Shared Notes"})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)
    {:ok, event} = Clubs.create_event(club, %{kind: :research_session})

    assert {:ok, _attendance} = Clubs.attend_event(event, founder)
    assert {:ok, _attendance} = Clubs.attend_event(event, invitee)

    invitee_membership = Repo.get_by!(Membership, club_id: club.id, character_id: invitee.id)
    assert Clubs.research_contribution(invitee_membership).credits == 1

    invitee_xp_after_attendance = Repo.get!(Character, invitee.id).xp
    project_id = Ecto.UUID.generate()

    assert {:ok, [reward]} =
             Clubs.reward_research_contributors(
               %{id: project_id, character_id: founder.id, realm_id: realm.id},
               100
             )

    assert reward["character_id"] == invitee.id
    assert reward["research_note_credits"] == 1
    assert reward["xp_awarded"] == 5
    assert Repo.get!(Character, invitee.id).xp == invitee_xp_after_attendance + 5

    redeemed_membership = Repo.get_by!(Membership, club_id: club.id, character_id: invitee.id)
    assert Clubs.research_contribution(redeemed_membership).credits == 0
    assert redeemed_membership.metadata["research_project_rewards"][project_id]

    assert {:ok, []} =
             Clubs.reward_research_contributors(
               %{id: project_id, character_id: founder.id, realm_id: realm.id},
               100
             )
  end

  test "general-interest attendance creates reciprocal durable social ties", %{
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :general_interest, name: "Lore Circle"})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)
    {:ok, event} = Clubs.create_event(club, %{kind: :general_meeting})

    assert {:ok, _attendance} = Clubs.attend_event(event, founder)
    assert {:ok, _attendance} = Clubs.attend_event(event, invitee)

    founder_membership = Repo.get_by!(Membership, club_id: club.id, character_id: founder.id)
    invitee_membership = Repo.get_by!(Membership, club_id: club.id, character_id: invitee.id)

    assert Clubs.friendship_summary(founder_membership) == %{companions: 1, shared_events: 1}
    assert Clubs.friendship_summary(invitee_membership) == %{companions: 1, shared_events: 1}

    event_with_attendances = Clubs.list_events_for_club(club.id) |> List.first()

    invitee_attendance =
      event_with_attendances.attendances
      |> Enum.find(&(&1.character_id == invitee.id))

    assert invitee_attendance.metadata["social_ties_formed"] == 1
  end

  test "a finished no-wager club match completes its linked tournament event", %{
    realm: realm,
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} = Clubs.create_club(founder, %{club_type: :dueling, name: "Duelists"})
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)
    {:ok, event} = Clubs.create_event(club, %{kind: :duel_tournament})

    founder_xp = founder.xp
    invitee_xp = invitee.xp

    assert {:ok, _attendance} = Clubs.attend_event(event, founder)
    assert {:ok, _attendance} = Clubs.attend_event(event, invitee)
    assert Repo.get!(Character, founder.id).xp == founder_xp + 10
    assert Repo.get!(Character, invitee.id).xp == invitee_xp + 10

    assert {:ok, %{combat: combat}} =
             Combat.create_club_match(realm, %{
               participants: [
                 %{character_id: founder.id, side: "red", position: 0},
                 %{character_id: invitee.id, side: "blue", position: 0}
               ],
               metadata: %{club_event_id: event.id}
             })

    finished_combat =
      combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "red",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, completed_event} = Resolution.finalize(finished_combat)
    assert completed_event.status == :active
    assert completed_event.result_metadata["combat_id"] == combat.id
    assert completed_event.result_metadata["winner_side"] == "red"

    assert [%{"combat_id" => combat_id, "ladder_entries" => ladder_entries}] =
             completed_event.result_metadata["club_matches"]

    assert combat_id == combat.id

    assert Enum.any?(ladder_entries, fn entry ->
             entry["character_id"] == founder.id and entry["result"] == "win"
           end)

    founder_membership = Repo.get_by!(Membership, club_id: club.id, character_id: founder.id)
    invitee_membership = Repo.get_by!(Membership, club_id: club.id, character_id: invitee.id)
    current_year = Clock.world_time().year

    assert founder_membership.metadata["duel_ladder"] == %{
             "year" => current_year,
             "wins" => 1,
             "losses" => 0,
             "draws" => 0
           }

    assert invitee_membership.metadata["duel_ladder"] == %{
             "year" => current_year,
             "wins" => 0,
             "losses" => 1,
             "draws" => 0
           }

    ladder = Clubs.list_duel_ladder(club)

    assert [%{character_id: founder_id, rank: 1, wins: 1}, %{character_id: invitee_id, rank: 2}] =
             ladder

    assert founder_id == founder.id
    assert invitee_id == invitee.id

    assert {:ok, repeated_event} = Resolution.finalize(finished_combat)
    assert repeated_event.status == :active

    assert Repo.get_by!(Membership, club_id: club.id, character_id: founder.id).metadata[
             "duel_ladder"
           ]["wins"] == 1
  end

  test "a duelling tournament creates no-wager combat only after the challenged attendee consents",
       %{
         founder: founder,
         invitee: invitee
       } do
    {:ok, %{club: club}} = Clubs.create_club(founder, %{club_type: :dueling, name: "Duelists"})
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)
    {:ok, event} = Clubs.create_event(club, %{kind: :duel_tournament})
    assert {:ok, _attendance} = Clubs.attend_event(event, founder)
    assert {:ok, _attendance} = Clubs.attend_event(event, invitee)

    assert {:ok, %{challenge: challenge}} = Clubs.challenge_duel(event, founder, invitee)
    assert challenge["status"] == "pending"
    refute Combat.active_combat_for_character(invitee.id)

    assert {:ok, %{event: updated_event, challenge: accepted_challenge, combat: combat}} =
             Clubs.accept_duel_challenge(event, challenge["id"], invitee)

    assert combat.kind == :club_match
    assert combat.metadata["club_event_id"] == event.id
    assert accepted_challenge["status"] == "accepted"
    assert accepted_challenge["combat_id"] == combat.id
    assert updated_event.status == :active
  end

  test "ordinary club members cannot schedule a club event", %{
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} = Clubs.create_club(founder, %{club_type: :dueling, name: "Duelists"})
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)

    assert {:error, changeset} = Clubs.create_event(club, invitee, %{kind: :duel_tournament})

    assert %{status: ["club role lacks required permission schedule_events"]} =
             errors_on(changeset)

    assert {:ok, event} = Clubs.create_event(club, founder, %{kind: :duel_tournament})
    assert event.kind == :duel_tournament
  end

  test "the president grants officers real invitation and scheduling authority", %{
    realm: realm,
    city: city,
    founder: founder,
    invitee: invitee
  } do
    third_member = character_fixture(realm, city, "third-member", "Third Member")
    enroll(third_member, realm, :basic_education)

    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :general_interest, name: "Officers Circle"})

    join_club!(club, founder, invitee)

    assert {:ok, %{membership: officer_membership}} =
             Clubs.appoint_officer(club, founder, invitee)

    assert officer_membership.role == :officer

    club_with_officer = Clubs.get_club!(club.id)

    current_officer =
      Enum.find(club_with_officer.memberships, &(&1.character_id == invitee.id))

    assert Clubs.officer?(current_officer)
    assert Clubs.can?(club_with_officer, current_officer, "invite_members")
    assert Clubs.can?(club_with_officer, current_officer, "schedule_events")
    refute Clubs.can?(club_with_officer, current_officer, "manage_officers")

    assert {:ok, %{invitation: invitation}} = Clubs.invite_member(club, invitee, third_member)
    assert {:ok, _membership} = Clubs.accept_invitation(invitation, third_member)

    assert {:ok, event} =
             Clubs.create_event(club, invitee, %{kind: :general_meeting})

    assert event.kind == :general_meeting

    assert {:ok, %{membership: ordinary_membership}} =
             Clubs.revoke_officer(club, founder, invitee)

    assert ordinary_membership.role == :member

    assert {:error, changeset} =
             Clubs.create_event(club, invitee, %{kind: :general_meeting})

    assert %{status: ["club role lacks required permission schedule_events"]} =
             errors_on(changeset)
  end

  test "a member election snapshots voters and atomically transfers the presidency", %{
    realm: realm,
    city: city,
    founder: founder,
    invitee: invitee
  } do
    third_member = character_fixture(realm, city, "election-third", "Election Third")
    enroll(third_member, realm, :basic_education)

    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :research, name: "Election Circle"})

    join_club!(club, founder, invitee)
    join_club!(club, founder, third_member)

    assert %{selection: "member_election", president: president, open_election: nil} =
             Clubs.governance_state(Clubs.get_club!(club.id), founder.id)

    assert president.character_id == founder.id

    assert {:ok, %{proposal: proposal}} =
             Clubs.open_president_election(club, founder, invitee)

    assert proposal["voter_character_ids"] ==
             Enum.sort([founder.id, invitee.id, third_member.id])

    assert {:error, changeset} = Clubs.open_president_election(club, founder, third_member)
    assert %{status: ["a president election is already open"]} = errors_on(changeset)

    assert {:ok, %{resolution: :pending}} =
             Clubs.cast_president_vote(club, invitee, proposal["id"], :approve)

    assert {:error, changeset} =
             Clubs.cast_president_vote(club, invitee, proposal["id"], :approve)

    assert %{status: ["member has already voted in this president election"]} =
             errors_on(changeset)

    assert {:ok, %{proposal: resolved_proposal, resolution: :accepted}} =
             Clubs.cast_president_vote(club, third_member, proposal["id"], :approve)

    assert resolved_proposal["status"] == "accepted"

    reloaded_club = Clubs.get_club!(club.id)
    assert reloaded_club.founder_character_id == founder.id

    founder_membership =
      Enum.find(reloaded_club.memberships, &(&1.character_id == founder.id))

    invitee_membership =
      Enum.find(reloaded_club.memberships, &(&1.character_id == invitee.id))

    assert founder_membership.role == :member
    assert invitee_membership.role == :leader

    assert %{president: elected_president, open_election: nil} =
             Clubs.governance_state(reloaded_club, third_member.id)

    assert elected_president.character_id == invitee.id
  end

  test "a tied complete president election is rejected without changing offices", %{
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :dueling, name: "Tie Breakers"})

    join_club!(club, founder, invitee)

    assert {:ok, %{proposal: proposal}} =
             Clubs.open_president_election(club, founder, invitee)

    assert {:ok, %{resolution: :pending}} =
             Clubs.cast_president_vote(club, invitee, proposal["id"], :approve)

    assert {:ok, %{proposal: resolved_proposal, resolution: :rejected}} =
             Clubs.cast_president_vote(club, founder, proposal["id"], :reject)

    assert resolved_proposal["status"] == "rejected"

    reloaded_club = Clubs.get_club!(club.id)

    assert Enum.find(reloaded_club.memberships, &(&1.character_id == founder.id)).role == :leader
    assert Enum.find(reloaded_club.memberships, &(&1.character_id == invitee.id)).role == :member
  end

  test "departure cancels an election whose voter snapshot is no longer current", %{
    realm: realm,
    city: city,
    founder: founder,
    invitee: invitee
  } do
    third_member = character_fixture(realm, city, "departing-voter", "Departing Voter")
    enroll(third_member, realm, :basic_education)

    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{club_type: :expedition_planning, name: "Departure Circle"})

    join_club!(club, founder, invitee)
    join_club!(club, founder, third_member)

    assert {:ok, %{proposal: proposal}} =
             Clubs.open_president_election(club, founder, invitee)

    assert {:ok, _club} = Clubs.leave_club(club, third_member)

    reloaded_club = Clubs.get_club!(club.id)

    [cancelled_proposal] =
      reloaded_club.metadata["governance"]["proposals"]
      |> Enum.filter(&(&1["id"] == proposal["id"]))

    assert cancelled_proposal["status"] == "cancelled"
    assert cancelled_proposal["cancellation_reason"] == "member_departed"
    assert Clubs.governance_state(reloaded_club, founder.id).open_election == nil

    assert {:error, changeset} =
             Clubs.cast_president_vote(club, founder, proposal["id"], :approve)

    assert %{status: ["president election is not open"]} = errors_on(changeset)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 1, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp join_club!(club, inviter, invitee) do
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, inviter, invitee)
    {:ok, %{membership: membership}} = Clubs.accept_invitation(invitation, invitee)
    membership
  end

  defp enroll(character, realm, program_type) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: program_type,
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

  defp professor_fixture(character, realm) do
    %Professor{}
    |> Professor.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
