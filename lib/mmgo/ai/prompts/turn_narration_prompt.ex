defmodule MMGO.AI.Prompts.TurnNarrationPrompt do
  alias MMGO.AI.PromptVersions

  def build(assigns) do
    %{
      kind: "turn_narration",
      prompt_version: PromptVersions.for!(:turn_narration),
      system_prompt: system_prompt(),
      user_prompt: user_prompt(assigns)
    }
  end

  def system_prompt do
    """
    You narrate MMGO combat turns for MMGO.
    Output Russian only.
    Do not invent mechanics, locations, casualties, summons, motives, or outcomes that are not present in the input.
    The narration must stay faithful to resolved events and feel like a premium combat log entry.

    Style rules:
    - Duel: taut, precise, personal.
    - Dungeon trash: brisk, hazardous, spatial.
    - Boss: ominous, weighty, consequence-forward.
    - PvP ambush: sharp, sudden, predatory.

    Must mention when present:
    - environment ticks or replacement tags
    - break conditions such as silenced, staggered, exposed, shield consumption
    - summons or linked actors if events reference them

    Length budget:
    - 1-2 events: 1 short sentence
    - 3-5 events: 2 sentences
    - 6+ events: up to 3 compact sentences

    Example bad output: invents a collapsing ceiling when no such event exists.
    Example good output: rephrases only the provided hits, states, and reversals in Russian.
    """
    |> String.trim()
  end

  def user_prompt(assigns) do
    combat = Map.fetch!(assigns, :combat)
    events = Map.fetch!(assigns, :events)

    Jason.encode!(%{
      task: "narrate_turn",
      combat: combat,
      turn: Map.fetch!(assigns, :turn),
      events: events,
      narration_contract: %{
        language: "ru",
        tone_bucket: tone_bucket(combat),
        max_sentences: sentence_budget(events),
        no_invention: true
      }
    })
  end

  defp tone_bucket(combat) do
    combat_kind = combat[:kind] || combat["kind"]
    metadata = combat[:metadata] || combat["metadata"] || %{}
    encounter_kind = metadata[:encounter_kind] || metadata["encounter_kind"]

    cond do
      combat_kind == :duel or combat_kind == "duel" -> "duel"
      encounter_kind in [:boss, "boss"] -> "boss"
      combat_kind in [:overworld_encounter, "overworld_encounter"] -> "pvp_ambush"
      true -> "dungeon_trash"
    end
  end

  defp sentence_budget(events) when is_list(events) do
    cond do
      length(events) <= 2 -> 1
      length(events) <= 5 -> 2
      true -> 3
    end
  end
end
