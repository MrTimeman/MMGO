defmodule MMGO.Worlds do
  import Ecto.Query, warn: false

  alias MMGO.Repo
  alias MMGO.Worlds.{Location, Realm, Route}

  def list_realms do
    Repo.all(from realm in Realm, order_by: [asc: realm.inserted_at])
  end

  def get_realm!(id), do: Repo.get!(Realm, id)

  def get_realm_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Realm, slug: slug)
  end

  def get_default_realm do
    Repo.get_by(Realm, is_default: true)
  end

  def get_default_realm! do
    Repo.get_by!(Realm, is_default: true)
  end

  def create_realm(attrs \\ %{}) do
    %Realm{}
    |> Realm.changeset(attrs)
    |> Repo.insert()
  end

  def change_realm(%Realm{} = realm, attrs \\ %{}) do
    Realm.changeset(realm, attrs)
  end

  def list_locations_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from location in Location,
        where: location.realm_id == ^realm_id,
        order_by: [asc: location.inserted_at]
    )
  end

  def get_location!(id), do: Repo.get!(Location, id)

  def get_location_by_slug(realm_id, slug) when is_binary(realm_id) and is_binary(slug) do
    Repo.get_by(Location, realm_id: realm_id, slug: slug)
  end

  def create_location(%Realm{} = realm, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "realm_id", realm.id)

    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  def list_routes_for_location(location_id) when is_binary(location_id) do
    Repo.all(
      from route in Route,
        where:
          route.origin_location_id == ^location_id or
            route.destination_location_id == ^location_id,
        order_by: [asc: route.inserted_at],
        preload: [:origin_location, :destination_location]
    )
  end

  def route_from_location_to_slug(location_id, destination_slug)
      when is_binary(location_id) and is_binary(destination_slug) do
    list_routes_for_location(location_id)
    |> Enum.find(fn route ->
      cond do
        route.origin_location_id == location_id and
            route.destination_location.slug == destination_slug ->
          true

        route.bidirectional and route.destination_location_id == location_id and
            route.origin_location.slug == destination_slug ->
          true

        true ->
          false
      end
    end)
  end

  def get_route!(id), do: Repo.get!(Route, id)

  def create_route(%Realm{} = realm, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "realm_id", realm.id)

    %Route{}
    |> Route.changeset(attrs)
    |> Repo.insert()
  end

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  def change_route(%Route{} = route, attrs \\ %{}) do
    Route.changeset(route, attrs)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
