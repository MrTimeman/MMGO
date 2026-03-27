defmodule MMGO.Dungeons do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Dungeons.{Dungeon, Floor, Link, Node, NodeState, Run}
  alias MMGO.Parties.Expedition
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def list_dungeons_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from dungeon in Dungeon,
        where: dungeon.realm_id == ^realm_id,
        order_by: [asc: dungeon.inserted_at]
    )
  end

  def get_dungeon!(id) do
    Dungeon
    |> Repo.get!(id)
    |> Repo.preload([:entrance_location, floors: [nodes: []]])
  end

  def get_dungeon_by_slug(realm_id, slug) when is_binary(realm_id) and is_binary(slug) do
    Repo.get_by(Dungeon, realm_id: realm_id, slug: slug)
  end

  def create_dungeon(%Realm{} = realm, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "realm_id", realm.id)

    %Dungeon{}
    |> Dungeon.changeset(attrs)
    |> Repo.insert()
  end

  def create_floor(%Dungeon{} = dungeon, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "dungeon_id", dungeon.id)

    %Floor{}
    |> Floor.changeset(attrs)
    |> Repo.insert()
  end

  def create_node(%Floor{} = floor, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "floor_id", floor.id)

    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  def create_link(%Dungeon{} = dungeon, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "dungeon_id", dungeon.id)

    %Link{}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  def active_run_for_expedition(expedition_id) when is_binary(expedition_id) do
    Repo.get_by(Run, expedition_id: expedition_id, status: :active)
  end

  def get_run!(id) do
    Run
    |> Repo.get!(id)
    |> preload_run()
  end

  def enter_dungeon(%Expedition{} = expedition, %Dungeon{} = dungeon, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      expedition = lock_expedition!(expedition.id)
      dungeon = Repo.get!(Dungeon, dungeon.id)

      validate_run_entry!(expedition, dungeon)

      if active_run_for_expedition(expedition.id) do
        Repo.rollback(run_changeset("expedition already has an active dungeon run"))
      end

      entrance_node =
        case Keyword.get(opts, :entrance_node_id) do
          nil -> default_entrance_node!(dungeon.id)
          entrance_node_id -> Repo.get!(Node, entrance_node_id)
        end

      if not node_belongs_to_dungeon?(entrance_node, dungeon.id) do
        Repo.rollback(run_changeset("entrance node does not belong to this dungeon"))
      end

      run =
        %Run{}
        |> Run.changeset(%{
          expedition_id: expedition.id,
          dungeon_id: dungeon.id,
          current_floor_id: entrance_node.floor_id,
          current_node_id: entrance_node.id,
          status: :active,
          started_at: now,
          last_progressed_at: now,
          steps_taken: 0
        })
        |> Repo.insert!()

      node_state =
        %NodeState{}
        |> NodeState.changeset(%{
          run_id: run.id,
          node_id: entrance_node.id,
          status: :current,
          encounter_status: :pending,
          resource_status: :unknown,
          visit_count: 1,
          entered_at: now,
          last_seen_at: now,
          metadata: %{"first_entry" => true}
        })
        |> Repo.insert!()

      %{run: preload_run(run), node_state: node_state}
    end)
    |> normalize_transaction_result()
  end

  def move_run(%Run{} = run, target_node_id, opts \\ []) when is_binary(target_node_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    leave_status = normalize_node_status(Keyword.get(opts, :leave_status, :visited))

    Repo.transaction(fn ->
      run = lock_run!(run.id)

      if run.status != :active do
        Repo.rollback(run_changeset("run is not active"))
      end

      target_node = Repo.get!(Node, target_node_id)

      if not node_belongs_to_dungeon?(target_node, run.dungeon_id) do
        Repo.rollback(run_changeset("target node does not belong to this dungeon"))
      end

      link = find_link!(run.current_node_id, target_node.id)

      current_state =
        NodeState
        |> where([state], state.run_id == ^run.id and state.node_id == ^run.current_node_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      current_state
      |> NodeState.changeset(%{status: leave_status, left_at: now, last_seen_at: now})
      |> Repo.update!()

      target_state =
        NodeState
        |> where([state], state.run_id == ^run.id and state.node_id == ^target_node.id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      target_state =
        case target_state do
          nil ->
            %NodeState{}
            |> NodeState.changeset(%{
              run_id: run.id,
              node_id: target_node.id,
              status: :current,
              encounter_status: :pending,
              resource_status: :unknown,
              visit_count: 1,
              entered_at: now,
              last_seen_at: now,
              metadata: %{}
            })
            |> Repo.insert!()

          %NodeState{} = existing_state ->
            existing_state
            |> NodeState.changeset(%{
              status: :current,
              visit_count: existing_state.visit_count + 1,
              entered_at: now,
              last_seen_at: now
            })
            |> Repo.update!()
        end

      updated_run =
        run
        |> Run.changeset(%{
          current_floor_id: target_node.floor_id,
          current_node_id: target_node.id,
          last_progressed_at: now,
          steps_taken: run.steps_taken + Map.get(link, :travel_cost, 1)
        })
        |> Repo.update!()

      %{run: preload_run(updated_run), node_state: target_state, link: link}
    end)
    |> normalize_transaction_result()
  end

  def update_node_state(%Run{} = run, node_id, attrs) when is_binary(node_id) and is_map(attrs) do
    attrs = stringify_keys(attrs)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      run = lock_run!(run.id)

      state =
        NodeState
        |> where([state], state.run_id == ^run.id and state.node_id == ^node_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      base_attrs = %{
        "run_id" => run.id,
        "node_id" => node_id,
        "status" => attrs["status"] || "visited",
        "encounter_status" => attrs["encounter_status"] || "pending",
        "resource_status" => attrs["resource_status"] || "unknown",
        "visit_count" => attrs["visit_count"] || 1,
        "entered_at" => attrs["entered_at"] || now,
        "last_seen_at" => attrs["last_seen_at"] || now,
        "metadata" => attrs["metadata"] || %{}
      }

      case state do
        nil ->
          %NodeState{}
          |> NodeState.changeset(base_attrs)
          |> Repo.insert!()

        %NodeState{} = existing_state ->
          existing_state
          |> NodeState.changeset(
            Map.merge(base_attrs, %{"visit_count" => existing_state.visit_count})
          )
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  def end_run(%Run{} = run, status \\ :completed, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    status = normalize_run_status(status)

    Repo.transaction(fn ->
      run = lock_run!(run.id)

      if run.status != :active do
        Repo.rollback(run_changeset("run is not active"))
      end

      run
      |> Run.changeset(%{status: status, ended_at: now, last_progressed_at: now})
      |> Repo.update!()
      |> preload_run()
    end)
    |> normalize_transaction_result()
  end

  defp validate_run_entry!(%Expedition{} = expedition, %Dungeon{} = dungeon) do
    cond do
      expedition.status != :active ->
        Repo.rollback(run_changeset("expedition must be active"))

      expedition.expedition_type != :dungeon ->
        Repo.rollback(run_changeset("expedition must be a dungeon expedition"))

      expedition.realm_id != dungeon.realm_id ->
        Repo.rollback(run_changeset("expedition and dungeon must belong to the same realm"))

      expedition.location_id != dungeon.entrance_location_id ->
        Repo.rollback(run_changeset("expedition must start at the dungeon entrance location"))

      true ->
        :ok
    end
  end

  defp default_entrance_node!(dungeon_id) do
    Node
    |> join(:inner, [node], floor in assoc(node, :floor))
    |> where([node, floor], floor.dungeon_id == ^dungeon_id and node.kind == :entrance)
    |> order_by([_node, floor], asc: floor.number)
    |> order_by([node, _floor], asc: node.inserted_at)
    |> Repo.one!()
  end

  defp node_belongs_to_dungeon?(%Node{} = node, dungeon_id) do
    Repo.exists?(
      from floor in Floor,
        where: floor.id == ^node.floor_id and floor.dungeon_id == ^dungeon_id
    )
  end

  defp find_link!(from_node_id, to_node_id) do
    Link
    |> where(
      [link],
      (link.from_node_id == ^from_node_id and link.to_node_id == ^to_node_id) or
        (link.bidirectional == true and link.from_node_id == ^to_node_id and
           link.to_node_id == ^from_node_id)
    )
    |> Repo.one()
    |> case do
      nil -> Repo.rollback(run_changeset("target node is not reachable from the current node"))
      link -> link
    end
  end

  defp preload_run(%Run{} = run) do
    Repo.preload(run, [:dungeon, :current_floor, :current_node, node_states: :node])
  end

  defp lock_expedition!(expedition_id) do
    Expedition
    |> where([expedition], expedition.id == ^expedition_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_run!(run_id) do
    Run
    |> where([run], run.id == ^run_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_run_status(status) when status in [:completed, :retreated, :failed], do: status
  defp normalize_run_status("completed"), do: :completed
  defp normalize_run_status("retreated"), do: :retreated
  defp normalize_run_status("failed"), do: :failed
  defp normalize_run_status(_status), do: :completed

  defp normalize_node_status(status) when status in [:visited, :cleared, :blocked], do: status
  defp normalize_node_status("visited"), do: :visited
  defp normalize_node_status("cleared"), do: :cleared
  defp normalize_node_status("blocked"), do: :blocked
  defp normalize_node_status(_status), do: :visited

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp run_changeset(message) do
    %Run{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
