defmodule MMGO.Combat.Narrator do
  import Ecto.Query, warn: false

  alias MMGO.AI
  alias MMGO.AI.Prompts.TurnNarrationPrompt
  alias MMGO.Combat
  alias MMGO.Combat.{Event, Participant, Turn}
  alias MMGO.Repo

  @narration_key "narration"

  def narrate_turn(combat_id, turn_number, opts \\ []) do
    combat = Combat.get_combat!(combat_id)
    turn = Repo.get_by!(Turn, combat_id: combat_id, number: turn_number)

    if persisted_narration?(turn) do
      {:ok, turn}
    else
      persist_narration(combat, turn, opts)
    end
  end

  defp persist_narration(combat, turn, opts) do
    participants =
      Participant
      |> where([participant], participant.combat_id == ^combat.id)
      |> Repo.all()

    participants_by_id =
      Map.new(participants, fn p ->
        {p.id,
         %{
           name: p.display_name,
           side: p.side,
           level: p.combat_level,
           active_states: Enum.map(p.active_states || [], & &1["state"])
         }}
      end)

    event_payloads =
      Event
      |> where([event], event.combat_turn_id == ^turn.id)
      |> order_by([event], asc: event.sequence)
      |> Repo.all()
      |> Enum.map(fn event ->
        %{
          type: event.event_type,
          sequence: event.sequence,
          payload: resolve_names(event.payload, participants_by_id)
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
          sides: annotate_sides(combat.sides, participants_by_id)
        },
        turn: %{
          id: turn.id,
          number: turn.number,
          status: turn.status,
          orchestration: Map.get(turn.resolution || %{}, "orchestration", %{})
        },
        events: event_payloads
      })

    ai_opts = Keyword.put_new(opts, :metadata, %{combat_id: combat.id, combat_turn_id: turn.id})

    case AI.narrate_turn(prompt_payload, ai_opts) do
      {:ok, %{narration: narration}} when is_binary(narration) ->
        case String.trim(narration) do
          "" ->
            persist_turn_narration(turn, fallback_narration(turn, event_payloads), "fallback")

          trimmed ->
            persist_turn_narration(turn, trimmed, "provider")
        end

      {:ok, _result} ->
        persist_turn_narration(turn, fallback_narration(turn, event_payloads), "fallback")

      {:error, _reason} ->
        persist_turn_narration(turn, fallback_narration(turn, event_payloads), "fallback")
    end
  end

  defp fallback_narration(turn, event_payloads) do
    count = length(event_payloads)

    case Map.get(turn.resolution || %{}, "orchestration", %{}) do
      %{"result" => %{"narrative_ru" => narrative}}
      when is_binary(narrative) and narrative != "" ->
        "Ход #{turn.number} завершён. #{narrative}"

      _other when count == 0 ->
        "Ход #{turn.number} завершён: стороны выждали, и поле боя осталось напряжённо тихим."

      _other ->
        "Ход #{turn.number} завершён: движок сохранил #{count} событий по запечатанным действиям."
    end
  end

  defp persist_turn_narration(turn, narration, source) do
    resolution =
      turn.resolution
      |> Kernel.||(%{})
      |> Map.put(@narration_key, %{"source" => source})

    turn
    |> Turn.changeset(%{narration: narration, resolution: resolution})
    |> Repo.update()
  end

  defp persisted_narration?(%Turn{resolution: resolution}) when is_map(resolution) do
    match?(%{}, Map.get(resolution, @narration_key))
  end

  defp persisted_narration?(_turn), do: false

  defp resolve_names(payload, participants_by_id) when is_map(payload) do
    payload
    |> maybe_add_name("participant_id", "participant_name", participants_by_id)
    |> maybe_add_name("target_participant_id", "target_participant_name", participants_by_id)
  end

  defp resolve_names(payload, _), do: payload

  defp maybe_add_name(payload, id_key, name_key, participants_by_id) do
    case Map.get(payload, id_key) do
      nil -> payload
      id -> Map.put_new(payload, name_key, get_in(participants_by_id, [id, :name]) || id)
    end
  end

  defp annotate_sides(sides, participants_by_id) when is_map(sides) do
    participants_by_side =
      participants_by_id
      |> Map.values()
      |> Enum.group_by(& &1.side)
      |> Map.new(fn {side, ps} -> {side, Enum.map(ps, & &1.name)} end)

    Map.merge(sides, participants_by_side, fn _side, side_data, names ->
      Map.put(side_data, "participants", names)
    end)
  end

  defp annotate_sides(sides, _), do: sides
end
