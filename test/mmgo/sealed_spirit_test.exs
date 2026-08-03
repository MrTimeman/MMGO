defmodule MMGO.SealedSpiritTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Operator.AuditEvent
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "spirit-realm", name: "Spirit Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 30,
        y: 30,
        safe_zone: true
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Tower Road",
        origin_location_id: tower.id,
        destination_location_id: city.id,
        travel_days: 2,
        risk_level: 1,
        bidirectional: true
      })

    spirit =
      character_fixture(realm, tower, "sealed-owner", "Альберт Латыпов", %{
        "profile_kind" => "sealed_spirit",
        "hidden_presence" => true,
        "sealed_anchor_location_id" => tower.id,
        "progression_tier" => "legendary"
      })

    %{realm: realm, tower: tower, city: city, route: route, spirit: spirit}
  end

  test "ordinary roads and previews are unavailable to a sealed spirit", %{
    route: route,
    spirit: spirit
  } do
    assert {:error, changeset} = Travel.start_journey(spirit, route)
    assert %{route_id: ["sealed spirit cannot use ordinary roads"]} = errors_on(changeset)

    assert {:ok, %{routes: []}} = Play.current_location_and_routes(spirit)
    assert {:error, :sealed_spirit} = Play.path_preview(spirit, "capital-city")
  end

  test "spirit teleport stays in-realm, preserves its anchor, and is audited", %{
    city: city,
    spirit: spirit,
    tower: tower
  } do
    assert {:ok, %{character: projected, audit_event: audit_event}} =
             Play.spirit_teleport(spirit, city.id)

    assert projected.current_location_id == city.id
    assert projected.metadata["sealed_anchor_location_id"] == tower.id
    assert audit_event.action == "sealed_spirit_teleport"
    assert Repo.get!(AuditEvent, audit_event.id).metadata["destination_location_id"] == city.id

    {:ok, other_realm} =
      Worlds.create_realm(%{slug: "other-spirit-realm", name: "Other Realm", is_default: false})

    {:ok, other_city} =
      Worlds.create_location(other_realm, %{
        slug: "other-city",
        name: "Other City",
        kind: :city,
        x: 1,
        y: 1,
        safe_zone: true
      })

    assert {:error, :spirit_teleport_forbidden} =
             Play.spirit_teleport(projected, other_city.id)
  end

  test "ordinary characters cannot invoke spirit teleport", %{
    realm: realm,
    tower: tower,
    city: city
  } do
    ordinary = character_fixture(realm, tower, "ordinary-owner", "Ordinary Mage", %{})
    assert {:error, :spirit_teleport_forbidden} = Play.spirit_teleport(ordinary, city.id)
  end

  defp character_fixture(realm, location, handle, name, metadata) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, metadata: metadata})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
