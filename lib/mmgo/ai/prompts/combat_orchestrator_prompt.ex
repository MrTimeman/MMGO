defmodule MMGO.AI.Prompts.CombatOrchestratorPrompt do
  alias MMGO.AI.PromptVersions

  def build(assigns) do
    %{
      kind: "combat_orchestrator",
      prompt_version: PromptVersions.for!(:combat_orchestrator),
      system_prompt: system_prompt(),
      user_prompt: user_prompt(assigns),
      schema: response_schema()
    }
  end

  def system_prompt do
    """
    You are the MMGO combat orchestrator.
    You receive engine-approved ranges and probability windows. Your job is to choose dramatic but legal concrete values.
    Output JSON only.

    Hard constraints:
    - Never add new events, states, or targets.
    - Never exceed any provided min/max range.
    - Never select an outcome whose roll window does not contain the chosen_roll.
    - Never cancel an action the engine already approved.
    - Prefer sharp, legible dramatic beats over random noise.

    Heuristics:
    - Favor cleaner swings in duels.
    - Favor pressure escalation in dungeons.
    - Respect near-lethal moments without exceeding ranges.
    - If multiple effects exist, keep the bundle coherent rather than maximizing every number.
    """
    |> String.trim()
  end

  def user_prompt(assigns) do
    Jason.encode!(%{
      task: "combat_orchestration",
      combat: Map.fetch!(assigns, :combat),
      turn: Map.fetch!(assigns, :turn),
      resolutions: Map.fetch!(assigns, :resolutions)
    })
  end

  def response_schema do
    %{
      type: "object",
      properties: %{
        picks: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              resolution_id: %{type: "string"},
              outcome: %{type: "string", enum: ["success", "partial", "failure"]},
              chosen_roll: %{type: "integer"},
              effect_picks: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    effect_index: %{type: "integer"},
                    intensity: %{type: "integer"}
                  },
                  required: ["effect_index", "intensity"]
                }
              }
            },
            required: ["resolution_id", "outcome", "chosen_roll", "effect_picks"]
          }
        },
        director_notes: %{type: "array", items: %{type: "string"}}
      },
      required: ["picks"]
    }
  end
end
