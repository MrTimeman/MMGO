defmodule MMGO.SecretCultTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character, SpecialProfiles}
  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.SecretCult
  alias MMGO.Travel
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
        slug: "the-tower",
        name: "Secret Cult Tower",
        kind: :tower,
        x: 60,
        y: 40,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Cult Realm Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 2,
        risk_level: 10,
        bidirectional: true
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
      realm: realm,
      city: city,
      watchtower: watchtower,
      tower: tower,
      founder: founder,
      player: player,
      cult: cult,
      route: route
    }
  end

  test "special-profile provisioning grants Albert a real cult pass while roads stay blocked", %{
    city: city,
    route: route
  } do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "albert",
               "first_name" => "Albert"
             })

    albert =
      account.id
      |> Accounts.list_characters_for_account()
      |> Enum.find(&(&1.name == "Альберт Латыпов"))

    assert {:ok, active_albert} = Accounts.switch_character(account.id, albert.id)

    assert %{stage: :passage_unlocked, passage_available?: true} =
             SecretCult.discovery_state(active_albert)

    assert {:error, road_changeset} = Travel.start_journey(active_albert, route)
    assert %{route_id: ["sealed spirit cannot use ordinary roads"]} = errors_on(road_changeset)

    assert {:ok, city_albert} = SecretCult.use_pass(active_albert, city.id)
    assert city_albert.current_location_id == city.id
  end

  test "maximum sealed access preserves an existing cult role through a private augmented role",
       %{
         realm: realm,
         founder: founder,
         cult: cult
       } do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "albert-governance",
               "first_name" => "Albert"
             })

    albert =
      account.id
      |> Accounts.list_characters_for_account()
      |> Enum.find(&(&1.name == "Альберт Латыпов"))

    assert {:ok, governance_role} =
             Organizations.add_role(cult, founder, %{
               code: "keeper-council",
               title: "Хранитель совета",
               rank: 80,
               permissions: ["invite_members", "manage_treasury"]
             })

    membership =
      Repo.get_by!(MMGO.Organizations.Membership,
        organization_id: cult.id,
        character_id: albert.id,
        status: :active
      )

    membership
    |> MMGO.Organizations.Membership.changeset(%{role_id: governance_role.id})
    |> Repo.update!()

    assert {:ok, _profiles} = SpecialProfiles.reconcile(account, realm)

    updated_membership =
      Repo.get_by!(MMGO.Organizations.Membership,
        organization_id: cult.id,
        character_id: albert.id,
        status: :active
      )
      |> Repo.preload(:role)

    assert updated_membership.role.id != governance_role.id
    assert updated_membership.role.title == governance_role.title
    assert updated_membership.role.rank == governance_role.rank

    assert Enum.sort(updated_membership.role.permissions) ==
             ["grant_fast_travel", "invite_members", "manage_treasury"]

    assert Repo.get!(MMGO.Organizations.Role, governance_role.id).permissions ==
             ["invite_members", "manage_treasury"]
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

  test "a sealed spirit may use only the verified Secret Cult passage", %{
    watchtower: watchtower,
    tower: tower,
    player: player,
    cult: cult
  } do
    assert {:ok, %{character: marked_player}} = SecretCult.hear_rumor(player)

    watchtower_player =
      marked_player
      |> Character.travel_changeset(%{current_location_id: watchtower.id})
      |> Repo.update!()

    assert {:ok, %{character: passage_bearer}} = SecretCult.reveal_passage(watchtower_player)

    sealed_spirit =
      passage_bearer
      |> Character.changeset(%{
        metadata:
          Map.merge(passage_bearer.metadata || %{}, %{
            "profile_kind" => "sealed_spirit",
            "hidden_presence" => true,
            "sealed_anchor_location_id" => tower.id
          })
      })
      |> Repo.update!()

    assert {:error, generic_changeset} =
             Organizations.use_fast_travel(sealed_spirit, cult, tower)

    assert %{status: ["sealed spirit cannot use organization fast travel"]} =
             errors_on(generic_changeset)

    assert {:ok, tower_spirit} = SecretCult.use_pass(sealed_spirit, tower.id)
    assert tower_spirit.current_location_id == tower.id
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
