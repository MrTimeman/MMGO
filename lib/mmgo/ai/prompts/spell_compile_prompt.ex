defmodule MMGO.AI.Prompts.SpellCompilePrompt do
  alias MMGO.AI.PromptVersions
  alias MMGO.Spells.Incantation

  @state_reference %{
    "impact" => %{
      category: "combat.damage",
      description: "Direct damage applied to the target side",
      notes: "Instant. Use for hit damage and burst spells."
    },
    "burning" => %{
      category: "combat.dot",
      description: "Fire damage over time",
      notes: "Periodic. Lasts multiple turns."
    },
    "frozen" => %{
      category: "combat.control",
      description: "Cold hindrance and movement lock",
      notes: "Non-periodic control state."
    },
    "trapped" => %{
      category: "combat.control",
      description: "Immobilizes and blocks action choice changes",
      notes: "Prevents movement-like responses."
    },
    "blinded" => %{
      category: "combat.debuff",
      description: "Obscures senses and precision",
      notes: "Use for light, sand, smoke, or void interference."
    },
    "silenced" => %{
      category: "combat.debuff",
      description: "Prevents spell casting actions",
      notes: "Blocks active casting and passive toggles."
    },
    "staggered" => %{
      category: "combat.break",
      description: "Consumes one future action",
      notes: "One-shot interruption state."
    },
    "channeling" => %{
      category: "combat.commitment",
      description: "Actor is committed to an existing effect",
      notes: "Use sparingly for delayed or sustained actions."
    },
    "shielded" => %{
      category: "combat.defense",
      description: "Absorbs incoming damage once",
      notes: "First shield is consumed on impact."
    },
    "regenerating" => %{
      category: "combat.healing",
      description: "Heals over time",
      notes: "Periodic positive state."
    },
    "empowered" => %{
      category: "combat.buff",
      description: "Boosts output or amplifies follow-up effects",
      notes: "Positive self-buff."
    },
    "exposed" => %{
      category: "combat.break",
      description: "Next incoming hit deals bonus damage",
      notes: "Consumed by the next damage packet."
    },
    "revealed" => %{
      category: "utility.map",
      description: "Hidden node or path becomes visible",
      notes: "Utility-only state."
    },
    "warded" => %{
      category: "utility.map",
      description: "Zone is protected or stabilized",
      notes: "Utility or passive environmental protection."
    },
    "illuminated" => %{
      category: "utility.map",
      description: "Zone is lit for exploration clarity",
      notes: "Utility-only state."
    },
    "detected" => %{
      category: "utility.sense",
      description: "Nearby threats or signals are exposed",
      notes: "Utility-only state."
    },
    "transmuted" => %{
      category: "utility.alteration",
      description: "Object, terrain, or node trait is altered",
      notes: "Utility-only state."
    }
  }

  @interaction_catalogue [
    %{
      trigger_type: "environment_tag",
      trigger: "wet",
      outcomes: ["negate", "amplify", "replace_environment", "spread", "transform"],
      guidance: "Use for terrain and battlefield condition interactions."
    },
    %{
      trigger_type: "target_state",
      trigger: "burning",
      outcomes: ["amplify", "apply_bonus_state"],
      guidance: "Use when the target already carries a compatible or opposing state."
    },
    %{
      trigger_type: "spell_tag",
      trigger: "fire",
      outcomes: ["amplify", "replace_environment"],
      guidance: "Use for school-level synergies and pattern echoes."
    }
  ]

  def build(assigns) do
    %{
      kind: "spell_compile",
      prompt_version: PromptVersions.for!(:spell_compile),
      system_prompt: system_prompt(),
      user_prompt: user_prompt(assigns),
      schema: response_schema()
    }
  end

  def system_prompt do
    """
    You are the MMGO spell compiler. Convert a player incantation into a strict, game-safe spell spec.
    Output JSON only. Never add unsupported state ids, triggers, delivery forms, or targeting modes.

    Core rules:
    1. Stay inside the supplied state primitive table and interaction catalogue.
    2. Respect the total intensity budget. Broad area coverage means lower per-effect intensity.
    3. Passive spells are toggled auras. They may affect only the caster or environment, never enemy targets.
       Passive spells use mana_reservation, must set fatigue_cost to 0, and should feel stable rather than bursty.
    4. Utility spells are outside-combat map actions. They may use only utility states and must target "self" or "zone".
       Utility spells must set mana_reservation to 0 and avoid direct combat damage.
    5. Active spells are the default combat cast. They use fatigue_cost and must set mana_reservation to 0.
    6. Include a Russian display name in name_ru.
    7. Edge-case handling is mandatory:
       - 0 meaningful words: produce the simplest safe spell that still matches school and request.
       - 6-word formula cap: do not infer hidden extra clauses.
       - Base-spell revamp: preserve the original identity unless the request clearly asks for a different delivery or role.
    8. Failure profiles should scale with ambition. High control, wide zones, or stacked riders increase difficulty and volatility.
    9. Prefer utility/passive guards over clever loopholes. If a requested effect is unsafe, degrade it into a smaller legal effect.
    """
    |> String.trim()
  end

  def user_prompt(assigns) do
    states = Map.fetch!(assigns, :states)

    Jason.encode!(%{
      task: "compile_spell",
      character: Map.fetch!(assigns, :character),
      request: Map.fetch!(assigns, :request),
      compiler_reference: %{
        state_primitives: state_primitives(states),
        slot_reference: Incantation.slot_definitions(),
        interaction_catalogue: @interaction_catalogue,
        failure_profile_rubric: %{
          low_risk: "difficulty 1-20, volatility 0-15, predictable single-purpose effects",
          medium_risk: "difficulty 21-55, volatility 10-35, mixed payload or wider footprint",
          high_risk:
            "difficulty 56-100, volatility 25-70, stacked control, recursion, or environment rewrites"
        },
        intensity_budget_examples: [
          "single target impact 10-18 plus one rider 2-6",
          "cone or sphere damage 6-12 with very light rider",
          "passive self-ward 4-10 intensity with longer duration and mana reservation",
          "utility reveal/ward effects usually intensity 1-5"
        ],
        spell_mode_guards: %{
          active: "combat cast, fatigue_cost > 0, mana_reservation = 0",
          passive: "self/environment only, fatigue_cost = 0, mana_reservation > 0",
          utility: "utility states only, target self or zone, mana_reservation = 0"
        },
        edge_cases: %{
          blank_or_near_blank_formula: "return a conservative spell, not an empty schema",
          six_word_cap: "treat the given formula as complete; do not add imagined suffixes",
          base_spell_revamp:
            "preserve source identity and tags unless the request explicitly pivots"
        }
      },
      incantation_analysis: Map.get(assigns[:request] || %{}, "incantation_analysis"),
      engine_constraints: %{
        spell_types: ["active", "passive", "utility"],
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

  def response_schema do
    %{
      type: "object",
      properties: %{
        name: %{type: "string"},
        name_ru: %{type: "string"},
        formula: %{type: "string"},
        school: %{type: "string"},
        spell_type: %{type: "string", enum: ["active", "passive", "utility"]},
        mana_reservation: %{type: "integer"},
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
        "name_ru",
        "formula",
        "school",
        "spell_type",
        "mana_reservation",
        "description",
        "level_requirement",
        "fatigue_cost",
        "cooldown_turns",
        "targeting",
        "delivery_form",
        "tags",
        "narrative_tags",
        "environment_tags",
        "environment_mode",
        "effects",
        "interaction_rules",
        "failure_profile"
      ]
    }
  end

  defp state_primitives(states) when is_list(states) do
    states
    |> Enum.map(&to_string/1)
    |> Enum.map(fn state -> {state, Map.get(@state_reference, state, fallback_state(state))} end)
    |> Map.new()
  end

  defp state_primitives(states) when is_map(states) do
    Map.new(states, fn {state, details} ->
      state = to_string(state)

      {state,
       fallback_state(state)
       |> Map.merge(normalize_state_details(details))}
    end)
  end

  defp normalize_state_details(details) when is_map(details) do
    %{
      description: details["description"] || details[:description],
      max_intensity: details["max_intensity"] || details[:max_intensity],
      notes: details["notes"] || details[:notes]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp fallback_state(state), do: Map.get(@state_reference, state, %{category: "unknown"})
end
