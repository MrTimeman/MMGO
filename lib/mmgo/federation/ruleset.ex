defmodule MMGO.Federation.Ruleset do
  @allowed_magic_scopes ["tower_and_dungeon", "global"]

  def default do
    %{
      "magic_scope" => "tower_and_dungeon",
      "overworld_pvp_enabled" => true,
      "dungeon_pvp_enabled" => true,
      "legal_market_enabled" => true,
      "black_market_enabled" => true,
      "travel_food_units_per_day" => 1,
      "carry_capacity_scale_bps" => 1000
    }
  end

  def normalize(nil), do: default()

  def normalize(ruleset) when is_map(ruleset) do
    default()
    |> Map.merge(stringify_keys(ruleset))
  end

  def validate(ruleset) when is_map(ruleset) do
    ruleset = normalize(ruleset)

    cond do
      ruleset["magic_scope"] not in @allowed_magic_scopes ->
        {:error, "magic_scope must be one of #{Enum.join(@allowed_magic_scopes, ", ")}"}

      not is_boolean(ruleset["overworld_pvp_enabled"]) ->
        {:error, "overworld_pvp_enabled must be a boolean"}

      not is_boolean(ruleset["dungeon_pvp_enabled"]) ->
        {:error, "dungeon_pvp_enabled must be a boolean"}

      not is_boolean(ruleset["legal_market_enabled"]) ->
        {:error, "legal_market_enabled must be a boolean"}

      not is_boolean(ruleset["black_market_enabled"]) ->
        {:error, "black_market_enabled must be a boolean"}

      not is_integer(ruleset["travel_food_units_per_day"]) or
          ruleset["travel_food_units_per_day"] <= 0 ->
        {:error, "travel_food_units_per_day must be a positive integer"}

      not is_integer(ruleset["carry_capacity_scale_bps"]) or
          ruleset["carry_capacity_scale_bps"] <= 0 ->
        {:error, "carry_capacity_scale_bps must be a positive integer"}

      true ->
        {:ok, ruleset}
    end
  end

  def magic_allowed?(ruleset, location_kind, combat_kind) do
    ruleset = normalize(ruleset)

    case ruleset["magic_scope"] do
      "global" ->
        true

      "tower_and_dungeon" ->
        location_kind in ["tower", "dungeon"] or combat_kind == :dungeon_encounter

      _other ->
        true
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
