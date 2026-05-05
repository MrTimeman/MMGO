defmodule MMGOWeb.PlayAdminController do
  use MMGOWeb, :controller

  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Route}
  alias MMGOWeb.PlaySession

  # ── Locations ──

  def create_location(conn, params) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         realm = Worlds.get_default_realm!(),
         {:ok, location} <- Worlds.create_location(realm, params) do
      json(conn, %{ok: true, location: location_data(location)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def update_location(conn, %{"id" => id} = params) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         {:ok, location} <- fetch_location(id),
         {:ok, location} <- Worlds.update_location(location, Map.drop(params, ["id"])) do
      json(conn, %{ok: true, location: location_data(location)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def delete_location(conn, %{"id" => id}) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         {:ok, location} <- fetch_location(id),
         {:ok, _location} <- Worlds.delete_location(location) do
      json(conn, %{ok: true})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  # ── Routes ──

  def create_route(conn, params) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         realm = Worlds.get_default_realm!(),
         {:ok, route} <- Worlds.create_route(realm, params),
         {:ok, route} <- fetch_route(route.id) do
      json(conn, %{ok: true, route: route_data(route)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def update_route(conn, %{"id" => id} = params) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         {:ok, route} <- fetch_route(id),
         {:ok, route} <- Worlds.update_route(route, Map.drop(params, ["id"])),
         {:ok, route} <- fetch_route(route.id) do
      json(conn, %{ok: true, route: route_data(route)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def delete_route(conn, %{"id" => id}) do
    with {:ok, conn, _character} <- PlaySession.fetch_current_character(conn),
         {:ok, route} <- fetch_route(id),
         {:ok, _route} <- Worlds.delete_route(route) do
      json(conn, %{ok: true})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  # ── Helpers ──

  defp fetch_location(id) do
    case Repo.get(Location, id) do
      nil -> {:error, "location not found"}
      location -> {:ok, location}
    end
  end

  defp fetch_route(id) do
    case Repo.get(Route, id) |> Repo.preload([:origin_location, :destination_location]) do
      nil -> {:error, "route not found"}
      route -> {:ok, route}
    end
  end

  defp location_data(location) do
    %{
      id: location.id,
      slug: location.slug,
      name: location.name,
      kind: location.kind,
      x: location.x,
      y: location.y,
      safe_zone: location.safe_zone,
      metadata: location.metadata
    }
  end

  defp route_data(route) do
    origin = Map.get(route, :origin_location) || route.origin_location
    dest = Map.get(route, :destination_location) || route.destination_location

    %{
      id: route.id,
      name: route.name,
      origin_location_id: route.origin_location_id,
      destination_location_id: route.destination_location_id,
      travel_days: route.travel_days,
      risk_level: route.risk_level,
      bidirectional: route.bidirectional,
      metadata: route.metadata,
      origin_location: origin && %{id: origin.id, name: origin.name, x: origin.x, y: origin.y},
      destination_location: dest && %{id: dest.id, name: dest.name, x: dest.x, y: dest.y}
    }
  end

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
