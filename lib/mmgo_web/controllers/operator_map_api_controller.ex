defmodule MMGOWeb.OperatorMapApiController do
  use MMGOWeb, :controller

  alias MMGO.Worlds

  def create_location(conn, params) do
    with realm when not is_nil(realm) <- Worlds.get_default_realm(),
         attrs <- location_attrs(params),
         {:ok, location} <- Worlds.create_location(realm, attrs) do
      json(conn, %{
        ok: true,
        location: %{id: location.id, name: location.name, slug: location.slug}
      })
    else
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "default realm not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})
    end
  end

  def create_route(conn, params) do
    with realm when not is_nil(realm) <- Worlds.get_default_realm(),
         attrs <- route_attrs(params),
         {:ok, route} <- Worlds.create_route(realm, attrs) do
      json(conn, %{ok: true, route: %{id: route.id, name: route.name}})
    else
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "default realm not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})
    end
  end

  defp location_attrs(params) do
    display = Map.get(params, "display", %{})

    %{
      slug: Map.get(params, "slug"),
      name: Map.get(params, "name"),
      kind: Map.get(params, "kind", "wilderness"),
      x: parse_int(Map.get(params, "x"), 1_000),
      y: parse_int(Map.get(params, "y"), 1_000),
      safe_zone: Map.get(params, "safe_zone", false),
      metadata: %{
        "event_template_code" => Map.get(params, "event_template_code"),
        "display" => display
      }
    }
  end

  defp route_attrs(params) do
    road_type = Map.get(params, "road_type", "minor")
    visibility = Map.get(params, "visibility", "public")

    %{
      name: Map.get(params, "name"),
      origin_location_id: Map.get(params, "origin_location_id"),
      destination_location_id: Map.get(params, "destination_location_id"),
      travel_days: parse_int(Map.get(params, "travel_days"), 1),
      risk_level: parse_int(Map.get(params, "risk_level"), 0),
      bidirectional: Map.get(params, "bidirectional", true),
      metadata: %{
        "road_type" => road_type,
        "visibility" => visibility,
        "organization_id" => Map.get(params, "organization_id"),
        "visual_points" => parse_visual_points(Map.get(params, "visual_points", []))
      }
    }
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp parse_int(_value, default), do: default

  defp parse_visual_points(points) when is_list(points), do: points

  defp parse_visual_points(points) when is_binary(points) do
    case Jason.decode(points) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _other -> []
    end
  end

  defp parse_visual_points(_points), do: []

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
