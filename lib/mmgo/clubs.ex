defmodule MMGO.Clubs do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Clubs.{Club, Event, EventAttendance, Invitation, Membership}
  alias MMGO.Notifications
  alias MMGO.Repo

  @club_types [:general_interest, :dueling, :research, :expedition_planning]

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

  def pending_invitations_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from invitation in Invitation,
        where: invitation.invitee_character_id == ^character_id and invitation.status == :pending,
        order_by: [asc: invitation.inserted_at],
        preload: [:club, :inviter_character]
    )
  end

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
          metadata: attrs["metadata"] || %{}
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

      %{club: Repo.preload(club, memberships: active_membership_query()), membership: membership}
    end)
    |> normalize_transaction_result()
  end

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

      cond do
        event.status not in [:scheduled, :active] ->
          Repo.rollback(club_changeset("event is not open for attendance"))

        not active_membership_exists?(event.club_id, character.id) ->
          Repo.rollback(club_changeset("character is not an active club member"))

        already_attended?(event.id, character.id) ->
          Repo.rollback(club_changeset("character has already attended this event"))

        true ->
          %EventAttendance{}
          |> EventAttendance.changeset(%{
            event_id: event.id,
            character_id: character.id,
            attended_at: DateTime.utc_now(),
            metadata: %{}
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
  end

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
      membership = lock_membership!(club.id, character.id)

      if is_nil(membership) or membership.status != :active do
        Repo.rollback(club_changeset("character is not an active club member"))
      end

      membership
      |> Membership.changeset(%{status: :left, left_at: DateTime.utc_now()})
      |> Repo.update!()

      remaining_members =
        active_membership_query()
        |> where([membership], membership.club_id == ^club.id)
        |> Repo.all()

      updated_club =
        cond do
          remaining_members == [] ->
            club
            |> Club.changeset(%{status: :archived})
            |> Repo.update!()

          membership.role == :leader ->
            new_leader =
              Enum.min_by(remaining_members, &DateTime.to_unix(&1.joined_at, :microsecond))

            new_leader
            |> Membership.changeset(%{role: :leader})
            |> Repo.update!()

            club
            |> Club.changeset(%{founder_character_id: new_leader.character_id})
            |> Repo.update!()

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

      not Academy.academic_affiliated?(founder.id) ->
        Repo.rollback(club_changeset("character must be academically affiliated to create clubs"))

      true ->
        :ok
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

      inviter_membership.role != :leader ->
        Repo.rollback(club_changeset("only the club leader can send invitations"))

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

  defp lock_event!(event_id) do
    Event
    |> where([event], event.id == ^event_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp already_attended?(event_id, character_id) do
    Repo.exists?(
      from attendance in EventAttendance,
        where:
          attendance.event_id == ^event_id and attendance.character_id == ^character_id
    )
  end
end
