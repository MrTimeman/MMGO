defmodule MMGO.Telegram.OrgProgressionCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Organizations.Organization
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
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

    founder = character_fixture(realm, city, "founderorg", "Founder Org")
    invitee = character_fixture(realm, city, "inviteeorg", "Invitee Org")

    {:ok, _milestone} =
      Progression.create_milestone(%{
        level: 2,
        code: "carry-boost",
        title: "Carry Boost",
        effects: %{"carry_capacity_bonus" => 5}
      })

    %{founder: founder, invitee: invitee, tower: tower}
  end

  test "/progression and /org commands exercise milestones and organization flow", %{
    founder: founder,
    invitee: invitee,
    tower: tower
  } do
    assert {:ok, milestones_text} =
             Commands.process_message(founder, %{"text" => "/progression milestones"})

    assert milestones_text =~ "Carry Boost"

    assert {:ok, create_text} =
             Commands.process_message(founder, %{"text" => "/org create cult Death Cult"})

    assert create_text =~ "Organization created"

    [organization] = MMGO.Organizations.list_organizations_for_character(founder.id)

    organization =
      organization
      |> Organization.changeset(%{linked_location_ids: [founder.current_location_id, tower.id]})
      |> Repo.update!()

    assert {:ok, role_text} =
             Commands.process_message(founder, %{
               "text" => "/org role #{organization.id} acolyte 10 grant_fast_travel Acolyte"
             })

    assert role_text =~ "Role created"

    assert {:ok, invite_text} =
             Commands.process_message(founder, %{
               "text" => "/org invite #{organization.id} inviteeorg acolyte"
             })

    assert invite_text =~ "Organization invitation"

    [invitation] = MMGO.Organizations.pending_invitations_for_character(invitee.id)

    assert {:ok, invites_text} = Commands.process_message(invitee, %{"text" => "/org invites"})
    assert invites_text =~ invitation.id

    assert {:ok, accept_text} =
             Commands.process_message(invitee, %{"text" => "/org accept #{invitation.id}"})

    assert accept_text =~ "accepted"

    _founder =
      founder |> Character.travel_changeset(%{current_location_id: tower.id}) |> Repo.update!()

    invitee =
      invitee |> Character.travel_changeset(%{current_location_id: tower.id}) |> Repo.update!()

    assert {:ok, travel_text} =
             Commands.process_message(invitee, %{"text" => "/org travel #{organization.id} city"})

    assert travel_text =~ "Organization travel complete"
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
end
