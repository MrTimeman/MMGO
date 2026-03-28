defmodule MMGO.Telegram.ClubCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Enrollment
  alias MMGO.Clubs
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
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

    founder = character_fixture(realm, city, "clubber", "Clubber")
    invitee = character_fixture(realm, city, "invitee", "Invitee")

    enroll(founder, realm, :basic_education)
    enroll(invitee, realm, :basic_education)

    %{founder: founder, invitee: invitee}
  end

  test "/club commands exercise creation, invitation, acceptance, and listing", %{
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, create_text} =
             Commands.process_message(founder, %{"text" => "/club create dueling Duel Society"})

    assert create_text =~ "Club created"

    [club] = Clubs.list_clubs_for_character(founder.id)

    assert {:ok, invite_text} =
             Commands.process_message(founder, %{"text" => "/club invite #{club.id} invitee"})

    assert invite_text =~ "Invitation"

    [invitation] = Clubs.pending_invitations_for_character(invitee.id)

    assert {:ok, invites_text} = Commands.process_message(invitee, %{"text" => "/club invites"})
    assert invites_text =~ club.name

    assert {:ok, accept_text} =
             Commands.process_message(invitee, %{"text" => "/club accept #{invitation.id}"})

    assert accept_text =~ "Joined club"

    assert {:ok, list_text} = Commands.process_message(invitee, %{"text" => "/club list"})
    assert list_text =~ club.name

    assert {:ok, status_text} =
             Commands.process_message(invitee, %{"text" => "/club status #{club.id}"})

    assert status_text =~ "Members: Clubber, Invitee"
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
