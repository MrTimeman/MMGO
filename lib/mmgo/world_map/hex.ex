defmodule MMGO.WorldMap.Hex do
  @moduledoc """
  A single hex tile entry in the world map: axial coordinate, terrain id, and
  optional sprite/road/location annotations.
  """

  @enforce_keys [:q, :r, :terrain]
  defstruct [:q, :r, :terrain, :sprite, :loc, road: false]

  @type t :: %__MODULE__{
          q: integer(),
          r: integer(),
          terrain: String.t(),
          sprite: String.t() | nil,
          loc: String.t() | nil,
          road: boolean()
        }

  @doc "Builds a `%Hex{}` from a decoded JSON map (string keys, short field names)."
  def from_json(%{} = json) do
    %__MODULE__{
      q: fetch_int!(json, "q"),
      r: fetch_int!(json, "r"),
      terrain: Map.fetch!(json, "t"),
      sprite: Map.get(json, "s"),
      loc: Map.get(json, "loc"),
      road: Map.get(json, "road", false)
    }
  end

  @doc "Serializes a `%Hex{}` back to the compact JSON shape."
  def to_json(%__MODULE__{} = hex) do
    %{"q" => hex.q, "r" => hex.r, "t" => hex.terrain}
    |> maybe_put("s", hex.sprite)
    |> maybe_put("loc", hex.loc)
    |> maybe_put_road(hex.road)
  end

  defp fetch_int!(json, key) do
    case Map.fetch!(json, key) do
      value when is_integer(value) -> value
      value when is_float(value) -> round(value)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_road(map, false), do: map
  defp maybe_put_road(map, true), do: Map.put(map, "road", true)
end
