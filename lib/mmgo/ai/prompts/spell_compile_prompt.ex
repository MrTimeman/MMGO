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
    You are the MMGO spell compiler. Convert the player's incantation into a deterministic spell spec.
    Never invent unsupported state ids. Stay inside the supplied runtime schema and intensity budget.
    Return JSON only.
    """
    |> String.trim()
  end

  defp user_prompt(assigns) do
    Jason.encode!(%{
      task: "compile_spell",
      character: Map.fetch!(assigns, :character),
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
