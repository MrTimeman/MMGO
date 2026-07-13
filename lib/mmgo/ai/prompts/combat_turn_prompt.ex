defmodule MMGO.AI.Prompts.CombatTurnPrompt do
  @moduledoc """
  Prompt contract for bounded runtime spell orchestration.

  The envelope deliberately contains only server-approved casts and their
  mechanical budgets. The provider can describe/select within that envelope;
  it never receives persistence authority, rewards, arbitrary targets, or a
  writable shared-HP value.
  """

  alias MMGO.AI.PromptVersions

  def build(envelope) when is_map(envelope) do
    %{
      kind: "combat_orchestration",
      prompt_version: PromptVersions.for!(:combat_orchestration),
      system_prompt: system_prompt(),
      user_prompt: Jason.encode!(envelope),
      schema: response_schema()
    }
  end

  defp system_prompt do
    """
    Ты — ограниченный оркестратор магии MMGO. Пиши JSON, соответствующий схеме.

    Тебе передан неизменяемый серверный конверт уже запечатанных заклинаний. Ты
    можешь выбрать только цели и состояния, буквально перечисленные в `casters`;
    интенсивность и длительность не могут превышать соответствующее разрешённое
    значение. Не добавляй новых состояний, эффектов среды, наград, затрат,
    отмен действий, участников, сторон или чисел HP. Механический движок остаётся
    единственным источником истины. `narrative_ru` — короткое русское описание
    того, как эти уже допустимые проявления ощущаются в сцене.
    """
    |> String.trim()
  end

  defp response_schema do
    %{
      type: "object",
      properties: %{
        casts: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              participant_id: %{type: "string"},
              target_participant_id: %{type: ["string", "null"]},
              effects: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    applies_to: %{type: "string"},
                    state: %{type: "string"},
                    intensity: %{type: "integer"},
                    duration: %{type: "integer"}
                  },
                  required: ["applies_to", "state", "intensity", "duration"]
                }
              }
            },
            required: ["participant_id", "target_participant_id", "effects"]
          }
        },
        narrative_ru: %{type: "string"}
      },
      required: ["casts", "narrative_ru"]
    }
  end
end
