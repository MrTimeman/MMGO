defmodule MMGO.SecretCultTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.SecretCult
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "secret-cult-realm",
        name: "Secret Cult Realm",
        is_default: true
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "secret-cult-city",
        name: "Secret Cult City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, watchtower} =
      Worlds.create_location(realm, %{
        slug: "secret-cult-watchtower",
        name: "Secret Cult Watchtower",
        kind: :wilderness,
        x: 30,
        y: 20,
        safe_zone: false
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "secret-cult-tower",
        name: "Secret Cult Tower",
        kind: :tower,
        x: 60,
        y: 40,
        safe_zone: false
      })

    founder = character_fixture(realm, watchtower, "cult-keeper", "Cult Keeper")
    player = character_fixture(realm, city, "cult-player", "Cult Player")

    {:ok, %{organization: cult}} =
      Organizations.create_organization(founder, :cult, "Hidden Passage", %{
        fast_travel_enabled: true,
        linked_location_ids: [city.id, watchtower.id, tower.id],
        metadata: %{
          "secret_cult" => true,
          "discovery_city_id" => city.id,
          "discovery_watchtower_id" => watchtower.id,
          "passage_destination_id" => tower.id
        }
      })

    %{
      city: city,
      watchtower: watchtower,
      tower: tower,
      founder: founder,
      player: player,
      cult: cult
    }
  end

  test "the two location-bound discovery steps grant a real bidirectional passage", %{
    city: city,
    watchtower: watchtower,
    tower: tower,
    player: player
  } do
    assert %{stage: :unknown, can_hear_rumor?: true, passage_available?: false} =
             SecretCult.discovery_state(player)

    assert {:ok, %{character: marked_player, stage: :rumor_heard}} =
             SecretCult.hear_rumor(player)

    assert %{stage: :rumor_heard, can_reveal_passage?: false} =
             SecretCult.discovery_state(marked_player)

    watchtower_player =
      marked_player
      |> Character.travel_changeset(%{current_location_id: watchtower.id})
      |> Repo.update!()

    assert {:ok, %{character: passage_bearer, membership: membership, stage: :passage_unlocked}} =
             SecretCult.reveal_passage(watchtower_player)

    passage_role = Repo.preload(membership, :role).role
    assert passage_role.code == "passage-bearer"
    assert passage_role.permissions == ["grant_fast_travel"]

    assert %{stage: :passage_unlocked, passage_available?: true} =
             SecretCult.discovery_state(passage_bearer)

    destinations = Organizations.list_available_fast_travel_destinations(passage_bearer)
    destination_ids = MapSet.new(Enum.map(destinations, & &1.id))
    assert MapSet.member?(destination_ids, city.id)
    assert MapSet.member?(destination_ids, tower.id)

    assert {:ok, tower_player} = SecretCult.use_pass(passage_bearer, tower.id)
    assert tower_player.current_location_id == tower.id

    assert {:ok, returned_player} = SecretCult.use_pass(tower_player, city.id)
    assert returned_player.current_location_id == city.id
  end

  test "the passage cannot be guessed from the wrong place or before the rumor", %{
    watchtower: watchtower,
    player: player
  } do
    assert {:error, :secret_cult_wrong_location} = SecretCult.reveal_passage(player)

    watchtower_player =
      player
      |> Character.travel_changeset(%{current_location_id: watchtower.id})
      |> Repo.update!()

    assert {:error, :secret_cult_rumor_required} = SecretCult.reveal_passage(watchtower_player)
    assert {:error, :secret_cult_wrong_location} = SecretCult.hear_rumor(watchtower_player)
  end

  test "discovery preserves an existing passage role's permissions", %{
    watchtower: watchtower,
    founder: founder,
    player: player,
    cult: cult
  } do
    assert {:ok, existing_role} =
             Organizations.add_role(cult, founder, %{
               code: "passage-bearer",
               title: "Trusted Passage Bearer",
               rank: 20,
               permissions: ["invite_members"]
             })

    assert {:ok, %{character: marked_player}} = SecretCult.hear_rumor(player)

    watchtower_player =
      marked_player
      |> Character.travel_changeset(%{current_location_id: watchtower.id})
      |> Repo.update!()

    assert {:ok, %{membership: membership}} = SecretCult.reveal_passage(watchtower_player)
    assert Repo.preload(membership, :role).role.id == existing_role.id

    updated_role = Repo.get!(MMGO.Organizations.Role, existing_role.id)
    assert Enum.sort(updated_role.permissions) == ["grant_fast_travel", "invite_members"]
  end

  test "discovery never replaces a pre-existing cult role", %{
    watchtower: watchtower,
    founder: founder,
    player: player,
    cult: cult
  } do
    assert {:ok, initiates_role} =
             Organizations.add_role(cult, founder, %{
               code: "initiate",
               title: "Initiate",
               rank: 20,
               permissions: ["invite_members"]
             })

    assert {:ok, invitation} = Organizations.invite_member(cult, founder, player, initiates_role)
    assert {:ok, membership} = Organizations.accept_invitation(invitation, player)
    assert membership.role_id == initiates_role.id

    assert {:ok, %{character: marked_player}} = SecretCult.hear_rumor(player)

    watchtower_player =
      marked_player
      |> Character.travel_changeset(%{current_location_id: watchtower.id})
      |> Repo.update!()

    assert {:error, :secret_cult_existing_membership_requires_passage_role} =
             SecretCult.reveal_passage(watchtower_player)

    unchanged_membership =
      Repo.get_by!(MMGO.Organizations.Membership,
        organization_id: cult.id,
        character_id: player.id,
        status: :active
      )

    assert unchanged_membership.role_id == initiates_role.id
  end

  test "the cult remains out of public org and map state until the player learns the rumor", %{
    player: player,
    cult: cult
  } do
    assert {:ok, index_state} = Play.organizations_index(player)
    assert index_state.public_organizations == []

    assert {:ok, world_state} = Play.world_hub_state(player)
    assert world_state.organizations == []
    assert world_state.organization_economic_activity == %{}

    assert {:ok, %{character: marked_player}} = SecretCult.hear_rumor(player)

    assert {:ok, visible_index_state} = Play.organizations_index(marked_player)
    assert Enum.map(visible_index_state.public_organizations, & &1.id) == [cult.id]

    assert {:ok, visible_world_state} = Play.world_hub_state(marked_player)
    assert Enum.map(visible_world_state.organizations, & &1.id) == [cult.id]
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
