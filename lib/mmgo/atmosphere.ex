defmodule MMGO.Atmosphere do
  @moduledoc """
  Produces a small, semantic audio presentation state for gameplay surfaces.

  The server names the scene and any major event; the browser only decides
  whether the player has enabled sound. Audio recordings are deployment-owned
  static assets, so a game remains fully usable when no recording is licensed
  or configured yet.

  Configure only local, served asset paths. For example:

      config :mmgo, MMGO.Atmosphere,
        assets: %{
          city: "/audio/city.ogg",
          combat: "/audio/combat.ogg"
        }

  A configured event recording temporarily takes precedence over the ambient
  recording. The client then returns to ambience after that one-shot cue.
  """

  @ambient_by_location %{
    "base" => "base",
    "city" => "city",
    "dungeon_entrance" => "dungeon",
    "tower" => "tower",
    "wilderness" => "wilderness"
  }

  @event_cues MapSet.new(["combat", "dungeon_encounter", "journey", "migration"])

  @labels %{
    "base" => "тихий защищённый очаг",
    "city" => "городской гул",
    "combat" => "круг боя",
    "dungeon" => "гул глубин",
    "dungeon_encounter" => "угроза в глубинах",
    "journey" => "дорога",
    "migration" => "переход между реалмами",
    "tower" => "ветер у Башни",
    "wilderness" => "дикая местность",
    "world" => "мир"
  }

  @doc """
  Returns the semantic audio state for a location and optional major event.

  `:assets` is injectable for tests; without it the optional deployment
  configuration is used. Invalid and external asset URLs are ignored so the
  web shell never treats an arbitrary source as a curated game recording.
  """
  def cue_for(location_or_kind, opts \\ []) do
    ambient_cue = ambient_cue(location_or_kind)
    major_event_cue = event_cue(Keyword.get(opts, :major_event))
    assets = opts |> Keyword.get(:assets, configured_assets()) |> normalize_assets()
    ambient_source = Map.get(assets, ambient_cue)
    event_source = major_event_cue && Map.get(assets, major_event_cue)

    {active_cue, active_source, loop?} =
      cond do
        is_binary(event_source) -> {major_event_cue, event_source, false}
        is_binary(ambient_source) -> {ambient_cue, ambient_source, true}
        not is_nil(major_event_cue) -> {major_event_cue, nil, false}
        true -> {ambient_cue, nil, true}
      end

    %{
      ambient_cue: ambient_cue,
      ambient_source: ambient_source,
      major_event_cue: major_event_cue,
      event_source: event_source,
      active_cue: active_cue,
      active_source: active_source,
      loop?: loop?,
      available?: is_binary(active_source),
      label: label_for(active_cue)
    }
  end

  @doc "Returns the semantic ambient cue for a location or location kind."
  def ambient_cue(%{kind: kind}), do: ambient_cue(kind)

  def ambient_cue(kind) when is_atom(kind) or is_binary(kind) do
    kind
    |> to_string()
    |> then(&Map.get(@ambient_by_location, &1, "world"))
  end

  def ambient_cue(_other), do: "world"

  @doc "Returns a whitelisted major-event cue, or `nil` for an unknown event."
  def event_cue(event) when is_atom(event) or is_binary(event) do
    event = to_string(event)
    if MapSet.member?(@event_cues, event), do: event
  end

  def event_cue(_other), do: nil

  @doc "Human-readable Russian label for a semantic cue."
  def label_for(cue) when is_atom(cue) or is_binary(cue) do
    cue
    |> to_string()
    |> then(&Map.get(@labels, &1, @labels["world"]))
  end

  def label_for(_other), do: @labels["world"]

  defp configured_assets do
    :mmgo
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:assets, %{})
  end

  defp normalize_assets(assets) when is_map(assets) or is_list(assets) do
    Enum.reduce(assets, %{}, fn
      {cue, source}, normalized when (is_atom(cue) or is_binary(cue)) and is_binary(source) ->
        cue = to_string(cue)

        if known_cue?(cue) and local_asset_path?(source) do
          Map.put(normalized, cue, source)
        else
          normalized
        end

      _entry, normalized ->
        normalized
    end)
  end

  defp normalize_assets(_other), do: %{}

  defp known_cue?(cue), do: Map.has_key?(@labels, cue)

  defp local_asset_path?(source) do
    String.starts_with?(source, "/") and not String.starts_with?(source, "//") and
      is_nil(URI.parse(source).scheme)
  end
end
