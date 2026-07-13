defmodule MMGO.Combat do
  import Ecto.Query, warn: false

  alias MMGO.Actors.ActorTemplate
  alias Ecto.Multi

  alias MMGO.Combat.{
    Action,
    ActionSnapshot,
    Combat,
    Engine,
    Event,
    Participant,
    ResolveTurnWorker,
    Turn
  }

  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  @lifecycle_key "lifecycle"
  @base_turn_seconds 45
  @additional_participant_seconds 10
  @max_turn_seconds 120

  def active_combat_for_character(character_id) when is_binary(character_id) do
    Combat
    |> join(:inner, [combat], participant in assoc(combat, :participants))
    |> where(
      [combat, participant],
      participant.character_id == ^character_id and
        combat.status in [:active_turn, :locked, :resolving]
    )
    |> order_by([combat, _participant], desc: combat.inserted_at)
    |> preload(participants: [:character, :actor_template, grimoire: :entries])
    |> Repo.one()
  end

  def get_combat!(id) do
    Combat
    |> Repo.get!(id)
    |> Repo.preload(participants: [:character, :actor_template, grimoire: :entries])
  end

  @doc """
  Returns a combat with its participants when it exists.

  Unlike `get_combat!/1`, this is suitable for worker recovery paths where an
  expired job can legitimately reference a combat that has since been removed.
  Authorization still belongs to the caller; use `get_combat_for_character/2`
  for a player-facing lookup.
  """
  def get_combat(id) when is_binary(id) do
    Combat
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      combat ->
        Repo.preload(combat, participants: [:character, :actor_template, grimoire: :entries])
    end
  end

  def get_combat(_id), do: nil

  @doc """
  Returns a combat only when `character_id` belongs to one of its participants.

  This is the read boundary used by browser orchestration: knowing a combat ID
  is never enough to inspect another player's battle.
  """
  def get_combat_for_character(combat_id, character_id)
      when is_binary(combat_id) and is_binary(character_id) do
    Combat
    |> join(:inner, [combat], participant in assoc(combat, :participants))
    |> where(
      [combat, participant],
      combat.id == ^combat_id and participant.character_id == ^character_id
    )
    |> preload(participants: [:character, :actor_template, grimoire: :entries])
    |> Repo.one()
  end

  def get_combat_for_character(_combat_id, _character_id), do: nil

  def create_duel(%Realm{} = realm, attrs) when is_map(attrs) do
    create_combat_instance(realm, :duel, attrs)
  end

  def create_dungeon_encounter(%Realm{} = realm, attrs) when is_map(attrs) do
    create_combat_instance(realm, :dungeon_encounter, attrs)
  end

  def create_overworld_encounter(%Realm{} = realm, attrs) when is_map(attrs) do
    create_combat_instance(realm, :overworld_encounter, attrs)
  end

  def create_club_match(%Realm{} = realm, attrs) when is_map(attrs) do
    create_combat_instance(realm, :club_match, attrs)
  end

  defp create_combat_instance(%Realm{} = realm, kind, attrs) when is_map(attrs) do
    participant_attrs = Map.get(attrs, :participants) || Map.get(attrs, "participants") || []
    sides = build_sides(attrs, participant_attrs)
    opened_at = Map.get(attrs, :opened_at) || Map.get(attrs, "opened_at") || DateTime.utc_now()

    seed =
      Map.get(attrs, :seed) || Map.get(attrs, "seed") ||
        System.unique_integer([:positive, :monotonic])

    Multi.new()
    |> Multi.insert(
      :combat,
      Combat.changeset(%Combat{}, %{
        realm_id: realm.id,
        kind: kind,
        status: :active_turn,
        turn_number: 1,
        seed: seed,
        sides: sides,
        environment_tags:
          Map.get(attrs, :environment_tags) || Map.get(attrs, "environment_tags") || [],
        metadata: Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || %{}
      })
    )
    |> Multi.run(:participants, fn repo, %{combat: combat} ->
      insert_participants(repo, combat, participant_attrs)
    end)
    |> Multi.insert(:turn, fn %{combat: combat, participants: participants} ->
      Turn.changeset(
        %Turn{},
        new_turn_attrs(combat.id, 1, length(participants), opened_at)
      )
    end)
    |> Multi.run(:deadline_worker, fn _repo, %{combat: combat, turn: turn} ->
      schedule_turn_resolution(combat, turn)
    end)
    |> Repo.transaction()
    |> case do
      {:error, :participants, %{step: :participant, changeset: changeset, inserted: inserted},
       _changes} ->
        {:error, :participant, changeset, inserted}

      other ->
        other
    end
  end

  def submit_action(%Combat{} = combat, participant_id, attrs) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      current_combat = lock_combat!(combat.id)

      result =
        with :ok <- ensure_requested_turn_is_current(current_combat, combat.turn_number),
             {:ok, turn} <- lock_open_turn(current_combat),
             :ok <- ensure_turn_accepting_actions(turn, now),
             %Participant{} = participant <- lock_participant(participant_id, current_combat.id),
             existing_action = lock_existing_action(turn, participant),
             :ok <- release_action_reservation(existing_action),
             {:ok, snapshot} <- ActionSnapshot.normalize(current_combat, participant, attrs),
             :ok <- reserve_snapshot_item(snapshot, participant),
             {:ok, action} <- save_action(existing_action, turn, participant, snapshot, now),
             {:ok, _combat_or_turn} <- maybe_lock_turn(current_combat, turn) do
          {:ok, action}
        else
          nil -> {:error, :participant_not_found}
          {:error, reason} -> {:error, reason}
        end

      case result do
        {:ok, action} -> action
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def resolve_turn(%Combat{} = combat), do: resolve_turn(combat, [])

  def resolve_turn(%Combat{turn_number: requested_turn_number} = combat, opts)
      when is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force?, false)

    Repo.transaction(fn ->
      runtime_combat = lock_combat!(combat.id)

      with :ok <- ensure_requested_turn_is_current(runtime_combat, requested_turn_number),
           {:ok, turn} <- fetch_turn(runtime_combat, requested_turn_number),
           :ok <- ensure_turn_resolvable(turn, force?) do
        turn = claim_turn_resolution!(turn, now)

        actions =
          Action
          |> where([action], action.combat_turn_id == ^turn.id)
          |> Repo.all()
          |> Repo.preload([
            :spell,
            :participant,
            :target_participant,
            inventory_item: :item_template
          ])

        resolution =
          Engine.resolve_turn(runtime_combat, turn, runtime_combat.participants, actions)

        Enum.each(resolution.inventory_updates, fn {inventory_item_id, attrs} ->
          inventory_item = Repo.get!(InventoryItem, inventory_item_id)

          inventory_item
          |> InventoryItem.changeset(attrs)
          |> Repo.update!()
        end)

        Enum.each(runtime_combat.participants, fn participant ->
          attrs = Map.fetch!(resolution.participant_updates, participant.id)

          participant
          |> Participant.changeset(attrs)
          |> Repo.update!()
        end)

        turn
        |> Turn.changeset(resolved_turn_attrs(turn, resolution.turn_attrs, now))
        |> Repo.update!()

        Enum.each(resolution.events, fn event ->
          %Event{}
          |> Event.changeset(Map.merge(event, %{combat_id: combat.id, combat_turn_id: turn.id}))
          |> Repo.insert!()
        end)

        updated_combat =
          runtime_combat
          |> Combat.changeset(resolution.combat_attrs)
          |> Repo.update!()

        if resolution.create_next_turn? do
          next_turn =
            %Turn{}
            |> Turn.changeset(
              new_turn_attrs(
                combat.id,
                updated_combat.turn_number,
                ready_participant_count(runtime_combat.participants),
                now
              )
            )
            |> Repo.insert!()

          schedule_turn_resolution!(updated_combat, next_turn)
        end

        updated_combat
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Locks and resolves a turn only after its persisted deadline. Missing ready
  participants receive durable wait actions, making timeout resolution safe for
  reconnects and worker retries.
  """
  def resolve_due_turn(combat_id, turn_id, opts \\ [])

  def resolve_due_turn(combat_id, turn_id, opts)
      when is_binary(combat_id) and is_binary(turn_id) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, combat} <- lock_due_turn(combat_id, turn_id, now) do
      resolve_turn(combat, now: now)
    end
  end

  def resolve_due_turn(_combat_id, _turn_id, _opts), do: {:error, :turn_not_found}

  @doc """
  Resolves a specific turn that has already been sealed because every ready
  participant submitted an action. The exact turn ID prevents a delayed worker
  from falling through to a later turn.
  """
  def resolve_locked_turn(combat_id, turn_id, opts \\ [])

  def resolve_locked_turn(combat_id, turn_id, opts)
      when is_binary(combat_id) and is_binary(turn_id) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, combat} <- lock_ready_turn(combat_id, turn_id) do
      resolve_turn(combat, now: now)
    end
  end

  def resolve_locked_turn(_combat_id, _turn_id, _opts), do: {:error, :turn_not_found}

  @doc "Returns the persisted timing and resolution claim information for a turn."
  def turn_lifecycle(%Turn{resolution: resolution}) when is_map(resolution) do
    Map.get(resolution, @lifecycle_key, %{})
  end

  def turn_lifecycle(%Turn{}), do: %{}

  defp lock_combat!(combat_id) do
    Combat
    |> where([combat], combat.id == ^combat_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(participants: [:character, :actor_template, grimoire: :entries])
  end

  defp lock_open_turn(%Combat{} = combat) do
    case Turn
         |> where([turn], turn.combat_id == ^combat.id and turn.number == ^combat.turn_number)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      %Turn{status: :open} = turn -> {:ok, turn}
      %Turn{status: :locked} -> {:error, :turn_locked}
      %Turn{} -> {:error, :turn_closed}
      nil -> {:error, :turn_not_found}
    end
  end

  defp ensure_turn_accepting_actions(%Turn{} = turn, now) do
    if turn_due?(turn, now), do: {:error, :turn_deadline_elapsed}, else: :ok
  end

  defp lock_participant(participant_id, combat_id) do
    Participant
    |> where(
      [participant],
      participant.id == ^participant_id and participant.combat_id == ^combat_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> nil
      participant -> Repo.preload(participant, [:character, grimoire: :entries])
    end
  end

  defp lock_existing_action(%Turn{} = turn, %Participant{} = participant) do
    Action
    |> where(
      [action],
      action.combat_turn_id == ^turn.id and action.participant_id == ^participant.id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp save_action(existing_action, %Turn{} = turn, %Participant{} = participant, snapshot, now) do
    attrs = %{
      combat_turn_id: turn.id,
      participant_id: participant.id,
      action_type: snapshot.action_type,
      spell_id: Map.get(snapshot, :spell_id),
      inventory_item_id: Map.get(snapshot, :inventory_item_id),
      target_side: Map.get(snapshot, :target_side),
      target_participant_id: Map.get(snapshot, :target_participant_id),
      payload: Map.fetch!(snapshot, :payload),
      submitted_at: now
    }

    (existing_action || %Action{})
    |> Action.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp release_action_reservation(nil), do: :ok

  defp release_action_reservation(%Action{} = action) do
    with inventory_item_id when is_binary(inventory_item_id) <- action.inventory_item_id,
         quantity_cost when quantity_cost > 0 <- action_reservation_quantity(action),
         %InventoryItem{} = inventory_item <- lock_inventory_item(inventory_item_id) do
      inventory_item
      |> InventoryItem.changeset(%{
        reserved_quantity: max(inventory_item.reserved_quantity - quantity_cost, 0)
      })
      |> Repo.update!()
    end

    :ok
  end

  defp reserve_snapshot_item(snapshot, %Participant{} = participant) do
    case {Map.get(snapshot, :inventory_item_id), snapshot_reservation_quantity(snapshot)} do
      {nil, _quantity_cost} ->
        :ok

      {_inventory_item_id, 0} ->
        :ok

      {inventory_item_id, quantity_cost}
      when is_binary(inventory_item_id) and quantity_cost > 0 ->
        case lock_inventory_item(inventory_item_id) do
          %InventoryItem{} = inventory_item ->
            cond do
              inventory_item.character_id != participant.character_id ->
                {:error, :item_not_owned}

              Inventory.available_quantity(inventory_item) < quantity_cost ->
                {:error, :item_unavailable}

              true ->
                inventory_item
                |> InventoryItem.changeset(%{
                  reserved_quantity: inventory_item.reserved_quantity + quantity_cost
                })
                |> Repo.update!()

                :ok
            end

          nil ->
            {:error, :item_not_found}
        end

      _other ->
        {:error, :item_unavailable}
    end
  end

  defp lock_inventory_item(inventory_item_id) do
    InventoryItem
    |> where([inventory_item], inventory_item.id == ^inventory_item_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp action_reservation_quantity(%Action{payload: payload}),
    do: snapshot_reservation_quantity(payload)

  defp snapshot_reservation_quantity(snapshot) when is_map(snapshot) do
    quantity_cost =
      snapshot
      |> Map.get(:payload, snapshot)
      |> Map.get("snapshot", %{})
      |> Map.get("item_action", %{})
      |> Map.get("quantity_cost", 0)

    if is_integer(quantity_cost) and quantity_cost > 0, do: quantity_cost, else: 0
  end

  defp snapshot_reservation_quantity(_snapshot), do: 0

  defp fetch_turn(%Combat{} = combat, turn_number) do
    case Repo.get_by(Turn, combat_id: combat.id, number: turn_number) do
      %Turn{} = turn -> {:ok, turn}
      nil -> {:error, :turn_not_found}
    end
  end

  # Only a deadline worker or the final sealing action may enter normal
  # resolution. `force?` exists for isolated engine fixtures and privileged
  # maintenance paths; browser and Telegram commands never pass it.
  defp ensure_turn_resolvable(%Turn{status: :locked}, _force?), do: :ok
  defp ensure_turn_resolvable(%Turn{status: :open}, true), do: :ok
  defp ensure_turn_resolvable(%Turn{status: :open}, false), do: {:error, :turn_open}
  defp ensure_turn_resolvable(%Turn{}, _force?), do: {:error, :turn_closed}

  # A resolver is an intent for the turn visible to its caller. Once a prior
  # resolver advances the combat, a delayed request must never fall through to
  # resolve the newly-created next turn.
  defp ensure_requested_turn_is_current(%Combat{turn_number: number}, number), do: :ok

  defp ensure_requested_turn_is_current(%Combat{}, _requested_turn_number),
    do: {:error, :turn_closed}

  defp lock_due_turn(combat_id, turn_id, now) do
    Repo.transaction(fn ->
      case lock_combat(combat_id) do
        nil ->
          Repo.rollback(:combat_not_found)

        %Combat{} = combat ->
          case lock_turn(turn_id) do
            nil ->
              Repo.rollback(:turn_not_found)

            %Turn{} = turn ->
              cond do
                turn.combat_id != combat.id ->
                  Repo.rollback(:turn_not_found)

                combat.turn_number != turn.number ->
                  Repo.rollback(:turn_closed)

                turn.status not in [:open, :locked] ->
                  Repo.rollback(:turn_closed)

                not turn_due?(turn, now) ->
                  Repo.rollback(:turn_not_due)

                true ->
                  materialize_timeout_waits!(combat, turn, now)
                  _locked_turn = lock_turn!(turn, now)

                  combat
                  |> Combat.changeset(%{status: :locked})
                  |> Repo.update!()
              end
          end
      end
    end)
  end

  defp lock_ready_turn(combat_id, turn_id) do
    Repo.transaction(fn ->
      case lock_combat(combat_id) do
        nil ->
          Repo.rollback(:combat_not_found)

        %Combat{} = combat ->
          case lock_turn(turn_id) do
            nil ->
              Repo.rollback(:turn_not_found)

            %Turn{} = turn ->
              cond do
                turn.combat_id != combat.id -> Repo.rollback(:turn_not_found)
                combat.turn_number != turn.number -> Repo.rollback(:turn_closed)
                turn.status != :locked -> Repo.rollback(:turn_not_locked)
                true -> combat
              end
          end
      end
    end)
  end

  defp lock_combat(combat_id) do
    case Combat
         |> where([combat], combat.id == ^combat_id)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil ->
        nil

      combat ->
        Repo.preload(combat, participants: [:character, :actor_template, grimoire: :entries])
    end
  end

  defp lock_turn(turn_id) do
    Turn
    |> where([turn], turn.id == ^turn_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp materialize_timeout_waits!(%Combat{} = combat, %Turn{} = turn, now) do
    submitted_participant_ids =
      Action
      |> where([action], action.combat_turn_id == ^turn.id)
      |> select([action], action.participant_id)
      |> Repo.all()
      |> MapSet.new()

    Participant
    |> where([participant], participant.combat_id == ^combat.id and participant.status == :ready)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(submitted_participant_ids, &1.id))
    |> Enum.each(fn participant ->
      %Action{}
      |> Action.changeset(%{
        combat_turn_id: turn.id,
        participant_id: participant.id,
        action_type: :wait,
        submitted_at: now,
        payload: %{"source" => "turn_deadline"}
      })
      |> Repo.insert!(
        on_conflict: :nothing,
        conflict_target: [:combat_turn_id, :participant_id]
      )
    end)
  end

  defp turn_due?(%Turn{} = turn, now) do
    with {:ok, deadline_at} <- turn_deadline_at(turn) do
      DateTime.compare(now, deadline_at) in [:eq, :gt]
    else
      _ -> false
    end
  end

  defp claim_turn_resolution!(%Turn{} = turn, now) do
    turn
    |> Turn.changeset(%{
      status: :resolving,
      resolution:
        put_turn_lifecycle(turn, %{
          "resolution_claimed_at" => DateTime.to_iso8601(now),
          "resolution_token" => Ecto.UUID.generate()
        })
    })
    |> Repo.update!()
  end

  defp resolved_turn_attrs(%Turn{} = turn, turn_attrs, now) do
    lifecycle =
      turn
      |> turn_lifecycle()
      |> Map.put("resolved_at", DateTime.to_iso8601(now))

    Map.update!(turn_attrs, :resolution, &Map.put(&1, @lifecycle_key, lifecycle))
  end

  defp lock_turn!(%Turn{} = turn, now) do
    turn
    |> Turn.changeset(%{
      status: :locked,
      resolution: put_turn_lifecycle(turn, %{"locked_at" => DateTime.to_iso8601(now)})
    })
    |> Repo.update!()
  end

  defp new_turn_attrs(combat_id, number, participant_count, opened_at) do
    opened_at = normalize_turn_time(opened_at)
    duration_seconds = turn_duration_seconds(participant_count)

    %{
      combat_id: combat_id,
      number: number,
      status: :open,
      resolution: %{
        @lifecycle_key => %{
          "opened_at" => DateTime.to_iso8601(opened_at),
          "deadline_at" =>
            opened_at
            |> DateTime.add(duration_seconds, :second)
            |> DateTime.to_iso8601(),
          "deadline_seconds" => duration_seconds
        }
      }
    }
  end

  defp normalize_turn_time(%DateTime{} = opened_at), do: opened_at
  defp normalize_turn_time(_opened_at), do: DateTime.utc_now()

  defp turn_duration_seconds(participant_count) do
    participant_count
    |> Kernel.-(2)
    |> max(0)
    |> Kernel.*(@additional_participant_seconds)
    |> Kernel.+(@base_turn_seconds)
    |> min(@max_turn_seconds)
  end

  defp turn_deadline_at(%Turn{} = turn) do
    case Map.get(turn_lifecycle(turn), "deadline_at") do
      deadline_at when is_binary(deadline_at) ->
        case DateTime.from_iso8601(deadline_at) do
          {:ok, parsed, _offset} -> {:ok, parsed}
          _ -> {:error, :turn_deadline_missing}
        end

      _other ->
        {:error, :turn_deadline_missing}
    end
  end

  defp put_turn_lifecycle(%Turn{} = turn, attrs) do
    turn.resolution
    |> Kernel.||(%{})
    |> Map.put(@lifecycle_key, Map.merge(turn_lifecycle(turn), attrs))
  end

  defp ready_participant_count(participants) do
    Enum.count(participants, &(&1.status == :ready))
  end

  defp schedule_turn_resolution(%Combat{} = combat, %Turn{} = turn) do
    with {:ok, deadline_at} <- turn_deadline_at(turn) do
      %{"combat_id" => combat.id, "turn_id" => turn.id}
      |> ResolveTurnWorker.new(
        schedule_in: max(DateTime.diff(deadline_at, DateTime.utc_now(), :second), 0)
      )
      |> Oban.insert()
    end
  end

  defp schedule_turn_resolution!(%Combat{} = combat, %Turn{} = turn) do
    case schedule_turn_resolution(combat, turn) do
      {:ok, _job} -> :ok
      {:error, reason} -> raise "could not schedule combat turn deadline: #{inspect(reason)}"
    end
  end

  defp schedule_locked_turn_resolution(%Combat{} = combat, %Turn{} = turn) do
    %{"combat_id" => combat.id, "turn_id" => turn.id, "trigger" => "all_actions"}
    |> ResolveTurnWorker.new()
    |> Oban.insert()
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
      locked_turn = lock_turn!(turn, DateTime.utc_now())

      with {:ok, _combat} <-
             combat
             |> Combat.changeset(%{status: :locked})
             |> Repo.update(),
           {:ok, _job} <- schedule_locked_turn_resolution(combat, locked_turn) do
        {:ok, locked_turn}
      end
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

      character_id = attrs[:character_id] || attrs["character_id"]
      actor_template_id = attrs[:actor_template_id] || attrs["actor_template_id"]
      provided_grimoire_id = attrs[:grimoire_id] || attrs["grimoire_id"]

      attrs = participant_defaults(attrs, character_id, actor_template_id)

      case resolve_grimoire(character_id, provided_grimoire_id) do
        {:ok, grimoire} ->
          attrs = Map.put(attrs, :grimoire_id, grimoire && grimoire.id)

          case %Participant{} |> Participant.changeset(attrs) |> repo.insert() do
            {:ok, participant} ->
              {:cont, {:ok, [participant | inserted]}}

            {:error, changeset} ->
              {:halt, {:error, %{step: :participant, changeset: changeset, inserted: inserted}}}
          end

        {:error, changeset} ->
          {:halt, {:error, %{step: :participant, changeset: changeset, inserted: inserted}}}
      end
    end)
  end

  defp resolve_grimoire(character_id, provided_grimoire_id) when is_binary(character_id) do
    Grimoires.resolve_selected_grimoire(character_id, provided_grimoire_id)
  end

  defp resolve_grimoire(_character_id, _provided_grimoire_id), do: {:ok, nil}

  defp participant_defaults(attrs, character_id, nil) when is_binary(character_id) do
    character = Repo.get!(MMGO.Accounts.Character, character_id)

    attrs
    |> Map.put_new(:display_name, character.name)
    |> Map.put_new(:combat_level, character.level)
  end

  defp participant_defaults(attrs, _character_id, actor_template_id)
       when is_binary(actor_template_id) do
    actor_template = Repo.get!(ActorTemplate, actor_template_id)

    attrs
    |> Map.put_new(:display_name, actor_template.name)
    |> Map.put_new(:combat_level, actor_template.combat_level)
  end

  defp participant_defaults(attrs, _character_id, _actor_template_id), do: attrs

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
  defp side_label("party"), do: "Party"
  defp side_label("encounter"), do: "Encounter"
  defp side_label(side), do: side |> to_string() |> String.capitalize()

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
