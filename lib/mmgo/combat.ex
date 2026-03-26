defmodule MMGO.Combat do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias MMGO.Combat.{Action, Combat, Engine, Event, Participant, Turn}
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def get_combat!(id) do
    Combat
    |> Repo.get!(id)
    |> Repo.preload(participants: [:character])
  end

  def create_duel(%Realm{} = realm, attrs) when is_map(attrs) do
    participant_attrs = Map.get(attrs, :participants) || Map.get(attrs, "participants") || []
    sides = build_sides(attrs, participant_attrs)

    seed =
      Map.get(attrs, :seed) || Map.get(attrs, "seed") ||
        System.unique_integer([:positive, :monotonic])

    Multi.new()
    |> Multi.insert(
      :combat,
      Combat.changeset(%Combat{}, %{
        realm_id: realm.id,
        kind: :duel,
        status: :active_turn,
        turn_number: 1,
        seed: seed,
        sides: sides,
        environment_tags:
          Map.get(attrs, :environment_tags) || Map.get(attrs, "environment_tags") || []
      })
    )
    |> Multi.run(:participants, fn repo, %{combat: combat} ->
      insert_participants(repo, combat, participant_attrs)
    end)
    |> Multi.insert(:turn, fn %{combat: combat} ->
      Turn.changeset(%Turn{}, %{combat_id: combat.id, number: 1, status: :open})
    end)
    |> Repo.transaction()
  end

  def submit_action(%Combat{} = combat, participant_id, attrs) do
    with {:ok, turn} <- fetch_open_turn(combat),
         %Participant{} = participant <-
           Repo.get_by(Participant, id: participant_id, combat_id: combat.id) do
      attrs =
        attrs
        |> Map.new(fn {key, value} -> {key, value} end)
        |> Map.put(:combat_turn_id, turn.id)
        |> Map.put(:participant_id, participant.id)
        |> Map.put_new(:submitted_at, DateTime.utc_now())

      action =
        Repo.get_by(Action, combat_turn_id: turn.id, participant_id: participant.id) || %Action{}

      result =
        action
        |> Action.changeset(attrs)
        |> Repo.insert_or_update()

      with {:ok, _action} <- result do
        maybe_lock_turn(combat, turn)
      end
    else
      nil -> {:error, :participant_not_found}
      error -> error
    end
  end

  def resolve_turn(%Combat{} = combat) do
    with {:ok, turn} <- fetch_turn(combat, combat.turn_number) do
      runtime_combat =
        combat
        |> Repo.preload(participants: [:character])

      actions =
        Action
        |> where([action], action.combat_turn_id == ^turn.id)
        |> Repo.all()
        |> Repo.preload([:spell, :participant, :target_participant])

      resolution = Engine.resolve_turn(runtime_combat, turn, runtime_combat.participants, actions)

      Repo.transaction(fn ->
        Enum.each(runtime_combat.participants, fn participant ->
          attrs = Map.fetch!(resolution.participant_updates, participant.id)

          participant
          |> Participant.changeset(attrs)
          |> Repo.update!()
        end)

        turn
        |> Turn.changeset(resolution.turn_attrs)
        |> Repo.update!()

        Enum.each(resolution.events, fn event ->
          %Event{}
          |> Event.changeset(Map.merge(event, %{combat_id: combat.id, combat_turn_id: turn.id}))
          |> Repo.insert!()
        end)

        updated_combat =
          combat
          |> Combat.changeset(resolution.combat_attrs)
          |> Repo.update!()

        if resolution.create_next_turn? do
          %Turn{}
          |> Turn.changeset(%{
            combat_id: combat.id,
            number: updated_combat.turn_number,
            status: :open
          })
          |> Repo.insert!()
        end

        updated_combat
      end)
    end
  end

  defp fetch_open_turn(%Combat{} = combat) do
    case Repo.get_by(Turn, combat_id: combat.id, number: combat.turn_number) do
      %Turn{status: status} = turn when status in [:open, :locked] -> {:ok, turn}
      nil -> {:error, :turn_not_found}
      _turn -> {:error, :turn_closed}
    end
  end

  defp fetch_turn(%Combat{} = combat, turn_number) do
    case Repo.get_by(Turn, combat_id: combat.id, number: turn_number) do
      %Turn{} = turn -> {:ok, turn}
      nil -> {:error, :turn_not_found}
    end
  end

  defp maybe_lock_turn(%Combat{} = combat, %Turn{} = turn) do
    active_count =
      Participant
      |> where(
        [participant],
        participant.combat_id == ^combat.id and participant.status == :ready
      )
      |> Repo.aggregate(:count, :id)

    submitted_count =
      Action
      |> where([action], action.combat_turn_id == ^turn.id)
      |> Repo.aggregate(:count, :id)

    if submitted_count >= active_count and active_count > 0 do
      turn
      |> Turn.changeset(%{status: :locked})
      |> Repo.update()

      combat
      |> Combat.changeset(%{status: :locked})
      |> Repo.update()
    else
      {:ok, turn}
    end
  end

  defp insert_participants(repo, %Combat{} = combat, participant_attrs) do
    Enum.reduce_while(participant_attrs, {:ok, []}, fn attrs, {:ok, inserted} ->
      attrs =
        attrs
        |> Map.new(fn {key, value} -> {key, value} end)
        |> Map.put(:combat_id, combat.id)

      case %Participant{} |> Participant.changeset(attrs) |> repo.insert() do
        {:ok, participant} -> {:cont, {:ok, [participant | inserted]}}
        {:error, changeset} -> {:halt, {:error, :participant, changeset, inserted}}
      end
    end)
  end

  defp build_sides(attrs, participant_attrs) do
    provided_sides = Map.get(attrs, :sides) || Map.get(attrs, "sides") || %{}

    sides_from_participants =
      participant_attrs
      |> Enum.reduce(%{}, fn attrs, acc ->
        side = Map.get(attrs, :side) || Map.get(attrs, "side")

        Map.put_new(acc, to_string(side), %{
          "label" => side_label(side),
          "shared_hp" => 100,
          "max_shared_hp" => 100
        })
      end)

    Map.merge(sides_from_participants, stringify_keys(provided_sides), fn _key,
                                                                          inferred,
                                                                          provided ->
      Map.merge(inferred, provided)
    end)
  end

  defp side_label("attackers"), do: "Attackers"
  defp side_label("defenders"), do: "Defenders"
  defp side_label(side), do: side |> to_string() |> String.capitalize()

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
