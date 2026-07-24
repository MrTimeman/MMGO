defmodule MMGO.Alchemy.Interpreter do
  @moduledoc "Schema-bounded AI composition over immutable item primitives."

  alias MMGO.AI
  alias MMGO.AI.Prompts.AlchemyBrewPrompt
  alias MMGO.Accounts.Character

  @primitive_states %{
    "heat" => ["burning", "impact"],
    "cold" => ["frozen"],
    "water" => ["frozen", "regenerating"],
    "earth" => ["shielded", "trapped", "impact"],
    "air" => ["blinded", "staggered"],
    "toxicity" => ["exposed", "blinded"],
    "binding" => ["trapped", "shielded"],
    "restoration" => ["regenerating"],
    "life" => ["regenerating", "empowered"],
    "death" => ["exposed", "silenced"],
    "volatility" => ["impact", "staggered"],
    "clarity" => ["empowered", "silenced"]
  }

  @targeting ~w(self ally enemy zone)
  @applies_to ~w(caster target)

  def primitive_keys, do: Map.keys(@primitive_states) |> Enum.sort()

  def interpret(%Character{} = character, mixture, opts \\ []) when is_map(mixture) do
    allowed_states = allowed_states(mixture.primitive_totals)
    max_intensity = max_intensity(mixture.primitive_totals)

    prompt =
      AlchemyBrewPrompt.build(%{
        fingerprint: mixture.fingerprint,
        ingredients: mixture.ingredients,
        primitive_totals: mixture.primitive_totals,
        allowed_states: allowed_states,
        max_intensity: max_intensity
      })

    ai_opts =
      Keyword.put_new(opts, :metadata, %{
        character_id: character.id,
        ingredient_fingerprint: mixture.fingerprint
      })

    case AI.interpret_alchemy(prompt, ai_opts) do
      {:ok, %{alchemy_brew: response, ai_request: request}} ->
        case validate_response(response, allowed_states, max_intensity) do
          {:ok, result} ->
            {:ok, %{result: result, ai_request: request, fallback?: false}}

          {:error, _reason} ->
            {:ok, fallback_result(mixture, allowed_states, max_intensity, request)}
        end

      {:error, _reason} ->
        {:ok, fallback_result(mixture, allowed_states, max_intensity, nil)}
    end
  end

  def allowed_states(primitive_totals) do
    primitive_totals
    |> Enum.flat_map(fn {primitive, amount} ->
      if is_integer(amount) and amount > 0,
        do: Map.get(@primitive_states, primitive, []),
        else: []
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> ["impact"]
      states -> states
    end
  end

  defp validate_response(response, allowed_states, max_intensity) when is_map(response) do
    name = response["name"]
    description = response["description"]
    targeting = response["targeting"]
    effects = response["effects"]
    brew_days = response["brew_time_game_days"]
    difficulty = response["difficulty"]

    cond do
      not valid_text?(name, 120) -> {:error, :invalid_name}
      not valid_text?(description, 800) -> {:error, :invalid_description}
      targeting not in @targeting -> {:error, :invalid_targeting}
      not is_integer(brew_days) or brew_days not in 1..14 -> {:error, :invalid_brew_time}
      not is_integer(difficulty) or difficulty not in 1..20 -> {:error, :invalid_difficulty}
      not is_list(effects) or effects == [] or length(effects) > 3 -> {:error, :invalid_effects}
      true -> validate_effects(response, effects, allowed_states, max_intensity)
    end
  end

  defp validate_response(_response, _allowed_states, _max_intensity),
    do: {:error, :invalid_response}

  defp validate_effects(response, effects, allowed_states, max_intensity) do
    if Enum.all?(effects, &valid_effect?(&1, allowed_states, max_intensity)) do
      {:ok,
       %{
         "name" => String.trim(response["name"]),
         "description" => String.trim(response["description"]),
         "targeting" => response["targeting"],
         "brew_time_game_days" => response["brew_time_game_days"],
         "difficulty" => response["difficulty"],
         "effects" => Enum.map(effects, &normalize_effect/1)
       }}
    else
      {:error, :effect_outside_boundary}
    end
  end

  defp valid_effect?(effect, allowed_states, max_intensity) when is_map(effect) do
    intensity = effect["intensity"]
    variance = effect["variance"] || 0
    duration = effect["duration"]
    tags = effect["tags"] || []

    effect["applies_to"] in @applies_to and effect["state"] in allowed_states and
      is_integer(intensity) and intensity in 1..max_intensity and is_integer(variance) and
      variance >= 0 and variance <= intensity and is_integer(duration) and duration in 0..5 and
      is_list(tags) and length(tags) <= 6 and Enum.all?(tags, &valid_text?(&1, 40))
  end

  defp valid_effect?(_effect, _allowed_states, _max_intensity), do: false

  defp normalize_effect(effect) do
    %{
      "applies_to" => effect["applies_to"],
      "state" => effect["state"],
      "intensity" => effect["intensity"],
      "variance" => effect["variance"] || 0,
      "duration" => effect["duration"],
      "tags" => effect["tags"] || []
    }
  end

  defp fallback_result(mixture, allowed_states, max_intensity, request) do
    state = fallback_state(allowed_states)
    restorative? = state in ["regenerating", "empowered", "shielded"]

    %{
      result: %{
        "name" => "Настой #{String.slice(mixture.fingerprint, 0, 6)}",
        "description" => "Устойчивая смесь, выведенная из неизменных свойств ингредиентов.",
        "targeting" => if(restorative?, do: "self", else: "enemy"),
        "brew_time_game_days" => max(min(map_size(mixture.primitive_totals), 14), 1),
        "difficulty" => max(min(div(max_intensity, 2), 20), 1),
        "effects" => [
          %{
            "applies_to" => if(restorative?, do: "caster", else: "target"),
            "state" => state,
            "intensity" => min(max_intensity, 8),
            "variance" => 0,
            "duration" => if(state == "impact", do: 0, else: 2),
            "tags" => ["alchemy", "deterministic_fallback"]
          }
        ]
      },
      ai_request: request,
      fallback?: true
    }
  end

  defp fallback_state(states) do
    Enum.find(
      ~w(regenerating shielded burning frozen trapped exposed blinded staggered empowered silenced impact),
      "impact",
      &(&1 in states)
    )
  end

  defp max_intensity(primitive_totals) do
    primitive_totals
    |> Map.values()
    |> Enum.filter(&is_integer/1)
    |> Enum.sum()
    |> max(1)
    |> min(30)
  end

  defp valid_text?(value, max_bytes) when is_binary(value) do
    value = String.trim(value)
    value != "" and String.valid?(value) and byte_size(value) <= max_bytes
  end

  defp valid_text?(_value, _max_bytes), do: false
end
