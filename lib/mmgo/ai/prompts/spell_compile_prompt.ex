defmodule MMGO.AI.Prompts.SpellCompilePrompt do
  alias MMGO.AI.PromptVersions

  def build(assigns) do
    %{
      kind: "spell_compile",
      prompt_version: PromptVersions.for!(:spell_compile),
      system_prompt: system_prompt(),
      user_prompt: user_prompt(assigns),
      schema: response_schema()
    }
  end

  defp system_prompt do
    """
    You are the MMGO spell compiler. MMGO is a text-based MMO played in Telegram where players write Latin incantations to cast spells inside a magical Tower. Combat is narrative — spells should create dramatic *situations*, not just deal numbers.

    ## Your job
    Convert the player's Latin incantation into a spell spec that the engine will execute. The incantation maps word-by-word to parameter slots (action, shape, power, duration, secondary effect, cost). Unspecified slots are yours to fill creatively based on school and context.

    ## Schools and their identity
    - **fire** — explosive, aggressive, leaves burning environments. Favors area effects and DoTs.
    - **water** — fluid, controlling. Freezes, slows, saturates. Transforms environments (wet, steam, flood).
    - **earth** — immovable, protective. Walls, armor, entrapment. Creates rubble and terrain.
    - **air** — fast, displacement. Knockback, blindness, speed. Spreads other environment tags.
    - **chaos** — unpredictable, volatile. High variance, backlash risk, unstable environments.
    - **order** — crystalline, precise. Silences, locks, crystallizes. Environments become rigid.
    - **life** — growth, restoration. Heals, regenerates, summons. Environments become overgrown.
    - **death** — draining, decaying. Weakens, corrodes, exposes. Environments become necrotic.

    ## Environment effects — use them generously
    The environment is one of the most underused and most exciting parts of the game. Any spell of meaningful intensity should leave a mark. Set `environment_mode` to `"add"` and populate `environment_tags` with 1–2 descriptive strings (e.g. `["fire"]`, `["wet", "flood"]`, `["rubble"]`, `["necrotic"]`, `["crystallized"]`, `["unstable"]`). Only use `"none"` for truly minor utility spells.

    Add `interaction_rules` that define what happens when another school's spell hits this environment. Make them feel physical: water on fire makes steam, air on fire spreads it, earth on air dampens it.

    ## Mechanics
    - All damage is delivered through state primitives — there is no base_damage field.
    - `impact` (duration 0) = one-time hit. `burning` / `regenerating` = per-turn DoT/HoT. All others = status effects.
    - Use `variance` (0–4) to control randomness. Chaos spells: high variance. Order spells: zero variance.
    - `failure_profile.difficulty` should scale with spell complexity (1-word: low, 6-word: high).
    - When `base_spell_id` is provided, you are in revamp mode: modify the base spell's parameters rather than inventing from scratch. Preserve the core action but evolve it.

    Return JSON only. Never invent state IDs outside the supplied list.
    """
    |> String.trim()
  end

  defp user_prompt(assigns) do
    character = Map.fetch!(assigns, :character)
    environment_tags = Map.get(assigns, :environment_tags, [])

    Jason.encode!(%{
      task: "compile_spell",
      character: character,
      current_environment: environment_tags,
      request: Map.fetch!(assigns, :request),
      engine_constraints: %{
        states: Map.fetch!(assigns, :states),
        targeting_modes: ["self", "ally", "enemy", "zone"],
        delivery_forms: [
          "single_target",
          "beam",
          "cone",
          "sphere",
          "wall",
          "zone",
          "self",
          "link",
          "delayed_trigger"
        ],
        environment_modes: ["none", "add", "replace"]
      }
    })
  end

  defp response_schema do
    %{
      type: "object",
      properties: %{
        name: %{type: "string"},
        formula: %{type: "string"},
        school: %{type: "string"},
        description: %{type: "string"},
        level_requirement: %{type: "integer"},
        fatigue_cost: %{type: "integer"},
        cooldown_turns: %{type: "integer"},
        targeting: %{type: "string"},
        delivery_form: %{type: "string"},
        tags: %{type: "array", items: %{type: "string"}},
        narrative_tags: %{type: "array", items: %{type: "string"}},
        environment_tags: %{type: "array", items: %{type: "string"}},
        environment_mode: %{type: "string"},
        effects: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              applies_to: %{type: "string"},
              state: %{type: "string"},
              intensity: %{type: "integer"},
              variance: %{type: "integer"},
              duration: %{type: "integer"},
              tags: %{type: "array", items: %{type: "string"}}
            },
            required: ["applies_to", "state", "intensity", "duration"]
          }
        },
        interaction_rules: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              trigger_type: %{type: "string"},
              trigger: %{type: "string"},
              outcome: %{type: "string"},
              modifier: %{type: "integer"},
              state: %{type: "string"},
              replacement_tags: %{type: "array", items: %{type: "string"}}
            },
            required: ["trigger_type", "trigger", "outcome"]
          }
        },
        failure_profile: %{
          type: "object",
          properties: %{
            difficulty: %{type: "integer"},
            base_success_rate: %{type: "integer"},
            partial_success_rate: %{type: "integer"},
            backlash_damage: %{type: "integer"},
            volatility: %{type: "integer"}
          },
          required: ["difficulty", "base_success_rate", "partial_success_rate", "backlash_damage"]
        }
      },
      required: [
        "name",
        "formula",
        "school",
        "targeting",
        "delivery_form",
        "effects",
        "failure_profile"
      ]
    }
  end
end
