defmodule MMGO.OrganizationsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Notifications.Notification
  alias MMGO.Organizations
  alias MMGO.Repo
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

    %{city: city, tower: tower, founder: founder, invitee: invitee}
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
    assert Repo.get_by!(Notification, character_id: invitee.id, kind: "organization_invitation")

    assert {:ok, membership} = Organizations.accept_invitation(invitation, invitee)
    assert membership.status == :active

    destinations = Organizations.list_available_fast_travel_destinations(invitee)
    assert Enum.map(destinations, & &1.id) == [tower.id]

    assert {:ok, updated_character} = Organizations.use_fast_travel(invitee, organization, tower)
    assert updated_character.current_location_id == tower.id
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
