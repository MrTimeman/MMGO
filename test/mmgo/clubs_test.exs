defmodule MMGO.ClubsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Enrollment
  alias MMGO.Clubs
  alias MMGO.Clubs.Membership
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

    founder = character_fixture(realm, city, "founder", "Founder")
    invitee = character_fixture(realm, city, "invitee", "Invitee")
    outsider = character_fixture(realm, city, "outsider", "Outsider")

    enroll(founder, realm, :basic_education)
    enroll(invitee, realm, :basic_education)

    %{realm: realm, founder: founder, invitee: invitee, outsider: outsider}
  end

  test "create_club/2 creates a club and leader membership", %{founder: founder} do
    assert {:ok, %{club: club, membership: membership}} =
             Clubs.create_club(founder, %{club_type: :general_interest, name: "History Society"})

    assert club.club_type == :general_interest
    assert membership.role == :leader
    assert membership.status == :active
    assert Clubs.list_clubs_for_character(founder.id) |> Enum.any?(&(&1.id == club.id))
  end

  test "create_club/2 rejects non-academically affiliated characters", %{outsider: outsider} do
    assert {:error, changeset} =
             Clubs.create_club(outsider, %{club_type: :dueling, name: "Duelists"})

    assert %{status: ["character must be academically affiliated to create clubs"]} =
             errors_on(changeset)
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

    new_leader = Repo.get_by!(Membership, club_id: group_club.id, character_id: invitee.id)
    assert new_leader.role == :leader
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
end
