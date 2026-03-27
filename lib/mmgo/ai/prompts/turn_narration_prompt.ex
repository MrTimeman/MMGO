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

  defp system_prompt do
    """
    You narrate MMGO combat turns in vivid but concise prose.
    Do not invent mechanics. Only describe the provided resolved events.
    Keep the text suitable for a text-based MMO combat log.
    """
    |> String.trim()
  end

  defp user_prompt(assigns) do
    Jason.encode!(%{
      task: "narrate_turn",
      combat: Map.fetch!(assigns, :combat),
      turn: Map.fetch!(assigns, :turn),
      events: Map.fetch!(assigns, :events)
    })
  end
end
