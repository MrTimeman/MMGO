defmodule MMGO.AI.Prompts.DungeonTickPrompt do
  alias MMGO.AI.PromptVersions

  def build(assigns) do
    %{
      kind: "dungeon_tick",
      prompt_version: PromptVersions.for!(:dungeon_tick),
      system_prompt: system_prompt(),
      user_prompt: user_prompt(assigns),
      schema: response_schema()
    }
  end

  def system_prompt do
    """
    You are the MMGO dungeon macro director.
    Output JSON only. You may only emit bounded mutation directives for the supplied floors.
    Never create new floors or nodes. Never exceed the allowed mutation caps.
    Favor small, legible shifts that react to recent player pressure and resource saturation.
    """
    |> String.trim()
  end

  def user_prompt(assigns) do
    Jason.encode!(%{
      task: "dungeon_tick",
      dungeon: Map.fetch!(assigns, :dungeon),
      state: Map.fetch!(assigns, :state),
      floors: Map.fetch!(assigns, :floors),
      activity_window: Map.fetch!(assigns, :activity_window),
      mutation_caps: %{
        threat_delta: [-5, 5],
        resource_delta: [-5, 5],
        connection_shift: ["stabilize", "block", "open"],
        anomaly_tag: ["none", "volatile", "wrath", "depleted", "echo", "predator"]
      }
    })
  end

  def response_schema do
    %{
      type: "object",
      properties: %{
        floor_directives: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              floor_id: %{type: "string"},
              threat_delta: %{type: "integer"},
              resource_delta: %{type: "integer"},
              connection_shift: %{
                type: "string",
                enum: ["stabilize", "block", "open"]
              },
              anomaly_tag: %{
                type: "string",
                enum: ["none", "volatile", "wrath", "depleted", "echo", "predator"]
              }
            },
            required: [
              "floor_id",
              "threat_delta",
              "resource_delta",
              "connection_shift",
              "anomaly_tag"
            ]
          }
        },
        summary: %{type: "string"}
      },
      required: ["floor_directives"]
    }
  end
end
