defmodule MMGO.Dungeons do
  import Ecto.Query, warn: false

  alias MMGO.Actors
  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema

  alias MMGO.Dungeons.{
    CompleteExtractionWorker,
    Drop,
    Dungeon,
    Encounter,
    EncounterSpawn,
    Extraction,
    Floor,
    Link,
    LootDrop,
    Node,
    NodeState,
    ResourceCache,
    Run
  }

  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Notifications
  alias MMGO.Parties
  alias MMGO.Parties.{Expedition, ExpeditionMember}
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

  def active_dungeon_at_location(realm_id, location_id)
      when is_binary(realm_id) and is_binary(location_id) do
    Repo.get_by(Dungeon,
      realm_id: realm_id,
      entrance_location_id: location_id,
      status: :active
    )
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
    case Repo.get_by(Run, expedition_id: expedition_id, status: :active) do
      nil -> nil
      run -> preload_run(run)
    end
  end

  def current_encounter_for_run(run_id) when is_binary(run_id) do
    run = Repo.get!(Run, run_id)
    Repo.get_by(Encounter, run_id: run.id, node_id: run.current_node_id)
  end

  def get_node_by_slug_in_dungeon(dungeon_id, slug)
      when is_binary(dungeon_id) and is_binary(slug) do
    Node
    |> join(:inner, [node], floor in assoc(node, :floor))
    |> where([node, floor], floor.dungeon_id == ^dungeon_id and node.slug == ^slug)
    |> Repo.one()
  end

  def get_run!(id) do
    Run
    |> Repo.get!(id)
    |> preload_run()
  end

  def active_extraction(run_id) when is_binary(run_id) do
    Repo.get_by(Extraction, run_id: run_id, status: :active)
  end

  def list_drops_for_run(run_id) when is_binary(run_id) do
    Repo.all(
      from drop in Drop,
        where: drop.run_id == ^run_id,
        order_by: [asc: drop.inserted_at],
        preload: [:item_template, :owner_character]
    )
  end

  def start_encounter_combat(%Encounter{} = encounter, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      encounter = lock_encounter!(encounter.id)
      run = Repo.get!(Run, encounter.run_id)
      expedition = Repo.get!(Expedition, run.expedition_id)
      dungeon = Repo.get!(Dungeon, run.dungeon_id)

      cond do
        encounter.status not in [:pending, :active] ->
          Repo.rollback(
            encounter_changeset("encounter cannot enter combat from its current state")
          )

        encounter.combat_id ->
          Repo.rollback(encounter_changeset("encounter already has a linked combat"))

        true ->
          expedition_members = active_expedition_members(expedition.id)
          {:ok, spawns} = Actors.ensure_default_spawns(encounter, %Realm{id: dungeon.realm_id})

          if expedition_members == [] do
            Repo.rollback(encounter_changeset("expedition has no active members for combat"))
          end

          encounter_participants = build_encounter_participants(spawns)

          combat_attrs = %{
            participants: build_party_participants(expedition_members) ++ encounter_participants,
            sides: %{
              party: %{
                "label" => "Party",
                "shared_hp" => party_shared_hp(expedition_members),
                "max_shared_hp" => party_shared_hp(expedition_members)
              },
              encounter: %{
                "label" => encounter_label(encounter),
                "shared_hp" => encounter_shared_hp_from_spawns(encounter, spawns),
                "max_shared_hp" => encounter_shared_hp_from_spawns(encounter, spawns)
              }
            },
            metadata: %{
              "encounter_id" => encounter.id,
              "run_id" => run.id,
              "expedition_id" => expedition.id,
              "dungeon_id" => dungeon.id,
              "node_id" => encounter.node_id,
              "encounter_kind" => encounter.encounter_kind,
              "location_kind" => "dungeon",
              "started_at" => DateTime.to_iso8601(now)
            }
          }

          {:ok, %{combat: combat}} =
            Combat.create_dungeon_encounter(%Realm{id: dungeon.realm_id}, combat_attrs)

          updated_encounter =
            encounter
            |> Encounter.changeset(%{status: :active, combat_id: combat.id, started_at: now})
            |> Repo.update!()

          node_state =
            NodeState
            |> where([state], state.run_id == ^run.id and state.node_id == ^encounter.node_id)
            |> lock("FOR UPDATE")
            |> Repo.one!()
            |> NodeState.changeset(%{encounter_status: :active, last_seen_at: now})
            |> Repo.update!()

          %{combat: combat, encounter: updated_encounter, node_state: node_state}
      end
    end)
    |> normalize_transaction_result()
  end

  def sync_encounter_combat(%CombatSchema{} = combat, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      combat = Combat.get_combat!(combat.id)

      if combat.kind != :dungeon_encounter do
        Repo.rollback(encounter_changeset("combat is not a dungeon encounter combat"))
      end

      if combat.status != :finished do
        Repo.rollback(
          encounter_changeset("combat must be finished before it can resolve the encounter")
        )
      end

      encounter_id = combat.metadata["encounter_id"] || combat.metadata[:encounter_id]
      encounter = lock_encounter!(encounter_id)

      if encounter.status not in [:pending, :active] do
        Repo.rollback(encounter_changeset("encounter has already been resolved"))
      end

      outcome = encounter_outcome_from_combat(combat)

      result =
        resolve_encounter(
          encounter,
          outcome,
          Map.put(stringify_keyword_opts(opts), "resolved_via", "combat")
        )

      case result do
        {:ok, resolved_result} ->
          if outcome == :failed do
            run = Repo.get!(Run, encounter.run_id)
            {:ok, _failed_result} = fail_run_with_sacrifice(run, now: now)
          end

          Map.put(resolved_result, :combat, combat)

        {:error, %Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def list_encounters_for_run(run_id) when is_binary(run_id) do
    Repo.all(
      from encounter in Encounter,
        where: encounter.run_id == ^run_id,
        order_by: [asc: encounter.inserted_at]
    )
  end

  def list_resource_caches_for_run(run_id) when is_binary(run_id) do
    Repo.all(
      from resource_cache in ResourceCache,
        where: resource_cache.run_id == ^run_id,
        order_by: [asc: resource_cache.inserted_at],
        preload: [:item_template]
    )
  end

  def list_loot_drops_for_run(run_id) when is_binary(run_id) do
    Repo.all(
      from loot_drop in LootDrop,
        where: loot_drop.run_id == ^run_id,
        order_by: [asc: loot_drop.inserted_at],
        preload: [:item_template, :claimed_by_character]
    )
  end

  def get_encounter!(id), do: Repo.get!(Encounter, id)
  def get_resource_cache!(id), do: Repo.get!(ResourceCache, id) |> Repo.preload(:item_template)

  def get_loot_drop!(id),
    do: Repo.get!(LootDrop, id) |> Repo.preload([:item_template, :claimed_by_character])

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

      content = materialize_node_content!(run, entrance_node, now, content_attrs_from_opts(opts))

      %{run: preload_run(run), node_state: node_state, content: content}
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

      content =
        materialize_node_content!(updated_run, target_node, now, content_attrs_from_opts(opts))

      %{run: preload_run(updated_run), node_state: target_state, link: link, content: content}
    end)
    |> normalize_transaction_result()
  end

  def materialize_node_content(%Run{} = run, node_id, attrs \\ %{})
      when is_binary(node_id) and is_map(attrs) do
    now = Map.get(attrs, :now) || Map.get(attrs, "now") || DateTime.utc_now()

    Repo.transaction(fn ->
      run = lock_run!(run.id)
      node = Repo.get!(Node, node_id)

      if not node_belongs_to_dungeon?(node, run.dungeon_id) do
        Repo.rollback(run_changeset("node does not belong to this dungeon run"))
      end

      ensure_node_state_exists!(run.id, node.id, now)
      materialize_node_content!(run, node, now, stringify_keys(Map.delete(attrs, :now)))
    end)
    |> normalize_transaction_result()
  end

  def resolve_encounter(%Encounter{} = encounter, outcome, attrs \\ %{}) do
    now = Map.get(attrs, :now) || Map.get(attrs, "now") || DateTime.utc_now()
    attrs = stringify_keys(Map.delete(attrs, :now))
    outcome = normalize_encounter_outcome(outcome)

    Repo.transaction(fn ->
      encounter =
        Encounter
        |> where([encounter], encounter.id == ^encounter.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if encounter.status not in [:pending, :active] do
        Repo.rollback(encounter_changeset("encounter is not resolvable"))
      end

      updated_encounter =
        encounter
        |> Encounter.changeset(%{status: outcome, resolved_at: now})
        |> Repo.update!()

      xp_rewards =
        if outcome == :cleared do
          expedition = Repo.get!(Expedition, run_expedition_id!(updated_encounter.run_id))

          Parties.distribute_xp_shares(Repo, expedition, encounter_xp(updated_encounter), %{
            "source_type" => "encounter",
            "reward_kind" => "xp",
            "run_id" => updated_encounter.run_id,
            "encounter_id" => updated_encounter.id,
            "granted_at" => now,
            "encounter_kind" => updated_encounter.encounter_kind
          })
        else
          []
        end

      loot_drops = maybe_create_loot_drops!(updated_encounter, attrs)

      node_state =
        NodeState
        |> where(
          [state],
          state.run_id == ^encounter.run_id and state.node_id == ^encounter.node_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one!()

      updated_state =
        node_state
        |> NodeState.changeset(%{encounter_status: outcome, last_seen_at: now})
        |> Repo.update!()

      %{
        encounter: updated_encounter,
        node_state: updated_state,
        loot_drops: loot_drops,
        xp_rewards: xp_rewards
      }
    end)
    |> normalize_transaction_result()
  end

  def claim_loot(%LootDrop{} = loot_drop, %Character{} = character, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    now = Map.get(attrs, "now") || DateTime.utc_now()

    Repo.transaction(fn ->
      loot_drop =
        LootDrop
        |> where([loot_drop], loot_drop.id == ^loot_drop.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload(:item_template)

      character = Repo.get!(Character, character.id)

      validate_loot_claim!(loot_drop, character)

      reward_result =
        case loot_drop.reward_kind do
          :currency ->
            realm = Repo.get!(Realm, character.realm_id)

            Economy.grant_from_treasury(realm, character, loot_drop.amount, %{
              entry_type: "reward",
              source: "dungeon_loot",
              loot_drop_id: loot_drop.id
            })

          :item_template ->
            Inventory.grant_item(character, loot_drop.item_template, %{quantity: loot_drop.amount})
        end

      case reward_result do
        {:ok, reward} ->
          updated_loot_drop =
            loot_drop
            |> LootDrop.changeset(%{
              status: :claimed,
              claimed_at: now,
              claimed_by_character_id: character.id,
              metadata:
                Map.put(loot_drop.metadata || %{}, "claim_reason", attrs["reason"] || "claimed")
            })
            |> Repo.update!()

          %{loot_drop: updated_loot_drop, reward: reward}

        {:error, %Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def harvest_resource(
        %ResourceCache{} = resource_cache,
        %Character{} = character,
        quantity,
        attrs \\ %{}
      )
      when is_integer(quantity) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      resource_cache =
        ResourceCache
        |> where([resource_cache], resource_cache.id == ^resource_cache.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload(:item_template)

      character = Repo.get!(Character, character.id)
      validate_resource_claim!(resource_cache, character, quantity)

      reward_result =
        case resource_cache.item_template do
          nil -> {:ok, %{resource_code: resource_cache.resource_code, quantity: quantity}}
          item_template -> Inventory.grant_item(character, item_template, %{quantity: quantity})
        end

      case reward_result do
        {:ok, reward} ->
          remaining_quantity = resource_cache.quantity_remaining - quantity

          updated_resource_cache =
            resource_cache
            |> ResourceCache.changeset(%{
              quantity_remaining: remaining_quantity,
              status: if(remaining_quantity == 0, do: :depleted, else: :available),
              metadata:
                Map.put(
                  resource_cache.metadata || %{},
                  "last_harvest_note",
                  attrs["note"] || "harvested"
                )
            })
            |> Repo.update!()

          node_state =
            NodeState
            |> where(
              [state],
              state.run_id == ^resource_cache.run_id and state.node_id == ^resource_cache.node_id
            )
            |> lock("FOR UPDATE")
            |> Repo.one!()

          updated_state =
            node_state
            |> NodeState.changeset(%{
              resource_status: if(remaining_quantity == 0, do: :depleted, else: :available),
              last_seen_at: DateTime.utc_now()
            })
            |> Repo.update!()

          %{resource_cache: updated_resource_cache, node_state: updated_state, reward: reward}

        {:error, %Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
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

  def extract_via_ascent(%Run{} = run, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      run = lock_run!(run.id)
      validate_extraction_ready!(run, nil, :ascent, nil)

      current_node = Repo.get!(Node, run.current_node_id)

      if current_node.kind not in [:entrance, :stairs_up, :exit] do
        Repo.rollback(extraction_changeset("current node is not a valid ascent point"))
      end

      complete_run_exit!(run, :completed, :ascent, now)
    end)
    |> normalize_transaction_result()
  end

  def start_return_ritual(%Run{} = run, %Character{} = caster, opts \\ []) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())
    ritual_game_days = Keyword.get(opts, :ritual_game_days, 1)

    Repo.transaction(fn ->
      run = lock_run!(run.id)
      caster = Repo.get!(Character, caster.id)
      validate_extraction_ready!(run, caster, :return_ritual, nil)

      completes_at = MMGO.Travel.Clock.arrival_at(now, ritual_game_days)

      extraction =
        %Extraction{}
        |> Extraction.changeset(%{
          run_id: run.id,
          initiator_character_id: caster.id,
          extraction_type: :return_ritual,
          status: :active,
          started_at: now,
          completes_at: completes_at,
          metadata: %{"ritual_game_days" => ritual_game_days}
        })
        |> Repo.insert!()

      job =
        %{"extraction_id" => extraction.id}
        |> CompleteExtractionWorker.new(
          schedule_in: max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{extraction: extraction, worker_job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_extraction_by_id(extraction_id, opts \\ []) when is_binary(extraction_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      extraction =
        Extraction
        |> where([extraction], extraction.id == ^extraction_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if extraction.status != :active do
        Repo.rollback(extraction_changeset("extraction is not active"))
      end

      if (not force? and extraction.completes_at) &&
           DateTime.compare(now, extraction.completes_at) == :lt do
        Repo.rollback(extraction_changeset("extraction is not due yet"))
      end

      run = lock_run!(extraction.run_id)

      validate_extraction_ready!(
        run,
        Repo.get!(Character, extraction.initiator_character_id),
        extraction.extraction_type,
        extraction.id
      )

      result = complete_run_exit!(run, :completed, extraction.extraction_type, now)

      updated_extraction =
        extraction
        |> Extraction.changeset(%{status: :completed, completed_at: now})
        |> Repo.update!()

      Map.put(result, :extraction, updated_extraction)
    end)
    |> normalize_transaction_result()
  end

  def complete_due_extractions(now \\ DateTime.utc_now()) do
    Extraction
    |> where(
      [extraction],
      extraction.status == :active and not is_nil(extraction.completes_at) and
        extraction.completes_at <= ^now
    )
    |> Repo.all()
    |> Enum.map(fn extraction ->
      complete_extraction_by_id(extraction.id, now: now, force: true)
    end)
  end

  def fail_run_with_sacrifice(%Run{} = run, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      run = lock_run!(run.id)

      if run.status != :active do
        Repo.rollback(run_changeset("run is not active"))
      end

      complete_run_exit!(run, :failed, :sacrifice, now)
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

      complete_run_exit!(run, status, :manual, now)
    end)
    |> normalize_transaction_result()
  end

  defp complete_run_exit!(%Run{} = run, status, extraction_type, now) do
    dungeon = Repo.get!(Dungeon, run.dungeon_id)
    expedition = Repo.get!(Expedition, run.expedition_id)
    expedition_members = active_expedition_members(expedition.id)

    {drops, lost_grimoires} =
      if status == :failed do
        expedition_members
        |> Enum.map(&Repo.get!(Character, &1.character_id))
        |> Enum.reduce({[], []}, fn character, {drops_acc, grimoire_acc} ->
          {character_drops, grimoire_drop} = collect_character_drops!(run, character)
          grimoire_acc = if grimoire_drop, do: [grimoire_drop | grimoire_acc], else: grimoire_acc
          {drops_acc ++ character_drops, grimoire_acc}
        end)
      else
        {[], []}
      end

    updated_run =
      run
      |> Run.changeset(%{status: status, ended_at: now, last_progressed_at: now})
      |> Repo.update!()

    xp_rewards =
      if status == :completed do
        Parties.distribute_xp_shares(Repo, expedition, run_completion_xp(updated_run), %{
          "source_type" => "run",
          "reward_kind" => "xp",
          "run_id" => updated_run.id,
          "granted_at" => now,
          "reason" => "run_completion"
        })
      else
        []
      end

    conclude_expedition!(expedition, expedition_status_from_run(status), now)
    move_expedition_members_to_location!(expedition_members, dungeon.entrance_location_id)

    notify_run_exit!(
      expedition_members,
      updated_run,
      extraction_type,
      length(drops) + length(lost_grimoires)
    )

    %{run: preload_run(updated_run), xp_rewards: xp_rewards, drops: drops ++ lost_grimoires}
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

  defp validate_extraction_ready!(%Run{} = run, caster, extraction_type, current_extraction_id) do
    expedition = Repo.get!(Expedition, run.expedition_id)
    encounter = current_encounter_for_run(run.id)
    extraction = active_extraction(run.id)

    cond do
      run.status != :active ->
        Repo.rollback(extraction_changeset("run is not active"))

      expedition.status != :active ->
        Repo.rollback(extraction_changeset("expedition is not active"))

      extraction && extraction.id != current_extraction_id ->
        Repo.rollback(extraction_changeset("run already has an active extraction"))

      encounter && encounter.status in [:pending, :active] ->
        Repo.rollback(
          extraction_changeset("current encounter must be resolved before extraction")
        )

      extraction_type == :return_ritual and is_nil(caster) ->
        Repo.rollback(extraction_changeset("a caster must initiate the return ritual"))

      extraction_type == :return_ritual and not ritual_caster?(caster) ->
        Repo.rollback(
          extraction_changeset(
            "initiator must be a wizardry specialist to perform the return ritual"
          )
        )

      extraction_type == :return_ritual and not expedition_member?(expedition.id, caster.id) ->
        Repo.rollback(extraction_changeset("ritual caster must belong to the expedition"))

      true ->
        :ok
    end
  end

  defp ritual_caster?(%Character{} = character) do
    case MMGO.Academy.active_specialization(character.id) do
      %MMGO.Academy.Specialization{track: :wizardry} -> true
      _other -> false
    end
  end

  defp expedition_member?(expedition_id, character_id) do
    Repo.exists?(
      from member in ExpeditionMember,
        where:
          member.expedition_id == ^expedition_id and member.character_id == ^character_id and
            member.status == :active
    )
  end

  defp conclude_expedition!(%Expedition{} = expedition, status, now) do
    expedition_members =
      ExpeditionMember
      |> where([member], member.expedition_id == ^expedition.id and member.status == :active)
      |> lock("FOR UPDATE")
      |> Repo.all()

    Enum.each(expedition_members, fn member ->
      member
      |> ExpeditionMember.changeset(%{status: :completed, left_at: now})
      |> Repo.update!()
    end)

    expedition
    |> Expedition.changeset(%{status: status, ended_at: now})
    |> Repo.update!()
  end

  defp expedition_status_from_run(:failed), do: :failed
  defp expedition_status_from_run(_status), do: :completed

  defp move_expedition_members_to_location!(members, location_id) do
    Enum.each(members, fn member ->
      Repo.get!(Character, member.character_id)
      |> Character.travel_changeset(%{current_location_id: location_id})
      |> Repo.update!()
    end)
  end

  defp collect_character_drops!(%Run{} = run, %Character{} = character) do
    inventory_drops =
      Inventory.InventoryItem
      |> where(
        [item],
        item.character_id == ^character.id and item.quantity > item.reserved_quantity
      )
      |> Repo.all()
      |> Enum.flat_map(fn item ->
        item = Repo.preload(item, :item_template)
        available_quantity = Inventory.available_quantity(item)

        drop =
          %Drop{}
          |> Drop.changeset(%{
            run_id: run.id,
            node_id: run.current_node_id,
            owner_character_id: character.id,
            item_template_id: item.item_template_id,
            drop_kind: :inventory,
            name: item.item_template.name,
            quantity: available_quantity,
            durability: item.durability,
            metadata: item.metadata || %{}
          })
          |> Repo.insert!()

        if item.quantity - available_quantity == 0 do
          Repo.delete!(item)
        else
          item
          |> Inventory.InventoryItem.changeset(%{
            quantity: item.quantity - available_quantity,
            reserved_quantity: item.reserved_quantity
          })
          |> Repo.update!()
        end

        [drop]
      end)

    grimoire_drop =
      case Grimoires.active_grimoire_for_character(character.id) do
        nil ->
          nil

        grimoire ->
          grimoire = Grimoires.get_grimoire!(grimoire.id)

          drop =
            %Drop{}
            |> Drop.changeset(%{
              run_id: run.id,
              node_id: run.current_node_id,
              owner_character_id: character.id,
              drop_kind: :grimoire,
              name: grimoire.name,
              quantity: 1,
              durability: 0,
              metadata: %{"spell_count" => length(grimoire.entries)}
            })
            |> Repo.insert!()

          Repo.delete!(grimoire)
          drop
      end

    {inventory_drops, grimoire_drop}
  end

  defp notify_run_exit!(members, run, extraction_type, lost_item_count) do
    Enum.each(members, fn member ->
      character = Repo.get!(Character, member.character_id)

      case run.status do
        :failed -> _ = Notifications.notify_run_failed(character, run, lost_item_count)
        _other -> _ = Notifications.notify_extraction_completed(character, run, extraction_type)
      end
    end)
  end

  defp extraction_changeset(message) do
    %Extraction{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
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
    Repo.preload(run, [
      :dungeon,
      :current_floor,
      :current_node,
      node_states: :node,
      encounters: [:node, :combat],
      resource_caches: [:node, :item_template],
      loot_drops: [:node, :item_template, :claimed_by_character]
    ])
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

  defp stringify_keyword_opts(opts) when is_list(opts) do
    opts
    |> Keyword.delete(:now)
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp active_expedition_members(expedition_id) do
    ExpeditionMember
    |> where([member], member.expedition_id == ^expedition_id and member.status == :active)
    |> order_by([member], asc: member.joined_at)
    |> preload(:character)
    |> Repo.all()
  end

  defp party_shared_hp(expedition_members) do
    max(length(expedition_members), 1) * 100
  end

  defp encounter_shared_hp_from_spawns(%Encounter{} = encounter, spawns) when is_list(spawns) do
    spawns
    |> Enum.reduce(0, fn spawn, total -> total + spawn.current_hp * spawn.quantity end)
    |> max(max(encounter.threat_level, 1) * 3)
  end

  defp build_party_participants(expedition_members) do
    expedition_members
    |> Enum.with_index()
    |> Enum.map(fn {member, index} ->
      %{
        character_id: member.character_id,
        side: "party",
        position: index,
        metadata: %{"expedition_member_id" => member.id}
      }
    end)
  end

  defp build_encounter_participants(spawns) do
    spawns
    |> Enum.flat_map(fn spawn ->
      Enum.map(0..(spawn.quantity - 1), fn offset ->
        %{
          actor_template_id: spawn.actor_template_id,
          side: "encounter",
          position: offset,
          display_name: encounter_spawn_name(spawn, offset),
          combat_level: spawn.actor_template.combat_level,
          metadata: %{"encounter_spawn_id" => spawn.id}
        }
      end)
    end)
  end

  defp encounter_spawn_name(%EncounterSpawn{} = spawn, 0), do: spawn.actor_template.name

  defp encounter_spawn_name(%EncounterSpawn{} = spawn, offset),
    do: "#{spawn.actor_template.name} #{offset + 1}"

  defp encounter_label(%Encounter{} = encounter) do
    encounter.encounter_kind
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp encounter_outcome_from_combat(%CombatSchema{} = combat) do
    case combat.winner_side do
      "party" -> :cleared
      _other -> :failed
    end
  end

  defp lock_encounter!(encounter_id) do
    Encounter
    |> where([encounter], encounter.id == ^encounter_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp content_attrs_from_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([:encounter, :resource, :loot_drops])
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp materialize_node_content!(%Run{} = run, %Node{} = node, now, attrs) do
    encounter = ensure_encounter!(run, node, now, Map.get(attrs, "encounter"))
    resource_cache = ensure_resource_cache!(run, node, Map.get(attrs, "resource"))
    _spawns = ensure_spawns!(encounter, run.dungeon_id)

    node_state =
      NodeState
      |> where([state], state.run_id == ^run.id and state.node_id == ^node.id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    updated_state =
      node_state
      |> NodeState.changeset(%{
        encounter_status: encounter_status_for(encounter),
        resource_status: resource_status_for(resource_cache),
        last_seen_at: now
      })
      |> Repo.update!()

    %{encounter: encounter, resource_cache: resource_cache, node_state: updated_state}
  end

  defp ensure_spawns!(nil, _dungeon_id), do: []

  defp ensure_spawns!(%Encounter{} = encounter, dungeon_id) do
    encounter = Repo.preload(encounter, spawns: :actor_template)

    if encounter.spawns == [] do
      dungeon = Repo.get!(Dungeon, dungeon_id)
      {:ok, spawns} = Actors.ensure_default_spawns(encounter, %Realm{id: dungeon.realm_id})
      spawns
    else
      encounter.spawns
    end
  end

  defp ensure_encounter!(%Run{} = run, %Node{} = node, now, custom_encounter) do
    case Repo.get_by(Encounter, run_id: run.id, node_id: node.id) do
      %Encounter{} = encounter ->
        encounter

      nil ->
        attrs = default_encounter_attrs(node, now, custom_encounter)

        case attrs do
          nil ->
            nil

          attrs ->
            %Encounter{}
            |> Encounter.changeset(Map.merge(attrs, %{"run_id" => run.id, "node_id" => node.id}))
            |> Repo.insert!()
        end
    end
  end

  defp ensure_resource_cache!(%Run{} = run, %Node{} = node, custom_resource) do
    case Repo.get_by(ResourceCache, run_id: run.id, node_id: node.id) do
      %ResourceCache{} = resource_cache ->
        Repo.preload(resource_cache, :item_template)

      nil ->
        attrs = default_resource_attrs(node, custom_resource)

        case attrs do
          nil ->
            nil

          attrs ->
            %ResourceCache{}
            |> ResourceCache.changeset(
              Map.merge(attrs, %{"run_id" => run.id, "node_id" => node.id})
            )
            |> Repo.insert!()
            |> Repo.preload(:item_template)
        end
    end
  end

  defp default_encounter_attrs(%Node{threat_level: threat_level} = node, now, nil)
       when threat_level > 0 do
    %{
      "encounter_kind" => default_encounter_kind(node.kind),
      "status" => "pending",
      "threat_level" => threat_level,
      "started_at" => now,
      "metadata" => %{"generated" => true}
    }
  end

  defp default_encounter_attrs(_node, _now, nil), do: nil
  defp default_encounter_attrs(_node, _now, attrs) when is_map(attrs), do: stringify_keys(attrs)

  defp default_resource_attrs(%Node{kind: :rest}, nil) do
    %{
      "resource_code" => "rest_supplies",
      "status" => "available",
      "quantity_total" => 1,
      "quantity_remaining" => 1,
      "metadata" => %{"generated" => true}
    }
  end

  defp default_resource_attrs(_node, nil), do: nil
  defp default_resource_attrs(_node, attrs) when is_map(attrs), do: stringify_keys(attrs)

  defp default_encounter_kind(:boss), do: "boss"
  defp default_encounter_kind(:hazard), do: "hazard"
  defp default_encounter_kind(_kind), do: "skirmish"

  defp encounter_status_for(nil), do: :avoided
  defp encounter_status_for(%Encounter{status: status}), do: status

  defp resource_status_for(nil), do: :unknown
  defp resource_status_for(%ResourceCache{status: status}), do: status

  defp ensure_node_state_exists!(run_id, node_id, now) do
    case Repo.get_by(NodeState, run_id: run_id, node_id: node_id) do
      %NodeState{} = node_state ->
        node_state

      nil ->
        %NodeState{}
        |> NodeState.changeset(%{
          run_id: run_id,
          node_id: node_id,
          status: :visited,
          encounter_status: :pending,
          resource_status: :unknown,
          visit_count: 1,
          entered_at: now,
          last_seen_at: now,
          metadata: %{}
        })
        |> Repo.insert!()
    end
  end

  defp normalize_encounter_outcome(outcome) when outcome in [:cleared, :avoided, :failed],
    do: outcome

  defp normalize_encounter_outcome("cleared"), do: :cleared
  defp normalize_encounter_outcome("avoided"), do: :avoided
  defp normalize_encounter_outcome("failed"), do: :failed
  defp normalize_encounter_outcome(_outcome), do: :cleared

  defp maybe_create_loot_drops!(%Encounter{} = encounter, attrs) do
    existing_loot =
      Repo.all(from loot_drop in LootDrop, where: loot_drop.encounter_id == ^encounter.id)

    cond do
      existing_loot != [] ->
        existing_loot

      encounter.status != :cleared ->
        []

      true ->
        attrs
        |> loot_drop_attrs_for(encounter)
        |> Enum.map(fn loot_attrs ->
          %LootDrop{}
          |> LootDrop.changeset(
            Map.merge(loot_attrs, %{
              "run_id" => encounter.run_id,
              "node_id" => encounter.node_id,
              "encounter_id" => encounter.id
            })
          )
          |> Repo.insert!()
          |> Repo.preload([:item_template, :claimed_by_character])
        end)
    end
  end

  defp loot_drop_attrs_for(attrs, %Encounter{} = encounter) do
    case Map.get(attrs, "loot_drops") do
      loot_drops when is_list(loot_drops) and loot_drops != [] ->
        Enum.map(loot_drops, &stringify_keys/1)

      _other ->
        [default_currency_loot_attrs(encounter)]
    end
  end

  defp default_currency_loot_attrs(%Encounter{} = encounter) do
    amount = max(div(encounter.threat_level, 5), 1) * 10

    %{
      "reward_kind" => "currency",
      "status" => "available",
      "amount" => amount,
      "metadata" => %{"generated" => true}
    }
  end

  defp validate_loot_claim!(%LootDrop{} = loot_drop, %Character{} = character) do
    cond do
      loot_drop.status != :available ->
        Repo.rollback(loot_changeset("loot has already been claimed"))

      character.realm_id != run_realm_id!(loot_drop.run_id) ->
        Repo.rollback(loot_changeset("character must belong to the same realm as the run"))

      not eligible_character_for_run?(loot_drop.run_id, character.id) ->
        Repo.rollback(
          loot_changeset("character must belong to the expedition that earned this loot")
        )

      true ->
        :ok
    end
  end

  defp validate_resource_claim!(
         %ResourceCache{} = resource_cache,
         %Character{} = character,
         quantity
       ) do
    cond do
      quantity <= 0 ->
        Repo.rollback(resource_changeset("quantity must be greater than zero"))

      resource_cache.status != :available ->
        Repo.rollback(resource_changeset("resource cache is depleted"))

      quantity > resource_cache.quantity_remaining ->
        Repo.rollback(resource_changeset("quantity exceeds the remaining resources"))

      character.realm_id != run_realm_id!(resource_cache.run_id) ->
        Repo.rollback(resource_changeset("character must belong to the same realm as the run"))

      not eligible_character_for_run?(resource_cache.run_id, character.id) ->
        Repo.rollback(
          resource_changeset(
            "character must belong to the expedition that discovered this resource"
          )
        )

      true ->
        :ok
    end
  end

  defp run_realm_id!(run_id) do
    run = Repo.get!(Run, run_id)
    dungeon = Repo.get!(Dungeon, run.dungeon_id)
    dungeon.realm_id
  end

  defp run_expedition_id!(run_id) do
    Repo.get!(Run, run_id).expedition_id
  end

  defp eligible_character_for_run?(run_id, character_id) do
    Parties.eligible_member_for_expedition?(run_expedition_id!(run_id), character_id)
  end

  defp encounter_xp(%Encounter{} = encounter) do
    max(encounter.threat_level * 6, 10)
  end

  defp run_completion_xp(%Run{} = run) do
    max(run.steps_taken * 4, 20)
  end

  defp loot_changeset(message) do
    %LootDrop{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp resource_changeset(message) do
    %ResourceCache{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp encounter_changeset(message) do
    %Encounter{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp run_changeset(message) do
    %Run{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
