defmodule MMGO.Clubs do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Academia
  alias MMGO.Clubs.{Club, Event, EventAttendance, Invitation, Membership}
  alias MMGO.Combat, as: CombatContext
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.Participant, as: CombatParticipant
  alias MMGO.Economy
  alias MMGO.Notifications
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  @club_types [:general_interest, :dueling, :research, :expedition_planning]
  @club_governance_key "governance"
  @governance_proposals_key "proposals"
  @governance_proposal_history_limit 20
  @leadership_selection "member_election"
  @succession_rule "earliest_active_member"
  @officer_permissions ["invite_members", "schedule_events"]
  @president_permissions @officer_permissions ++ ["manage_officers"]
  @election_votes ["approve", "reject"]
  @research_note_share_percent 5
  @research_note_share_cap 5
  @expedition_route_plan_bonus_bps 1_000
  @club_founding_fee 10

  def list_active_clubs(realm_id) when is_binary(realm_id) do
    Repo.all(
      from club in Club,
        where: club.realm_id == ^realm_id and club.status == :active,
        order_by: [asc: club.inserted_at]
    )
  end

  def get_club!(id) do
    Club
    |> Repo.get!(id)
    |> Repo.preload(memberships: active_membership_query())
  end

  def list_clubs_for_character(character_id) when is_binary(character_id) do
    Club
    |> join(:inner, [club], membership in assoc(club, :memberships))
    |> where(
      [club, membership],
      membership.character_id == ^character_id and membership.status == :active
    )
    |> order_by([club, _membership], asc: club.inserted_at)
    |> Repo.all()
    |> Repo.preload(memberships: active_membership_query())
  end

  def list_members(%Club{} = club) do
    active_membership_query()
    |> where([membership], membership.club_id == ^club.id)
    |> Repo.all()
  end

  @doc "Returns the current game-year duel ladder for one club's active members."
  def list_duel_ladder(%Club{} = club) do
    active_membership_query()
    |> where([membership], membership.club_id == ^club.id)
    |> Repo.all()
    |> Enum.map(fn membership ->
      ladder = duel_ladder(membership, Clock.world_time().year)

      %{
        character: membership.character,
        character_id: membership.character_id,
        wins: ladder.wins,
        losses: ladder.losses,
        draws: ladder.draws,
        matches: ladder.wins + ladder.losses + ladder.draws
      }
    end)
    |> Enum.sort_by(fn entry ->
      {-entry.wins, entry.losses, -entry.draws, entry.character.name, entry.character_id}
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :rank, rank) end)
  end

  @doc "Returns one member's unredeemed research-club note credits."
  def research_contribution(%Membership{} = membership) do
    contribution = research_contribution_metadata(membership.metadata || %{})

    %{
      credits: nonnegative_integer(Map.get(contribution, "credits")),
      last_event_id: Map.get(contribution, "last_event_id"),
      last_contributed_at: Map.get(contribution, "last_contributed_at")
    }
  end

  @doc "Returns one member's unused expedition-planning briefing credits."
  def expedition_plan_contribution(%Membership{} = membership) do
    plan = expedition_plan_metadata(membership.metadata || %{})

    %{
      credits: nonnegative_integer(Map.get(plan, "credits")),
      last_event_id: Map.get(plan, "last_event_id"),
      last_prepared_at: Map.get(plan, "last_prepared_at")
    }
  end

  @doc "Summarizes the durable social ties created through general-interest club meetings."
  def friendship_summary(%Membership{} = membership) do
    friendships = friendship_metadata(membership.metadata || %{})

    %{
      companions: map_size(friendships),
      shared_events:
        friendships
        |> Map.values()
        |> Enum.map(fn tie ->
          if(is_map(tie), do: nonnegative_integer(Map.get(tie, "shared_events")), else: 0)
        end)
        |> Enum.sum()
    }
  end

  @doc "Returns whether an active membership holds the club president office."
  def president?(%Membership{status: :active, role: :leader}), do: true
  def president?(_membership), do: false

  @doc "Returns whether an active membership is a club officer."
  def officer?(%Membership{status: :active, role: :officer}), do: true
  def officer?(_membership), do: false

  @doc "Lists the server-enforced permissions for one active club membership."
  def membership_permissions(%Club{} = club, %Membership{} = membership) do
    cond do
      president?(membership) -> @president_permissions
      officer?(membership) -> officer_permissions(club)
      true -> []
    end
  end

  def membership_permissions(_club, _membership), do: []

  @doc "Checks one club permission without trusting any client-owned role data."
  def can?(%Club{} = club, %Membership{} = membership, permission) when is_binary(permission) do
    permission in membership_permissions(club, membership)
  end

  def can?(_club, _membership, _permission), do: false

  @doc "Returns the club's safe governance view for a scoped member or visitor."
  def governance_state(%Club{} = club, actor_id \\ nil) do
    memberships = active_memberships_for_state(club)
    president = Enum.find(memberships, &president?/1)
    officers = Enum.filter(memberships, &officer?/1)

    open_election =
      club.metadata
      |> governance_proposals()
      |> Enum.find(
        &(Map.get(&1, "kind") == "president_election" and Map.get(&1, "status") == "open")
      )
      |> election_summary(memberships, actor_id)

    %{
      selection: @leadership_selection,
      president: president,
      officers: officers,
      officer_permissions: officer_permissions(club),
      candidate_memberships: memberships,
      open_election: open_election
    }
  end

  def pending_invitations_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from invitation in Invitation,
        where: invitation.invitee_character_id == ^character_id and invitation.status == :pending,
        order_by: [asc: invitation.inserted_at],
        preload: [:club, :inviter_character]
    )
  end

  @doc "Returns the fixed Academy fee charged to found one club."
  def club_founding_fee, do: @club_founding_fee

  def create_club(%Character{} = founder, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    club_type = normalize_club_type(attrs["club_type"] || :general_interest)
    name = attrs["name"] || "#{founder.name}'s Club"

    Repo.transaction(fn ->
      founder = lock_character!(founder.id)
      validate_club_creation!(founder, club_type)

      club =
        %Club{}
        |> Club.changeset(%{
          realm_id: founder.realm_id,
          founder_character_id: founder.id,
          name: name,
          club_type: club_type,
          status: :active,
          metadata: club_metadata_for(attrs)
        })
        |> Repo.insert!()

      membership =
        %Membership{}
        |> Membership.changeset(%{
          club_id: club.id,
          character_id: founder.id,
          role: :leader,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      charge_club_founding_fee!(club, founder)

      %{club: Repo.preload(club, memberships: active_membership_query()), membership: membership}
    end)
    |> normalize_transaction_result()
  end

  @doc "Appoints one active member as an officer through the current president."
  def appoint_officer(%Club{} = club, %Character{} = president, %Character{} = target) do
    Repo.transaction(fn ->
      club = lock_club!(club.id)
      memberships = lock_active_memberships!(club.id)
      president_membership = Enum.find(memberships, &(&1.character_id == president.id))
      target_membership = Enum.find(memberships, &(&1.character_id == target.id))

      cond do
        club.status != :active ->
          Repo.rollback(club_changeset("club is not active"))

        not president?(president_membership) ->
          Repo.rollback(club_changeset("only the club president can appoint officers"))

        is_nil(target_membership) ->
          Repo.rollback(club_changeset("officer must be an active club member"))

        president?(target_membership) ->
          Repo.rollback(club_changeset("club president cannot be appointed as an officer"))

        officer?(target_membership) ->
          Repo.rollback(club_changeset("club member is already an officer"))

        true ->
          updated_membership =
            target_membership
            |> Membership.changeset(%{role: :officer})
            |> Repo.update!()

          %{
            club: Repo.preload(club, memberships: active_membership_query()),
            membership: updated_membership
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def appoint_officer(_club, _president, _target),
    do: {:error, club_changeset("officer appointment is unavailable")}

  @doc "Returns an officer to the ordinary member role through the current president."
  def revoke_officer(%Club{} = club, %Character{} = president, %Character{} = target) do
    Repo.transaction(fn ->
      club = lock_club!(club.id)
      memberships = lock_active_memberships!(club.id)
      president_membership = Enum.find(memberships, &(&1.character_id == president.id))
      target_membership = Enum.find(memberships, &(&1.character_id == target.id))

      cond do
        club.status != :active ->
          Repo.rollback(club_changeset("club is not active"))

        not president?(president_membership) ->
          Repo.rollback(club_changeset("only the club president can revoke officers"))

        not officer?(target_membership) ->
          Repo.rollback(club_changeset("club member is not an officer"))

        true ->
          updated_membership =
            target_membership
            |> Membership.changeset(%{role: :member})
            |> Repo.update!()

          %{
            club: Repo.preload(club, memberships: active_membership_query()),
            membership: updated_membership
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def revoke_officer(_club, _president, _target),
    do: {:error, club_changeset("officer revocation is unavailable")}

  @doc "Opens one durable member election for the club presidency."
  def open_president_election(club, proposer, candidate, opts \\ [])

  def open_president_election(
        %Club{} = club,
        %Character{} = proposer,
        %Character{} = candidate,
        opts
      ) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      club = lock_club!(club.id)
      memberships = lock_active_memberships!(club.id)
      proposer_membership = Enum.find(memberships, &(&1.character_id == proposer.id))
      candidate_membership = Enum.find(memberships, &(&1.character_id == candidate.id))

      cond do
        club.status != :active ->
          Repo.rollback(club_changeset("club is not active"))

        candidate.realm_id != club.realm_id or candidate.status != :active ->
          Repo.rollback(club_changeset("president candidate must belong to this active realm"))

        is_nil(proposer_membership) ->
          Repo.rollback(club_changeset("election proposer is not an active club member"))

        is_nil(candidate_membership) ->
          Repo.rollback(club_changeset("president candidate is not an active club member"))

        length(memberships) < 2 ->
          Repo.rollback(club_changeset("president election requires at least two active members"))

        open_president_election?(club) ->
          Repo.rollback(club_changeset("a president election is already open"))

        true ->
          proposal = new_president_election(proposer.id, candidate.id, memberships, now)

          updated_club =
            club
            |> Club.changeset(%{
              metadata: append_governance_proposal(club.metadata || %{}, proposal)
            })
            |> Repo.update!()

          %{
            club: Repo.preload(updated_club, memberships: active_membership_query()),
            proposal: proposal
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def open_president_election(_club, _proposer, _candidate, _opts),
    do: {:error, club_changeset("president election is unavailable")}

  @doc "Records one immutable member vote and resolves a decisive presidency election."
  def cast_president_vote(club, voter, proposal_id, vote, opts \\ [])

  def cast_president_vote(
        %Club{} = club,
        %Character{} = voter,
        proposal_id,
        vote,
        opts
      )
      when is_binary(proposal_id) and vote in [:approve, :reject] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      club = lock_club!(club.id)
      memberships = lock_active_memberships!(club.id)
      voter_membership = Enum.find(memberships, &(&1.character_id == voter.id))

      proposal =
        club.metadata
        |> governance_proposals()
        |> Enum.find(fn proposal ->
          Map.get(proposal, "id") == proposal_id and
            Map.get(proposal, "kind") == "president_election" and
            Map.get(proposal, "status") == "open"
        end)

      candidate_membership =
        if proposal do
          Enum.find(
            memberships,
            &(&1.character_id == Map.get(proposal, "candidate_character_id"))
          )
        end

      cond do
        is_nil(proposal) ->
          Repo.rollback(club_changeset("president election is not open"))

        is_nil(voter_membership) ->
          Repo.rollback(club_changeset("voter is not an active club member"))

        voter.id not in proposal_voter_ids(proposal) ->
          Repo.rollback(club_changeset("voter is not part of this president election"))

        Map.has_key?(proposal_votes(proposal), voter.id) ->
          Repo.rollback(club_changeset("member has already voted in this president election"))

        is_nil(candidate_membership) ->
          Repo.rollback(club_changeset("president candidate is not an active club member"))

        true ->
          proposal = put_president_vote(proposal, voter.id, vote)

          case president_election_resolution(proposal) do
            :pending ->
              updated_club = replace_governance_proposal!(club, proposal)

              %{
                club: Repo.preload(updated_club, memberships: active_membership_query()),
                proposal: proposal,
                resolution: :pending
              }

            :rejected ->
              proposal = resolve_president_election(proposal, :rejected, now)
              updated_club = replace_governance_proposal!(club, proposal)

              %{
                club: Repo.preload(updated_club, memberships: active_membership_query()),
                proposal: proposal,
                resolution: :rejected
              }

            :accepted ->
              transfer_presidency!(memberships, candidate_membership.character_id)
              proposal = resolve_president_election(proposal, :accepted, now)
              updated_club = replace_governance_proposal!(club, proposal)

              %{
                club: Repo.preload(updated_club, memberships: active_membership_query()),
                proposal: proposal,
                resolution: :accepted
              }
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def cast_president_vote(_club, _voter, _proposal_id, _vote, _opts),
    do: {:error, club_changeset("president election vote is unavailable")}

  def invite_member(%Club{} = club, %Character{} = inviter, %Character{} = invitee) do
    Repo.transaction(fn ->
      club = lock_club!(club.id)
      inviter_membership = lock_membership!(club.id, inviter.id)
      invitee = lock_character!(invitee.id)

      validate_invitation!(club, inviter_membership, invitee)

      invitation =
        %Invitation{}
        |> Invitation.changeset(%{
          club_id: club.id,
          inviter_character_id: inviter.id,
          invitee_character_id: invitee.id,
          status: :pending,
          sent_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      _ = Notifications.notify_club_invitation(invitee, invitation, club)

      %{club: club, invitation: Repo.preload(invitation, [:club, :inviter_character])}
    end)
    |> normalize_transaction_result()
  end

  def accept_invitation(%Invitation{} = invitation, %Character{} = invitee) do
    Repo.transaction(fn ->
      invitation = lock_invitation!(invitation.id)
      invitee = lock_character!(invitee.id)
      club = lock_club!(invitation.club_id)

      validate_invitation_response!(invitation, invitee)

      membership =
        %Membership{}
        |> Membership.changeset(%{
          club_id: club.id,
          character_id: invitee.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      updated_invitation =
        invitation
        |> Invitation.changeset(%{status: :accepted, responded_at: DateTime.utc_now()})
        |> Repo.update!()

      %{
        club: Repo.preload(club, memberships: active_membership_query()),
        membership: membership,
        invitation: updated_invitation
      }
    end)
    |> normalize_transaction_result()
  end

  def reject_invitation(%Invitation{} = invitation, %Character{} = invitee) do
    Repo.transaction(fn ->
      invitation = lock_invitation!(invitation.id)
      invitee = lock_character!(invitee.id)

      validate_invitation_response!(invitation, invitee)

      invitation
      |> Invitation.changeset(%{status: :rejected, responded_at: DateTime.utc_now()})
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def get_event!(event_id) when is_binary(event_id) do
    Event
    |> Repo.get!(event_id)
    |> Repo.preload([:club, :attendances])
  end

  def character_attending_event?(event_id, character_id)
      when is_binary(event_id) and is_binary(character_id) do
    Repo.exists?(
      from attendance in EventAttendance,
        where: attendance.event_id == ^event_id and attendance.character_id == ^character_id
    )
  end

  def character_attending_event?(_event_id, _character_id), do: false

  @doc "Returns the durable no-wager duel challenges attached to one tournament event."
  def list_duel_challenges(%Event{} = event) do
    duel_challenges(event.metadata || %{})
  end

  @doc "Lists active same-club tournament attendees that the scoped challenger may invite."
  def list_duel_opponents(%Event{kind: :duel_tournament} = event, character_id)
      when is_binary(character_id) do
    attendee_ids =
      EventAttendance
      |> where(
        [attendance],
        attendance.event_id == ^event.id and attendance.character_id != ^character_id
      )
      |> select([attendance], attendance.character_id)
      |> Repo.all()

    if attendee_ids == [] do
      []
    else
      Character
      |> join(:inner, [character], membership in Membership,
        on: membership.character_id == character.id
      )
      |> where(
        [character, membership],
        character.id in ^attendee_ids and membership.club_id == ^event.club_id and
          membership.status == :active and character.realm_id == ^event.realm_id
      )
      |> order_by([character, _membership], asc: character.name, asc: character.id)
      |> Repo.all()
    end
  end

  def list_duel_opponents(_event, _character_id), do: []

  @doc "Creates a pending, consent-based no-wager club duel invitation."
  def challenge_duel(%Event{} = event, %Character{} = challenger, %Character{} = opponent) do
    Repo.transaction(fn ->
      event = lock_event!(event.id)
      {challenger, opponent} = lock_duel_characters!(challenger.id, opponent.id)
      memberships = lock_duel_memberships!(event.club_id, [challenger.id, opponent.id])

      validate_duel_participants!(event, challenger, opponent, memberships)

      challenges = list_duel_challenges(event)

      if pending_duel_challenge?(challenges, challenger.id, opponent.id) do
        Repo.rollback(
          club_changeset("a pending duel invitation already exists for these attendees")
        )
      end

      challenge = %{
        "id" => Ecto.UUID.generate(),
        "challenger_character_id" => challenger.id,
        "opponent_character_id" => opponent.id,
        "status" => "pending",
        "created_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      updated_event =
        event
        |> Event.changeset(%{
          metadata: Map.put(event.metadata || %{}, "duel_challenges", challenges ++ [challenge])
        })
        |> Repo.update!()

      %{event: Repo.preload(updated_event, [:club, :attendances]), challenge: challenge}
    end)
    |> normalize_transaction_result()
  end

  @doc "Accepts a tournament invitation and creates the corresponding no-wager combat."
  def accept_duel_challenge(%Event{} = event, challenge_id, %Character{} = opponent)
      when is_binary(challenge_id) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      event = lock_event!(event.id)
      challenge = find_duel_challenge(event, challenge_id)

      if is_nil(challenge) or challenge["status"] != "pending" do
        Repo.rollback(club_changeset("duel invitation is not pending"))
      end

      if challenge["opponent_character_id"] != opponent.id do
        Repo.rollback(club_changeset("duel invitation does not belong to this opponent"))
      end

      challenger_id = challenge["challenger_character_id"]
      {challenger, opponent} = lock_duel_characters!(challenger_id, opponent.id)
      memberships = lock_duel_memberships!(event.club_id, [challenger.id, opponent.id])

      validate_duel_participants!(event, challenger, opponent, memberships)

      combat =
        case CombatContext.create_club_match(%Realm{id: event.realm_id}, %{
               participants: [
                 %{character_id: challenger.id, side: "red", position: 0},
                 %{character_id: opponent.id, side: "blue", position: 0}
               ],
               metadata: %{
                 "club_event_id" => event.id,
                 "club_duel_challenge_id" => challenge_id,
                 "location_id" => challenger.current_location_id,
                 "started_at" => DateTime.to_iso8601(now)
               }
             }) do
          {:ok, %{combat: combat}} -> combat
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          {:error, _step, %Changeset{} = changeset, _changes} -> Repo.rollback(changeset)
          {:error, _reason} -> Repo.rollback(club_changeset("club duel could not be created"))
        end

      accepted_challenge =
        challenge
        |> Map.put("status", "accepted")
        |> Map.put("accepted_at", DateTime.to_iso8601(now))
        |> Map.put("combat_id", combat.id)

      updated_event =
        event
        |> Event.changeset(%{
          status: if(event.status == :scheduled, do: :active, else: event.status),
          metadata:
            Map.put(
              event.metadata || %{},
              "duel_challenges",
              replace_duel_challenge(list_duel_challenges(event), accepted_challenge)
            )
        })
        |> Repo.update!()

      %{
        event: Repo.preload(updated_event, [:club, :attendances]),
        challenge: accepted_challenge,
        combat: combat
      }
    end)
    |> normalize_transaction_result()
  end

  def accept_duel_challenge(_event, _challenge_id, _opponent),
    do: {:error, club_changeset("duel invitation is not pending")}

  def reject_duel_challenge(%Event{} = event, challenge_id, %Character{} = opponent)
      when is_binary(challenge_id) do
    Repo.transaction(fn ->
      event = lock_event!(event.id)
      challenge = find_duel_challenge(event, challenge_id)

      cond do
        is_nil(challenge) or challenge["status"] != "pending" ->
          Repo.rollback(club_changeset("duel invitation is not pending"))

        challenge["opponent_character_id"] != opponent.id ->
          Repo.rollback(club_changeset("duel invitation does not belong to this opponent"))

        true ->
          rejected_challenge =
            challenge
            |> Map.put("status", "rejected")
            |> Map.put("rejected_at", DateTime.to_iso8601(DateTime.utc_now()))

          event
          |> Event.changeset(%{
            metadata:
              Map.put(
                event.metadata || %{},
                "duel_challenges",
                replace_duel_challenge(list_duel_challenges(event), rejected_challenge)
              )
          })
          |> Repo.update!()
          |> Repo.preload([:club, :attendances])
      end
    end)
    |> normalize_transaction_result()
  end

  def reject_duel_challenge(_event, _challenge_id, _opponent),
    do: {:error, club_changeset("duel invitation is not pending")}

  @doc """
  Records a no-wager club-match result on its linked event.

  The association intentionally lives in combat metadata so existing club event
  rows need no new foreign key. A completed event is returned unchanged on a
  retry.
  """
  def settle_event_from_combat(%CombatSchema{} = combat) do
    Repo.transaction(fn ->
      if combat.kind != :club_match or combat.status != :finished do
        Repo.rollback(club_changeset("combat is not a finished club match"))
      end

      event_id = combat.metadata["club_event_id"] || combat.metadata[:club_event_id]
      event = lock_event!(event_id)

      if event.realm_id != combat.realm_id do
        Repo.rollback(club_changeset("club event belongs to another realm"))
      end

      cond do
        event.kind != :duel_tournament ->
          Repo.rollback(club_changeset("club match must belong to a duel tournament"))

        event.status == :completed ->
          Repo.preload(event, [:club, :attendances])

        event.status not in [:scheduled, :active] ->
          Repo.rollback(club_changeset("club event cannot be settled from combat"))

        club_match_recorded?(event, combat.id) ->
          Repo.preload(event, [:club, :attendances])

        true ->
          now = DateTime.utc_now()
          ladder_entries = update_duel_ladder!(event, combat, now)

          event
          |> Event.changeset(%{
            status: :active,
            metadata: mark_duel_challenge_completed(event.metadata, combat, now),
            result_metadata:
              append_club_match_result(event.result_metadata, combat, ladder_entries, now)
          })
          |> Repo.update!()
          |> Repo.preload([:club, :attendances])
      end
    end)
    |> normalize_transaction_result()
  end

  def create_event(%Club{} = club, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    kind = normalize_event_kind(attrs["kind"] || :general_meeting)
    scheduled_at = attrs["scheduled_at"] || DateTime.utc_now()

    Repo.transaction(fn ->
      club = lock_club!(club.id)

      if club.status != :active do
        Repo.rollback(club_changeset("club is not active"))
      end

      if is_nil(kind) do
        Repo.rollback(club_changeset("event kind is invalid"))
      end

      if not event_kind_matches_club?(club.club_type, kind) do
        Repo.rollback(club_changeset("event kind does not match the club type"))
      end

      insert_event!(club, kind, scheduled_at, attrs)
    end)
    |> normalize_transaction_result()
  end

  @doc "Creates an event only when the acting member has club scheduling authority."
  def create_event(%Club{} = club, %Character{} = actor, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    kind = normalize_event_kind(attrs["kind"] || :general_meeting)
    scheduled_at = attrs["scheduled_at"] || DateTime.utc_now()

    Repo.transaction(fn ->
      club = lock_club!(club.id)
      membership = lock_membership!(club.id, actor.id)

      cond do
        is_nil(membership) or membership.status != :active ->
          Repo.rollback(club_changeset("character is not an active club member"))

        not can?(club, membership, "schedule_events") ->
          Repo.rollback(club_changeset("club role lacks required permission schedule_events"))

        club.status != :active ->
          Repo.rollback(club_changeset("club is not active"))

        is_nil(kind) ->
          Repo.rollback(club_changeset("event kind is invalid"))

        not event_kind_matches_club?(club.club_type, kind) ->
          Repo.rollback(club_changeset("event kind does not match the club type"))

        true ->
          insert_event!(club, kind, scheduled_at, attrs)
      end
    end)
    |> normalize_transaction_result()
  end

  def list_events_for_club(club_id) when is_binary(club_id) do
    Repo.all(
      from event in Event,
        where: event.club_id == ^club_id,
        order_by: [asc: event.scheduled_at],
        preload: [:attendances]
    )
  end

  def list_upcoming_events_for_realm(realm_id) when is_binary(realm_id) do
    now = DateTime.utc_now()

    Repo.all(
      from event in Event,
        where:
          event.realm_id == ^realm_id and event.status in [:scheduled, :active] and
            event.scheduled_at >= ^now,
        order_by: [asc: event.scheduled_at],
        preload: [:club]
    )
  end

  def attend_event(%Event{} = event, %Character{} = character) do
    Repo.transaction(fn ->
      event = lock_event!(event.id)
      character = lock_character!(character.id)

      {membership, social_ties} =
        if event.kind == :general_meeting do
          lock_social_memberships(event, character.id)
        else
          {lock_membership!(event.club_id, character.id), []}
        end

      cond do
        event.status not in [:scheduled, :active] ->
          Repo.rollback(club_changeset("event is not open for attendance"))

        is_nil(membership) or membership.status != :active ->
          Repo.rollback(club_changeset("character is not an active club member"))

        already_attended?(event.id, character.id) ->
          Repo.rollback(club_changeset("character has already attended this event"))

        true ->
          xp_awarded = attendance_xp(event.kind)
          now = DateTime.utc_now()

          attendance =
            %EventAttendance{}
            |> EventAttendance.changeset(%{
              event_id: event.id,
              character_id: character.id,
              attended_at: now,
              metadata: attendance_metadata(event, xp_awarded, length(social_ties))
            })
            |> Repo.insert!()

          case event.kind do
            :research_session -> record_research_note!(membership, event.id, now)
            :expedition_briefing -> record_expedition_plan!(membership, event.id, now)
            :general_meeting -> record_social_ties!(membership, social_ties, event.id, now)
            _other -> :ok
          end

          {:ok, _result} =
            Progression.grant_xp(Repo, character, xp_awarded, %{
              "source" => "club_event_attendance",
              "club_event_id" => event.id,
              "club_event_kind" => to_string(event.kind),
              "granted_at" => now
            })

          attendance
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Awards unredeemed research-club contributors when a member completes a compatible project."
  def reward_research_contributors(project, project_xp, opts \\ [])

  def reward_research_contributors(
        %{id: project_id, character_id: author_character_id, realm_id: realm_id},
        project_xp,
        opts
      )
      when is_binary(project_id) and is_binary(author_character_id) and is_binary(realm_id) and
             is_integer(project_xp) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      author_club_ids =
        Membership
        |> join(:inner, [membership], club in Club, on: club.id == membership.club_id)
        |> where(
          [membership, club],
          membership.character_id == ^author_character_id and membership.status == :active and
            club.realm_id == ^realm_id and club.club_type == :research and club.status == :active
        )
        |> select([membership, _club], membership.club_id)
        |> Repo.all()

      memberships =
        if author_club_ids == [] do
          []
        else
          Membership
          |> where(
            [membership],
            membership.club_id in ^author_club_ids and membership.status == :active and
              membership.character_id != ^author_character_id
          )
          |> order_by([membership], asc: membership.character_id, asc: membership.club_id)
          |> lock("FOR UPDATE")
          |> preload(:character)
          |> Repo.all()
          |> Enum.filter(&(research_contribution(&1).credits > 0))
        end

      memberships
      |> Enum.group_by(& &1.character_id)
      |> Enum.map(fn {character_id, contributor_memberships} ->
        credits =
          contributor_memberships
          |> Enum.map(&research_contribution(&1).credits)
          |> Enum.sum()

        xp_awarded = research_contributor_xp(project_xp, credits)
        character = contributor_memberships |> List.first() |> Map.fetch!(:character)

        case Progression.grant_xp(Repo, character, xp_awarded, %{
               "source" => "club_research_contribution",
               "academia_project_id" => project_id,
               "research_note_credits" => credits,
               "granted_at" => now
             }) do
          {:ok, %{character: updated_character}} ->
            Enum.each(contributor_memberships, fn membership ->
              membership
              |> Membership.changeset(%{
                metadata: redeem_research_notes(membership.metadata || %{}, project_id, now)
              })
              |> Repo.update!()
            end)

            %{
              "character_id" => character_id,
              "character_name" => updated_character.name,
              "research_note_credits" => credits,
              "xp_awarded" => xp_awarded
            }

          {:error, %Changeset{} = changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end)
    |> normalize_transaction_result()
  end

  def reward_research_contributors(_project, _project_xp, _opts), do: {:ok, []}

  @doc "Consumes one briefing credit from every participant when a whole party has a shared route plan."
  def consume_expedition_plan_for_members(character_ids, realm_id, opts \\ [])

  def consume_expedition_plan_for_members(character_ids, realm_id, opts)
      when is_list(character_ids) and is_binary(realm_id) do
    character_ids = character_ids |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.sort()
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if character_ids == [] do
      {:ok, nil}
    else
      Repo.transaction(fn ->
        memberships =
          Membership
          |> join(:inner, [membership], club in Club, on: club.id == membership.club_id)
          |> where(
            [membership, club],
            membership.character_id in ^character_ids and membership.status == :active and
              club.realm_id == ^realm_id and club.club_type == :expedition_planning and
              club.status == :active
          )
          |> order_by([membership, _club], asc: membership.character_id, asc: membership.club_id)
          |> lock("FOR UPDATE")
          |> Repo.all()
          |> Enum.filter(&(expedition_plan_contribution(&1).credits > 0))

        selected_memberships =
          memberships
          |> Enum.group_by(& &1.character_id)
          |> then(fn memberships_by_character ->
            if Enum.all?(character_ids, &Map.has_key?(memberships_by_character, &1)) do
              Enum.map(character_ids, &List.first(Map.fetch!(memberships_by_character, &1)))
            else
              []
            end
          end)

        if selected_memberships == [] do
          nil
        else
          Enum.each(selected_memberships, &consume_expedition_plan_credit!(&1, now))

          %{
            "status" => "available",
            "source" => "club_expedition_briefing",
            "participant_character_ids" => character_ids,
            "xp_bonus_bps" => @expedition_route_plan_bonus_bps,
            "prepared_at" => DateTime.to_iso8601(now)
          }
        end
      end)
      |> normalize_transaction_result()
    end
  end

  def consume_expedition_plan_for_members(_character_ids, _realm_id, _opts), do: {:ok, nil}

  def complete_event(%Event{} = event, result_metadata \\ %{}) do
    Repo.transaction(fn ->
      event = lock_event!(event.id)

      if event.status not in [:scheduled, :active] do
        Repo.rollback(club_changeset("event is not active"))
      end

      event
      |> Event.changeset(%{
        status: :completed,
        completed_at: DateTime.utc_now(),
        result_metadata: result_metadata
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def leave_club(%Club{} = club, %Character{} = character) do
    Repo.transaction(fn ->
      club = lock_club!(club.id)
      memberships = lock_active_memberships!(club.id)
      membership = Enum.find(memberships, &(&1.character_id == character.id))

      if is_nil(membership) do
        Repo.rollback(club_changeset("character is not an active club member"))
      end

      now = DateTime.utc_now()

      membership
      |> Membership.changeset(%{status: :left, left_at: now})
      |> Repo.update!()

      remaining_members = Enum.reject(memberships, &(&1.id == membership.id))

      updated_metadata =
        cancel_stale_president_elections(club.metadata || %{}, membership.character_id, now)

      club =
        if updated_metadata == (club.metadata || %{}) do
          club
        else
          club
          |> Club.changeset(%{metadata: updated_metadata})
          |> Repo.update!()
        end

      updated_club =
        cond do
          remaining_members == [] ->
            club
            |> Club.changeset(%{status: :archived})
            |> Repo.update!()

          membership.role == :leader ->
            new_leader =
              successor_membership(
                remaining_members,
                club.metadata |> club_governance() |> succession_rule()
              )

            new_leader
            |> Membership.changeset(%{role: :leader})
            |> Repo.update!()

            club

          true ->
            club
        end

      Repo.preload(updated_club, memberships: active_membership_query())
    end)
    |> normalize_transaction_result()
  end

  defp validate_club_creation!(%Character{} = founder, club_type) do
    cond do
      club_type not in @club_types ->
        Repo.rollback(club_changeset("club type is invalid"))

      not eligible_club_founder?(founder) ->
        Repo.rollback(
          club_changeset("only active Academy Core students or active Professors can found clubs")
        )

      true ->
        :ok
    end
  end

  defp eligible_club_founder?(%Character{} = founder) do
    active_academy_core_student?(founder.id) or active_professor?(founder)
  end

  defp active_academy_core_student?(character_id) do
    case Academy.current_enrollment(character_id) do
      %{program_type: :academy_core, status: :active} -> true
      _enrollment -> false
    end
  end

  defp active_professor?(%Character{} = character) do
    case Academia.active_professor(character.id) do
      %{realm_id: realm_id} when realm_id == character.realm_id -> true
      _professor -> false
    end
  end

  defp charge_club_founding_fee!(%Club{} = club, %Character{} = founder) do
    case Economy.treasury_account_for_realm(founder.realm_id) do
      nil ->
        Repo.rollback(club_changeset("Academy treasury is unavailable"))

      academy_treasury ->
        with {:ok, founder_account} <- Economy.ensure_character_account(founder),
             {:ok, _transfer} <-
               Economy.transfer(founder_account, academy_treasury, @club_founding_fee, %{
                 entry_type: "purchase",
                 source: "academy_club_founding_fee",
                 academy_destination: "realm_treasury",
                 club_id: club.id,
                 club_type: Atom.to_string(club.club_type),
                 founder_character_id: founder.id
               }) do
          :ok
        else
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp validate_invitation!(
         %Club{} = club,
         inviter_membership,
         %Character{} = invitee
       ) do
    cond do
      club.status != :active ->
        Repo.rollback(club_changeset("club is not active"))

      is_nil(inviter_membership) or inviter_membership.status != :active ->
        Repo.rollback(club_changeset("inviter is not an active club member"))

      not can?(club, inviter_membership, "invite_members") ->
        Repo.rollback(club_changeset("club role lacks required permission invite_members"))

      invitee.realm_id != club.realm_id ->
        Repo.rollback(club_changeset("invitee must belong to the same realm"))

      not Academy.academic_affiliated?(invitee.id) ->
        Repo.rollback(club_changeset("invitee must be academically affiliated"))

      active_membership_exists?(club.id, invitee.id) ->
        Repo.rollback(club_changeset("invitee already belongs to this club"))

      pending_invitation_exists?(club.id, invitee.id) ->
        Repo.rollback(club_changeset("invitee already has a pending invitation"))

      true ->
        :ok
    end
  end

  defp validate_invitation_response!(%Invitation{} = invitation, %Character{} = invitee) do
    cond do
      invitation.status != :pending ->
        Repo.rollback(club_changeset("invitation is not pending"))

      invitation.invitee_character_id != invitee.id ->
        Repo.rollback(club_changeset("invitation does not belong to this character"))

      true ->
        :ok
    end
  end

  defp event_kind_matches_club?(:general_interest, :general_meeting), do: true
  defp event_kind_matches_club?(:dueling, :duel_tournament), do: true
  defp event_kind_matches_club?(:research, :research_session), do: true
  defp event_kind_matches_club?(:expedition_planning, :expedition_briefing), do: true
  defp event_kind_matches_club?(_club_type, _kind), do: false

  defp attendance_metadata(%Event{kind: :research_session}, xp_awarded, _social_ties) do
    %{"xp_awarded" => xp_awarded, "research_note_credit" => 1}
  end

  defp attendance_metadata(%Event{kind: :expedition_briefing}, xp_awarded, _social_ties) do
    %{"xp_awarded" => xp_awarded, "expedition_plan_credit" => 1}
  end

  defp attendance_metadata(_event, xp_awarded, social_ties) do
    %{"xp_awarded" => xp_awarded}
    |> maybe_put_social_ties(social_ties)
  end

  defp maybe_put_social_ties(metadata, social_ties)
       when is_integer(social_ties) and social_ties > 0,
       do: Map.put(metadata, "social_ties_formed", social_ties)

  defp maybe_put_social_ties(metadata, _social_ties), do: metadata

  defp record_research_note!(%Membership{} = membership, event_id, now) do
    contribution = research_contribution_metadata(membership.metadata || %{})
    event_ids = Map.get(contribution, "event_ids", [])
    event_ids = if(is_list(event_ids), do: event_ids, else: [])

    updated_contribution =
      contribution
      |> Map.put("credits", nonnegative_integer(Map.get(contribution, "credits")) + 1)
      |> Map.put("event_ids", Enum.uniq([event_id | event_ids]))
      |> Map.put("last_event_id", event_id)
      |> Map.put("last_contributed_at", DateTime.to_iso8601(now))

    membership
    |> Membership.changeset(%{
      metadata: Map.put(membership.metadata || %{}, "research_contribution", updated_contribution)
    })
    |> Repo.update!()
  end

  defp record_expedition_plan!(%Membership{} = membership, event_id, now) do
    plan = expedition_plan_metadata(membership.metadata || %{})
    event_ids = Map.get(plan, "event_ids", [])
    event_ids = if(is_list(event_ids), do: event_ids, else: [])

    updated_plan =
      plan
      |> Map.put("credits", nonnegative_integer(Map.get(plan, "credits")) + 1)
      |> Map.put("event_ids", Enum.uniq([event_id | event_ids]))
      |> Map.put("last_event_id", event_id)
      |> Map.put("last_prepared_at", DateTime.to_iso8601(now))

    membership
    |> Membership.changeset(%{
      metadata: Map.put(membership.metadata || %{}, "expedition_plan", updated_plan)
    })
    |> Repo.update!()
  end

  defp lock_social_memberships(%Event{} = event, character_id) do
    attendee_ids =
      EventAttendance
      |> where(
        [attendance],
        attendance.event_id == ^event.id and attendance.character_id != ^character_id
      )
      |> select([attendance], attendance.character_id)
      |> Repo.all()

    character_ids = Enum.uniq([character_id | attendee_ids])

    memberships =
      Membership
      |> where(
        [membership],
        membership.club_id == ^event.club_id and membership.character_id in ^character_ids
      )
      |> order_by([membership], asc: membership.character_id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    membership = Enum.find(memberships, &(&1.character_id == character_id))

    social_ties =
      Enum.filter(memberships, fn other_membership ->
        other_membership.character_id != character_id and other_membership.status == :active
      end)

    {membership, social_ties}
  end

  defp record_social_ties!(%Membership{} = membership, other_memberships, event_id, now) do
    current_metadata =
      Enum.reduce(other_memberships, membership.metadata || %{}, fn other_membership, metadata ->
        add_social_tie(metadata, other_membership.character_id, event_id, now)
      end)

    membership
    |> Membership.changeset(%{metadata: current_metadata})
    |> Repo.update!()

    Enum.each(other_memberships, fn other_membership ->
      other_membership
      |> Membership.changeset(%{
        metadata:
          add_social_tie(other_membership.metadata || %{}, membership.character_id, event_id, now)
      })
      |> Repo.update!()
    end)
  end

  defp add_social_tie(metadata, counterpart_character_id, event_id, now) do
    friendships = friendship_metadata(metadata)
    friendship = Map.get(friendships, counterpart_character_id, %{})
    friendship = if(is_map(friendship), do: friendship, else: %{})
    event_ids = Map.get(friendship, "event_ids", [])
    event_ids = if(is_list(event_ids), do: event_ids, else: [])

    updated_friendship =
      if event_id in event_ids do
        friendship
      else
        friendship
        |> Map.put("shared_events", nonnegative_integer(Map.get(friendship, "shared_events")) + 1)
        |> Map.put("event_ids", Enum.uniq([event_id | event_ids]))
        |> Map.put("last_shared_at", DateTime.to_iso8601(now))
      end

    Map.put(
      metadata,
      "club_friendships",
      Map.put(friendships, counterpart_character_id, updated_friendship)
    )
  end

  defp consume_expedition_plan_credit!(%Membership{} = membership, now) do
    plan = expedition_plan_metadata(membership.metadata || %{})

    updated_plan =
      plan
      |> Map.put("credits", max(nonnegative_integer(Map.get(plan, "credits")) - 1, 0))
      |> Map.put("last_consumed_at", DateTime.to_iso8601(now))

    membership
    |> Membership.changeset(%{
      metadata: Map.put(membership.metadata || %{}, "expedition_plan", updated_plan)
    })
    |> Repo.update!()
  end

  defp redeem_research_notes(metadata, project_id, now) do
    contribution = research_contribution_metadata(metadata)
    reward_history = Map.get(metadata, "research_project_rewards", %{})
    reward_history = if(is_map(reward_history), do: reward_history, else: %{})

    metadata
    |> Map.put(
      "research_contribution",
      contribution
      |> Map.put("credits", 0)
      |> Map.put("event_ids", [])
      |> Map.put("redeemed_at", DateTime.to_iso8601(now))
    )
    |> Map.put(
      "research_project_rewards",
      Map.put(reward_history, project_id, %{"redeemed_at" => DateTime.to_iso8601(now)})
    )
  end

  defp research_contribution_metadata(metadata) do
    case Map.get(metadata || %{}, "research_contribution", %{}) do
      contribution when is_map(contribution) -> contribution
      _other -> %{}
    end
  end

  defp expedition_plan_metadata(metadata) do
    case Map.get(metadata || %{}, "expedition_plan", %{}) do
      plan when is_map(plan) -> plan
      _other -> %{}
    end
  end

  defp friendship_metadata(metadata) do
    case Map.get(metadata || %{}, "club_friendships", %{}) do
      friendships when is_map(friendships) -> friendships
      _other -> %{}
    end
  end

  defp research_contributor_xp(project_xp, credits) do
    share_percent = min(max(credits, 0), @research_note_share_cap) * @research_note_share_percent
    max(div(max(project_xp, 1) * share_percent + 99, 100), 1)
  end

  defp attendance_xp(:general_meeting), do: 5
  defp attendance_xp(:duel_tournament), do: 10
  defp attendance_xp(:research_session), do: 8
  defp attendance_xp(:expedition_briefing), do: 6
  defp attendance_xp(_kind), do: 5

  defp update_duel_ladder!(%Event{kind: :duel_tournament} = event, combat, now) do
    attendee_ids =
      EventAttendance
      |> where([attendance], attendance.event_id == ^event.id)
      |> select([attendance], attendance.character_id)
      |> Repo.all()

    participants =
      CombatParticipant
      |> where(
        [participant],
        participant.combat_id == ^combat.id and participant.character_id in ^attendee_ids
      )
      |> Repo.all()

    character_ids = Enum.map(participants, & &1.character_id)

    memberships =
      Membership
      |> where(
        [membership],
        membership.club_id == ^event.club_id and membership.character_id in ^character_ids and
          membership.status == :active
      )
      |> order_by([membership], asc: membership.character_id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    participant_sides = Map.new(participants, &{&1.character_id, &1.side})
    year = Clock.world_time(now).year

    Enum.map(memberships, fn membership ->
      result =
        duel_result(Map.fetch!(participant_sides, membership.character_id), combat.winner_side)

      ladder = duel_ladder(membership, year)
      updated_ladder = increment_duel_ladder(ladder, result)

      membership
      |> Membership.changeset(%{
        metadata:
          Map.put(membership.metadata || %{}, "duel_ladder", ladder_metadata(updated_ladder))
      })
      |> Repo.update!()

      %{
        "character_id" => membership.character_id,
        "result" => Atom.to_string(result),
        "wins" => updated_ladder.wins,
        "losses" => updated_ladder.losses,
        "draws" => updated_ladder.draws,
        "year" => year
      }
    end)
  end

  defp club_match_recorded?(%Event{} = event, combat_id) do
    event.result_metadata
    |> Map.get("club_matches", [])
    |> List.wrap()
    |> Enum.any?(&(is_map(&1) and &1["combat_id"] == combat_id))
  end

  defp append_club_match_result(result_metadata, combat, ladder_entries, now) do
    matches =
      case Map.get(result_metadata, "club_matches", []) do
        matches when is_list(matches) -> matches
        _other -> []
      end

    match = %{
      "combat_id" => combat.id,
      "winner_side" => combat.winner_side,
      "resolved_at" => DateTime.to_iso8601(now),
      "ladder_entries" => ladder_entries
    }

    result_metadata
    |> Map.put("combat_id", combat.id)
    |> Map.put("winner_side", combat.winner_side)
    |> Map.put("resolved_via", "combat")
    |> Map.put("club_matches", matches ++ [match])
  end

  defp mark_duel_challenge_completed(metadata, combat, now) do
    challenge_id =
      Map.get(combat.metadata || %{}, "club_duel_challenge_id") ||
        Map.get(combat.metadata || %{}, :club_duel_challenge_id)

    if is_binary(challenge_id) do
      updated_challenges =
        metadata
        |> duel_challenges()
        |> Enum.map(fn challenge ->
          if challenge["id"] == challenge_id do
            challenge
            |> Map.put("status", "completed")
            |> Map.put("completed_at", DateTime.to_iso8601(now))
            |> Map.put("winner_side", combat.winner_side)
          else
            challenge
          end
        end)

      Map.put(metadata, "duel_challenges", updated_challenges)
    else
      metadata
    end
  end

  defp duel_ladder(%Membership{} = membership, year) do
    ladder = Map.get(membership.metadata || %{}, "duel_ladder", %{})

    if Map.get(ladder, "year") == year do
      %{
        year: year,
        wins: nonnegative_integer(Map.get(ladder, "wins")),
        losses: nonnegative_integer(Map.get(ladder, "losses")),
        draws: nonnegative_integer(Map.get(ladder, "draws"))
      }
    else
      %{year: year, wins: 0, losses: 0, draws: 0}
    end
  end

  defp increment_duel_ladder(ladder, :win), do: %{ladder | wins: ladder.wins + 1}
  defp increment_duel_ladder(ladder, :loss), do: %{ladder | losses: ladder.losses + 1}
  defp increment_duel_ladder(ladder, :draw), do: %{ladder | draws: ladder.draws + 1}

  defp ladder_metadata(ladder) do
    %{
      "year" => ladder.year,
      "wins" => ladder.wins,
      "losses" => ladder.losses,
      "draws" => ladder.draws
    }
  end

  defp duel_result(_participant_side, nil), do: :draw
  defp duel_result(participant_side, winner_side) when participant_side == winner_side, do: :win
  defp duel_result(_participant_side, _winner_side), do: :loss
  defp nonnegative_integer(value) when is_integer(value) and value >= 0, do: value
  defp nonnegative_integer(_value), do: 0

  defp lock_duel_characters!(challenger_id, opponent_id) do
    character_ids = [challenger_id, opponent_id] |> Enum.filter(&is_binary/1) |> Enum.uniq()

    characters =
      Character
      |> where([character], character.id in ^character_ids)
      |> order_by([character], asc: character.id)
      |> lock("FOR UPDATE")
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    case {Map.get(characters, challenger_id), Map.get(characters, opponent_id)} do
      {%Character{} = challenger, %Character{} = opponent} -> {challenger, opponent}
      _other -> Repo.rollback(club_changeset("duel attendees could not be found"))
    end
  end

  defp lock_duel_memberships!(club_id, character_ids) do
    Membership
    |> where(
      [membership],
      membership.club_id == ^club_id and membership.character_id in ^character_ids
    )
    |> order_by([membership], asc: membership.character_id)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Map.new(&{&1.character_id, &1})
  end

  defp validate_duel_participants!(event, challenger, opponent, memberships) do
    cond do
      event.kind != :duel_tournament ->
        Repo.rollback(club_changeset("event is not a duel tournament"))

      event.status not in [:scheduled, :active] ->
        Repo.rollback(club_changeset("duel tournament is not open"))

      challenger.id == opponent.id ->
        Repo.rollback(club_changeset("a character cannot challenge themselves"))

      challenger.realm_id != event.realm_id or opponent.realm_id != event.realm_id ->
        Repo.rollback(club_changeset("duel attendees must belong to the event realm"))

      not active_duel_membership?(memberships, challenger.id) or
          not active_duel_membership?(memberships, opponent.id) ->
        Repo.rollback(club_changeset("both duelists must be active club members"))

      not character_attending_event?(event.id, challenger.id) or
          not character_attending_event?(event.id, opponent.id) ->
        Repo.rollback(club_changeset("both duelists must attend the tournament"))

      is_nil(challenger.current_location_id) or
          challenger.current_location_id != opponent.current_location_id ->
        Repo.rollback(club_changeset("duelists must be together at the tournament"))

      not is_nil(Travel.active_journey(challenger.id)) or
          not is_nil(Travel.active_journey(opponent.id)) ->
        Repo.rollback(club_changeset("travelling characters cannot enter a club duel"))

      not is_nil(CombatContext.active_combat_for_character(challenger.id)) or
          not is_nil(CombatContext.active_combat_for_character(opponent.id)) ->
        Repo.rollback(club_changeset("a duelist is already in an active combat"))

      true ->
        :ok
    end
  end

  defp active_duel_membership?(memberships, character_id) do
    case Map.get(memberships, character_id) do
      %Membership{status: :active} -> true
      _other -> false
    end
  end

  defp pending_duel_challenge?(challenges, challenger_id, opponent_id) do
    Enum.any?(challenges, fn challenge ->
      challenge["status"] == "pending" and
        MapSet.new([challenge["challenger_character_id"], challenge["opponent_character_id"]]) ==
          MapSet.new([challenger_id, opponent_id])
    end)
  end

  defp find_duel_challenge(event, challenge_id) do
    event
    |> list_duel_challenges()
    |> Enum.find(&(&1["id"] == challenge_id))
  end

  defp duel_challenges(metadata) do
    case Map.get(metadata || %{}, "duel_challenges", []) do
      challenges when is_list(challenges) -> Enum.filter(challenges, &is_map/1)
      _other -> []
    end
  end

  defp replace_duel_challenge(challenges, updated_challenge) do
    Enum.map(challenges, fn challenge ->
      if challenge["id"] == updated_challenge["id"], do: updated_challenge, else: challenge
    end)
  end

  defp active_membership_exists?(club_id, character_id) do
    Repo.exists?(
      from membership in Membership,
        where:
          membership.club_id == ^club_id and membership.character_id == ^character_id and
            membership.status == :active
    )
  end

  defp pending_invitation_exists?(club_id, character_id) do
    Repo.exists?(
      from invitation in Invitation,
        where:
          invitation.club_id == ^club_id and invitation.invitee_character_id == ^character_id and
            invitation.status == :pending
    )
  end

  defp club_metadata_for(attrs) when is_map(attrs) do
    metadata =
      case Map.get(attrs, "metadata") do
        metadata when is_map(metadata) -> metadata
        _other -> %{}
      end

    metadata
    |> Map.delete(@club_governance_key)
    |> Map.delete(:governance)
    |> Map.put(@club_governance_key, default_governance())
  end

  defp default_governance do
    %{
      "leadership" => %{"selection" => @leadership_selection},
      "officers" => %{"permissions" => @officer_permissions},
      "succession" => %{"on_president_exit" => @succession_rule},
      @governance_proposals_key => []
    }
  end

  defp club_governance(metadata) when is_map(metadata) do
    raw_governance = Map.get(metadata, @club_governance_key, %{})
    raw_governance = if(is_map(raw_governance), do: raw_governance, else: %{})

    %{
      "leadership" => %{"selection" => leadership_selection(raw_governance)},
      "officers" => %{"permissions" => normalized_officer_permissions(raw_governance)},
      "succession" => %{"on_president_exit" => succession_rule(raw_governance)},
      @governance_proposals_key => normalized_governance_proposals(raw_governance)
    }
  end

  defp club_governance(_metadata), do: default_governance()

  defp leadership_selection(governance) when is_map(governance) do
    case governance_block(governance, "leadership") |> Map.get("selection") do
      @leadership_selection -> @leadership_selection
      _other -> @leadership_selection
    end
  end

  defp normalized_officer_permissions(governance) when is_map(governance) do
    permissions = governance_block(governance, "officers") |> Map.get("permissions")

    permissions =
      if is_list(permissions) do
        Enum.filter(permissions, &(&1 in @officer_permissions))
      else
        []
      end

    if permissions == [], do: @officer_permissions, else: permissions
  end

  defp succession_rule(governance) when is_map(governance) do
    case governance_block(governance, "succession") |> Map.get("on_president_exit") do
      @succession_rule -> @succession_rule
      _other -> @succession_rule
    end
  end

  defp officer_permissions(%Club{} = club) do
    club.metadata
    |> club_governance()
    |> get_in(["officers", "permissions"])
  end

  defp normalized_governance_proposals(governance) when is_map(governance) do
    case Map.get(governance, @governance_proposals_key, []) do
      proposals when is_list(proposals) -> Enum.filter(proposals, &is_map/1)
      _other -> []
    end
  end

  defp governance_block(governance, key) when is_map(governance) and is_binary(key) do
    case Map.get(governance, key) do
      block when is_map(block) -> block
      _other -> %{}
    end
  end

  defp governance_block(_governance, _key), do: %{}

  defp governance_proposals(metadata) do
    metadata
    |> club_governance()
    |> Map.get(@governance_proposals_key, [])
  end

  defp put_governance(metadata, governance) when is_map(governance) do
    metadata = if(is_map(metadata), do: metadata, else: %{})
    Map.put(metadata, @club_governance_key, governance)
  end

  defp append_governance_proposal(metadata, proposal) do
    governance = club_governance(metadata)

    proposals =
      [proposal | Map.get(governance, @governance_proposals_key, [])]
      |> Enum.take(@governance_proposal_history_limit)

    governance
    |> Map.put(@governance_proposals_key, proposals)
    |> then(&put_governance(metadata, &1))
  end

  defp replace_governance_proposal!(%Club{} = club, proposal) do
    club
    |> Club.changeset(%{
      metadata: replace_governance_proposal_metadata(club.metadata || %{}, proposal)
    })
    |> Repo.update!()
  end

  defp replace_governance_proposal_metadata(metadata, proposal) do
    proposal_id = Map.get(proposal, "id")
    governance = club_governance(metadata)

    proposals =
      governance
      |> Map.get(@governance_proposals_key, [])
      |> Enum.map(fn existing ->
        if Map.get(existing, "id") == proposal_id, do: proposal, else: existing
      end)

    governance
    |> Map.put(@governance_proposals_key, proposals)
    |> then(&put_governance(metadata, &1))
  end

  defp open_president_election?(%Club{} = club) do
    Enum.any?(governance_proposals(club.metadata || %{}), fn proposal ->
      Map.get(proposal, "kind") == "president_election" and Map.get(proposal, "status") == "open"
    end)
  end

  defp new_president_election(proposer_character_id, candidate_character_id, memberships, now) do
    voter_character_ids = memberships |> Enum.map(& &1.character_id) |> Enum.sort()

    %{
      "id" => Ecto.UUID.generate(),
      "kind" => "president_election",
      "status" => "open",
      "proposer_character_id" => proposer_character_id,
      "candidate_character_id" => candidate_character_id,
      "voter_character_ids" => voter_character_ids,
      "votes" => %{},
      "votes_needed" => votes_needed(voter_character_ids),
      "opened_at" => DateTime.to_iso8601(now)
    }
  end

  defp proposal_voter_ids(proposal) when is_map(proposal) do
    proposal
    |> Map.get("voter_character_ids", [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp proposal_voter_ids(_proposal), do: []

  defp proposal_votes(proposal) when is_map(proposal) do
    voter_ids = MapSet.new(proposal_voter_ids(proposal))

    case Map.get(proposal, "votes", %{}) do
      votes when is_map(votes) ->
        Enum.reduce(votes, %{}, fn
          {character_id, vote}, acc
          when is_binary(character_id) and vote in @election_votes ->
            if MapSet.member?(voter_ids, character_id) do
              Map.put(acc, character_id, vote)
            else
              acc
            end

          _entry, acc ->
            acc
        end)

      _other ->
        %{}
    end
  end

  defp proposal_votes(_proposal), do: %{}

  defp put_president_vote(proposal, voter_character_id, vote) do
    proposal
    |> Map.put(
      "votes",
      Map.put(proposal_votes(proposal), voter_character_id, Atom.to_string(vote))
    )
  end

  defp president_election_resolution(proposal) do
    voter_ids = proposal_voter_ids(proposal)
    votes = proposal_votes(proposal)
    votes_needed = votes_needed(voter_ids)
    approve_votes = Enum.count(votes, fn {_character_id, vote} -> vote == "approve" end)
    reject_votes = Enum.count(votes, fn {_character_id, vote} -> vote == "reject" end)

    cond do
      approve_votes >= votes_needed -> :accepted
      reject_votes >= votes_needed -> :rejected
      map_size(votes) >= length(voter_ids) -> :rejected
      true -> :pending
    end
  end

  defp votes_needed(voter_ids) when is_list(voter_ids), do: div(length(voter_ids), 2) + 1

  defp resolve_president_election(proposal, resolution, now)
       when resolution in [:accepted, :rejected] do
    proposal
    |> Map.put("status", Atom.to_string(resolution))
    |> Map.put("resolved_at", DateTime.to_iso8601(now))
  end

  defp transfer_presidency!(memberships, candidate_character_id) do
    Enum.each(memberships, fn membership ->
      role =
        cond do
          membership.character_id == candidate_character_id -> :leader
          membership.role == :leader -> :member
          true -> membership.role
        end

      if role != membership.role do
        membership
        |> Membership.changeset(%{role: role})
        |> Repo.update!()
      end
    end)
  end

  defp election_summary(nil, _memberships, _actor_id), do: nil

  defp election_summary(proposal, memberships, actor_id) do
    voter_ids = proposal_voter_ids(proposal)
    votes = proposal_votes(proposal)

    %{
      id: Map.get(proposal, "id"),
      candidate:
        Enum.find(memberships, &(&1.character_id == Map.get(proposal, "candidate_character_id"))),
      voter_count: length(voter_ids),
      votes_cast: map_size(votes),
      approve_votes: Enum.count(votes, fn {_character_id, vote} -> vote == "approve" end),
      reject_votes: Enum.count(votes, fn {_character_id, vote} -> vote == "reject" end),
      votes_needed: votes_needed(voter_ids),
      can_vote?:
        is_binary(actor_id) and actor_id in voter_ids and not Map.has_key?(votes, actor_id)
    }
  end

  defp cancel_stale_president_elections(metadata, departing_character_id, now) do
    proposals = governance_proposals(metadata)

    updated_proposals =
      Enum.map(proposals, fn proposal ->
        if Map.get(proposal, "kind") == "president_election" and
             Map.get(proposal, "status") == "open" and
             (departing_character_id in proposal_voter_ids(proposal) or
                Map.get(proposal, "candidate_character_id") == departing_character_id) do
          proposal
          |> Map.put("status", "cancelled")
          |> Map.put("cancelled_at", DateTime.to_iso8601(now))
          |> Map.put("cancellation_reason", "member_departed")
        else
          proposal
        end
      end)

    if updated_proposals == proposals do
      metadata
    else
      metadata
      |> club_governance()
      |> Map.put(@governance_proposals_key, updated_proposals)
      |> then(&put_governance(metadata, &1))
    end
  end

  defp successor_membership(memberships, @succession_rule) when is_list(memberships) do
    Enum.min_by(memberships, &membership_sort_key/1)
  end

  defp successor_membership(memberships, _rule),
    do: successor_membership(memberships, @succession_rule)

  defp membership_sort_key(%Membership{} = membership) do
    joined_at =
      case membership.joined_at do
        %DateTime{} = joined_at -> DateTime.to_unix(joined_at, :microsecond)
        _other -> 0
      end

    {joined_at, membership.character_id, membership.id}
  end

  defp active_memberships_for_state(%Club{} = club) do
    memberships =
      case club.memberships do
        %Ecto.Association.NotLoaded{} -> list_members(club)
        memberships when is_list(memberships) -> memberships
        _other -> []
      end

    memberships
    |> Enum.filter(&(&1.status == :active))
    |> Enum.sort_by(&membership_sort_key/1)
  end

  defp lock_active_memberships!(club_id) do
    Membership
    |> where([membership], membership.club_id == ^club_id and membership.status == :active)
    |> order_by([membership], asc: membership.character_id, asc: membership.id)
    |> lock("FOR UPDATE")
    |> Repo.all()
  end

  defp active_membership_query do
    from membership in Membership,
      where: membership.status == :active,
      order_by: [asc: membership.joined_at],
      preload: [:character]
  end

  defp normalize_club_type(value) when value in @club_types, do: value
  defp normalize_club_type("general_interest"), do: :general_interest
  defp normalize_club_type("dueling"), do: :dueling
  defp normalize_club_type("research"), do: :research
  defp normalize_club_type("expedition_planning"), do: :expedition_planning
  defp normalize_club_type(_value), do: nil

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_club!(club_id) do
    Club
    |> where([club], club.id == ^club_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_membership!(club_id, character_id) do
    Membership
    |> where(
      [membership],
      membership.club_id == ^club_id and membership.character_id == ^character_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp lock_invitation!(invitation_id) do
    Invitation
    |> where([invitation], invitation.id == ^invitation_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload([:club, :inviter_character])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp club_changeset(message) do
    %Club{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  @event_kinds [:general_meeting, :duel_tournament, :research_session, :expedition_briefing]

  defp normalize_event_kind(value) when value in @event_kinds, do: value
  defp normalize_event_kind("general_meeting"), do: :general_meeting
  defp normalize_event_kind("duel_tournament"), do: :duel_tournament
  defp normalize_event_kind("research_session"), do: :research_session
  defp normalize_event_kind("expedition_briefing"), do: :expedition_briefing
  defp normalize_event_kind(_value), do: nil

  defp insert_event!(%Club{} = club, kind, scheduled_at, attrs) do
    %Event{}
    |> Event.changeset(%{
      club_id: club.id,
      realm_id: club.realm_id,
      kind: kind,
      status: :scheduled,
      scheduled_at: scheduled_at,
      result_metadata: %{},
      metadata: attrs["metadata"] || %{}
    })
    |> Repo.insert!()
  end

  defp lock_event!(event_id) do
    Event
    |> where([event], event.id == ^event_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp already_attended?(event_id, character_id) do
    Repo.exists?(
      from attendance in EventAttendance,
        where: attendance.event_id == ^event_id and attendance.character_id == ^character_id
    )
  end
end
