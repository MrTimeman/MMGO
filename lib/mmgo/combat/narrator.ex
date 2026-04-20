defmodule MMGO.Combat.Narrator do
  import Ecto.Query, warn: false

  alias MMGO.AI
  alias MMGO.AI.Prompts.TurnNarrationPrompt
  alias MMGO.Combat
  alias MMGO.Combat.{Event, Turn}
  alias MMGO.Repo

  def narrate_turn(combat_id, turn_number, opts \\ []) do
    combat = Combat.get_combat!(combat_id)
    turn = Repo.get_by!(Turn, combat_id: combat_id, number: turn_number)

    event_payloads =
      Event
      |> where([event], event.combat_turn_id == ^turn.id)
      |> order_by([event], asc: event.sequence)
      |> Repo.all()
      |> Enum.map(fn event ->
        %{
          type: event.event_type,
          sequence: event.sequence,
          payload: event.payload
        }
      end)

    prompt_payload =
      TurnNarrationPrompt.build(%{
        combat: %{
          id: combat.id,
          kind: combat.kind,
          status: combat.status,
          turn_number: combat.turn_number,
          environment_tags: combat.environment_tags,
          sides: combat.sides,
          metadata: combat.metadata || %{}
        },
        turn: %{
          id: turn.id,
          number: turn.number,
          status: turn.status
        },
        events: event_payloads
      })

    ai_opts = Keyword.put_new(opts, :metadata, %{combat_id: combat.id, combat_turn_id: turn.id})

    with {:ok, %{narration: narration}} <- AI.narrate_turn(prompt_payload, ai_opts),
         narration <- validate_narration(narration, turn),
         {:ok, updated_turn} <- Turn.changeset(turn, %{narration: narration}) |> Repo.update() do
      {:ok, updated_turn}
    end
  end

  defp validate_narration(narration, %Turn{} = turn) when is_binary(narration) do
    if String.match?(narration, ~r/[А-Яа-яЁё]/u) do
      narration
    else
      turn.narration || "Ход #{turn.number} завершён."
    end
  end

  defp validate_narration(_narration, %Turn{} = turn) do
    turn.narration || "Ход #{turn.number} завершён."
  end
end
