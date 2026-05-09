defmodule MMGO.Dungeons do
  import Ecto.Query, warn: false
  require Logger

  alias MMGO.AI
  alias MMGO.AI.Prompts.DungeonTickPrompt
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
    LinkState,
    LootDrop,
    Node,
    NodeOverride,
    NodeState,
    ResourceCache,
    Run,
    State,
    MaintenanceWorker
  }

  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Inventory
  # Notifications removed in MVP
  alias MMGO.Parties
  alias MMGO.Parties.{Expedition, ExpeditionMember}
  alias MMGO.Repo
  alias MMGO.Spells.Spell
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
    |> Repo.preload([
      :entrance_location,
      :state,
      link_states: [],
      node_overrides: [],
      floors: [nodes: []]
    ])
  end

  def get_state_for_dungeon(dungeon_id) when is_binary(dungeon_id) do
    Repo.get_by(State, dungeon_id: dungeon_id)
  end

  def list_node_overrides(dungeon_id) when is_binary(dungeon_id) do
    Repo.all(
      from node_override in NodeOverride,
        where: node_override.dungeon_id == ^dungeon_id,
        order_by: [asc: node_override.inserted_at]
    )
  end

  def list_link_states(dungeon_id) when is_binary(dungeon_id) do
    Repo.all(
      from link_state in LinkState,
        where: link_state.dungeon_id == ^dungeon_id,
        order_by: [asc: link_state.inserted_at]
    )
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

  def maintain_dungeon_by_id(dungeon_id, opts \\ []) when is_binary(dungeon_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      dungeon = Repo.get!(Dungeon, dungeon_id)
      state = lock_or_init_state!(dungeon.id, now)
      active_run_count = count_active_runs(dungeon.id)
      pressure_level = min(active_run_count * 10, 100)
      anomaly_level = rem(state.cycle_number + active_run_count, 100)

      updated_state =
        state
        |> State.changeset(%{
          cycle_number: state.cycle_number + 1,
          active_run_count_snapshot: active_run_count,
          pressure_level: pressure_level,
          anomaly_level: anomaly_level,
          last_maintained_at: now,
          next_maintenance_at: DateTime.add(now, 300, :second)
        })
        |> Repo.update!()

      floors = list_floors_for_tick(dungeon.id)
      activity_window = activity_window(dungeon.id, now)

      {updated_state, floor_directives} =
        apply_dungeon_tick!(dungeon, updated_state, floors, activity_window, opts)

      floor_directive_map = Map.new(floor_directives, &{&1["floor_id"], &1})

      node_overrides = refresh_node_overrides!(dungeon.id, updated_state, floor_directive_map)
      link_states = refresh_link_states!(dungeon.id, updated_state, floor_directive_map)
      schedule_maintenance!(dungeon.id, updated_state.next_maintenance_at)

      %{state: updated_state, node_overrides: node_overrides, link_states: link_states}
    end)
    |> normalize_transaction_result()
  end

  def maintain_due_dungeons(now \\ DateTime.utc_now()) do
    Repo.all(
      from dungeon in Dungeon,
        left_join: state in assoc(dungeon, :state),
        where:
          dungeon.status == :active and (is_nil(state.id) or state.next_maintenance_at <= ^now),
        select: dungeon.id
    )
    |> Enum.map(&maintain_dungeon_by_id(&1, now: now))
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

  def cast_utility_spell(%Run{} = run, %Character{} = character, %Spell{} = spell, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      run = run.id |> lock_run!() |> preload_run()

      cond do
        run.status != :active ->
          Repo.rollback(run_changeset("run is not active"))

        not Parties.eligible_member_for_expedition?(run.expedition_id, character.id) ->
          Repo.rollback(run_changeset("character is not part of this expedition"))

        spell.spell_type != :utility ->
          Repo.rollback(run_changeset("spell is not a utility spell"))

        spell.targeting not in [:self, :zone] ->
          Repo.rollback(run_changeset("utility spells must target self or zone"))

        true ->
          current_state = ensure_node_state_exists!(run.id, run.current_node_id, now)
          hidden_nodes = revealable_hidden_nodes(run, spell)

          if utility_reveal_spell?(spell) and hidden_nodes == [] do
            Repo.rollback(run_changeset("no hidden nodes are available to reveal"))
          end

          updated_current_state =
            current_state
            |> NodeState.changeset(%{
              last_seen_at: now,
              metadata: merge_utility_node_metadata(current_state.metadata, spell, now)
            })
            |> Repo.update!()

          revealed_states =
            hidden_nodes
            |> Enum.take(reveal_budget(spell))
            |> Enum.map(fn node ->
              node_state = ensure_node_state_exists!(run.id, node.id, now)

              node_state
              |> NodeState.changeset(%{
                status: :visited,
                last_seen_at: now,
                metadata:
                  merge_utility_node_metadata(node_state.metadata, spell, now, %{
                    "revealed" => true,
                    "hidden_node_id" => node.id
                  })
              })
              |> Repo.update!()
            end)

          updated_run =
            run
            |> Run.changeset(%{
              last_progressed_at: now,
              metadata:
                merge_utility_run_metadata(run.metadata, character, spell, revealed_states, now)
            })
            |> Repo.update!()

          %{
            run: preload_run(updated_run),
            current_node_state: updated_current_state,
            revealed_states: revealed_states
          }
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

      encounter && encounter.status == :active ->
        Repo.rollback(extraction_changeset("current combat must be resolved before extraction"))

      extraction_type == :return_ritual and is_nil(caster) ->
        Repo.rollback(extraction_changeset("a caster must initiate the return ritual"))

      extraction_type == :return_ritual and not expedition_member?(expedition.id, caster.id) ->
        Repo.rollback(extraction_changeset("ritual caster must belong to the expedition"))

      true ->
        :ok
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

  defp notify_run_exit!(_members, _run, _extraction_type, _lost_item_count) do
    :ok
  end

  defp lock_or_init_state!(dungeon_id, now) do
    State
    |> where([state], state.dungeon_id == ^dungeon_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        %State{}
        |> State.changeset(%{
          dungeon_id: dungeon_id,
          cycle_number: 0,
          active_run_count_snapshot: 0,
          pressure_level: 0,
          anomaly_level: 0,
          last_maintained_at: now,
          next_maintenance_at: now,
          metadata: %{}
        })
        |> Repo.insert!()

      state ->
        state
    end
  end

  defp refresh_node_overrides!(dungeon_id, %State{} = state, floor_directive_map) do
    nodes =
      Node
      |> join(:inner, [node], floor in assoc(node, :floor))
      |> where([_node, floor], floor.dungeon_id == ^dungeon_id)
      |> Repo.all()

    Enum.map(nodes, fn node ->
      directive =
        Map.get(floor_directive_map, node.floor_id, default_floor_directive(node.floor_id))

      base_status =
        if state.pressure_level >= 60 and node.kind == :rest, do: :depleted, else: :stable

      threat_bias =
        if node.kind in [:room, :hazard, :boss],
          do: clamp(min(div(state.pressure_level, 5), 20) + directive["threat_delta"], -100, 100),
          else: 0

      resource_bias =
        if node.kind == :rest,
          do:
            clamp(
              -min(div(state.pressure_level, 10), 5) + directive["resource_delta"],
              -100,
              100
            ),
          else:
            clamp(
              max(5 - div(state.pressure_level, 20), -5) + directive["resource_delta"],
              -100,
              100
            )

      anomaly_tag =
        case directive["anomaly_tag"] do
          "none" -> anomaly_tag_for(node, state)
          explicit_tag -> explicit_tag
        end

      status =
        case {directive["anomaly_tag"], base_status} do
          {"depleted", _base_status} -> :depleted
          {tag, _base_status} when tag in ["volatile", "wrath", "echo", "predator"] -> :volatile
          {_tag, base_status} -> base_status
        end

      case Repo.get_by(NodeOverride, dungeon_id: dungeon_id, node_id: node.id) do
        nil ->
          %NodeOverride{}
          |> NodeOverride.changeset(%{
            dungeon_id: dungeon_id,
            node_id: node.id,
            status: status,
            threat_bias: threat_bias,
            resource_bias: resource_bias,
            anomaly_tag: anomaly_tag,
            metadata: %{
              "cycle_number" => state.cycle_number,
              "floor_directive" => directive
            }
          })
          |> Repo.insert!()

        %NodeOverride{} = node_override ->
          node_override
          |> NodeOverride.changeset(%{
            status: status,
            threat_bias: threat_bias,
            resource_bias: resource_bias,
            anomaly_tag: anomaly_tag,
            metadata:
              node_override.metadata
              |> Kernel.||(%{})
              |> Map.put("cycle_number", state.cycle_number)
              |> Map.put("floor_directive", directive)
          })
          |> Repo.update!()
      end
    end)
  end

  defp refresh_link_states!(dungeon_id, %State{} = state, floor_directive_map) do
    links =
      Repo.all(
        from link in Link,
          where: link.dungeon_id == ^dungeon_id,
          preload: [:from_node, :to_node]
      )

    Enum.map(links, fn link ->
      base_status =
        if rem(state.cycle_number + link.travel_cost, 4) == 0 and state.pressure_level >= 20,
          do: :blocked,
          else: :active

      floor_shifts =
        [link.from_node.floor_id, link.to_node.floor_id]
        |> Enum.map(&Map.get(floor_directive_map, &1, default_floor_directive(&1)))
        |> Enum.map(& &1["connection_shift"])

      status =
        cond do
          Enum.any?(floor_shifts, &(&1 == "block")) -> :blocked
          Enum.any?(floor_shifts, &(&1 == "open")) -> :active
          true -> base_status
        end

      case Repo.get_by(LinkState, dungeon_id: dungeon_id, link_id: link.id) do
        nil ->
          %LinkState{}
          |> LinkState.changeset(%{
            dungeon_id: dungeon_id,
            link_id: link.id,
            status: status,
            metadata: %{
              "cycle_number" => state.cycle_number,
              "floor_shifts" => floor_shifts
            }
          })
          |> Repo.insert!()

        %LinkState{} = link_state ->
          link_state
          |> LinkState.changeset(%{
            status: status,
            metadata:
              link_state.metadata
              |> Kernel.||(%{})
              |> Map.put("cycle_number", state.cycle_number)
              |> Map.put("floor_shifts", floor_shifts)
          })
          |> Repo.update!()
      end
    end)
  end

  defp apply_dungeon_tick!(%Dungeon{} = dungeon, %State{} = state, floors, activity_window, opts) do
    prompt_payload =
      DungeonTickPrompt.build(%{
        dungeon: %{
          id: dungeon.id,
          name: dungeon.name,
          status: dungeon.status
        },
        state: %{
          cycle_number: state.cycle_number,
          pressure_level: state.pressure_level,
          anomaly_level: state.anomaly_level
        },
        floors: Enum.map(floors, &floor_payload/1),
        activity_window: activity_window
      })

    ai_opts =
      Keyword.put_new(opts, :metadata, %{
        dungeon_id: dungeon.id,
        cycle_number: state.cycle_number
      })

    {directives, mode, reason} =
      case AI.tick_dungeon(prompt_payload, ai_opts) do
        {:ok, %{directives: %{"floor_directives" => raw_directives, "summary" => summary}}} ->
          case normalize_floor_directives(raw_directives, floors) do
            {:ok, directives} ->
              {directives, "ai", summary}

            {:error, validation_reason} ->
              emit_dungeon_tick_validation(dungeon.id, state, validation_reason)

              {fallback_floor_directives(floors, state, activity_window), "fallback",
               "validation_failure"}
          end

        {:ok, %{directives: directives}} ->
          emit_dungeon_tick_validation(dungeon.id, state, {:invalid_shape, directives})

          {fallback_floor_directives(floors, state, activity_window), "fallback",
           "validation_failure"}

        {:error, ai_reason} ->
          emit_dungeon_tick_fallback(dungeon.id, state, ai_reason)

          {fallback_floor_directives(floors, state, activity_window), "fallback",
           "provider_failure"}
      end

    metadata =
      state.metadata
      |> Kernel.||(%{})
      |> Map.put("ai_tick", %{
        "mode" => mode,
        "reason" => reason,
        "activity_window" => activity_window,
        "floor_directives" => directives
      })

    updated_state =
      state
      |> State.changeset(%{metadata: metadata})
      |> Repo.update!()

    {updated_state, directives}
  end

  defp list_floors_for_tick(dungeon_id) do
    Repo.all(
      from floor in Floor,
        where: floor.dungeon_id == ^dungeon_id,
        order_by: [asc: floor.number],
        preload: [:nodes]
    )
  end

  defp floor_payload(%Floor{} = floor) do
    %{
      "id" => floor.id,
      "number" => floor.number,
      "name" => floor.name,
      "node_count" => length(floor.nodes || []),
      "resource_saturation" => floor_resource_saturation(floor)
    }
  end

  defp floor_resource_saturation(%Floor{} = floor) do
    nodes = floor.nodes || []

    if nodes == [] do
      0
    else
      nodes
      |> Enum.map(& &1.threat_level)
      |> Enum.sum()
      |> Kernel.div(length(nodes))
    end
  end

  defp activity_window(dungeon_id, now) do
    cutoff = DateTime.add(now, -3_600, :second)

    %{
      "recent_moves" => recent_move_count(dungeon_id, cutoff),
      "recent_combats" => recent_combat_count(dungeon_id, cutoff),
      "recent_extractions" => recent_extraction_count(dungeon_id, cutoff)
    }
  end

  defp recent_move_count(dungeon_id, cutoff) do
    Repo.aggregate(
      from(node_state in NodeState,
        join: run in Run,
        on: run.id == node_state.run_id,
        where: run.dungeon_id == ^dungeon_id and node_state.last_seen_at >= ^cutoff
      ),
      :count,
      :id
    )
  end

  defp recent_combat_count(dungeon_id, cutoff) do
    Repo.aggregate(
      from(encounter in Encounter,
        join: run in Run,
        on: run.id == encounter.run_id,
        where: run.dungeon_id == ^dungeon_id and encounter.updated_at >= ^cutoff
      ),
      :count,
      :id
    )
  end

  defp recent_extraction_count(dungeon_id, cutoff) do
    Repo.aggregate(
      from(extraction in Extraction,
        join: run in Run,
        on: run.id == extraction.run_id,
        where: run.dungeon_id == ^dungeon_id and extraction.updated_at >= ^cutoff
      ),
      :count,
      :id
    )
  end

  defp normalize_floor_directives(raw_directives, floors) when is_list(raw_directives) do
    floor_ids = MapSet.new(floors, & &1.id)

    directives =
      Enum.map(raw_directives, fn directive ->
        %{
          "floor_id" => directive["floor_id"],
          "threat_delta" => directive["threat_delta"],
          "resource_delta" => directive["resource_delta"],
          "connection_shift" => directive["connection_shift"],
          "anomaly_tag" => directive["anomaly_tag"]
        }
      end)

    if Enum.all?(directives, &valid_floor_directive?(&1, floor_ids)) do
      {:ok,
       Enum.map(directives, fn directive ->
         directive
         |> Map.update!("threat_delta", &clamp(&1, -5, 5))
         |> Map.update!("resource_delta", &clamp(&1, -5, 5))
       end)}
    else
      {:error, :invalid_floor_directives}
    end
  end

  defp normalize_floor_directives(_raw_directives, _floors),
    do: {:error, :invalid_floor_directives}

  defp valid_floor_directive?(directive, floor_ids) do
    is_binary(directive["floor_id"]) and
      MapSet.member?(floor_ids, directive["floor_id"]) and
      is_integer(directive["threat_delta"]) and
      is_integer(directive["resource_delta"]) and
      directive["connection_shift"] in ["stabilize", "block", "open"] and
      directive["anomaly_tag"] in ["none", "volatile", "wrath", "depleted", "echo", "predator"]
  end

  defp fallback_floor_directives(floors, state, activity_window) do
    pressure_signal = state.pressure_level + Map.get(activity_window, "recent_moves", 0)

    Enum.map(floors, fn floor ->
      %{
        "floor_id" => floor.id,
        "threat_delta" => clamp(div(pressure_signal + floor.number * 5, 25), -5, 5),
        "resource_delta" => clamp(-div(state.pressure_level, 25), -5, 5),
        "connection_shift" =>
          if(state.pressure_level >= 50 and floor.number >= 2, do: "block", else: "stabilize"),
        "anomaly_tag" => fallback_anomaly_tag(floor, state)
      }
    end)
  end

  defp fallback_anomaly_tag(%Floor{number: number}, %State{anomaly_level: anomaly_level})
       when anomaly_level >= 60 and number >= 2,
       do: "volatile"

  defp fallback_anomaly_tag(_floor, _state), do: "none"

  defp default_floor_directive(floor_id) do
    %{
      "floor_id" => floor_id,
      "threat_delta" => 0,
      "resource_delta" => 0,
      "connection_shift" => "stabilize",
      "anomaly_tag" => "none"
    }
  end

  defp emit_dungeon_tick_validation(dungeon_id, state, reason) do
    metadata = %{
      dungeon_id: dungeon_id,
      cycle_number: state.cycle_number,
      reason: inspect(reason)
    }

    :telemetry.execute([:mmgo, :dungeon, :tick, :validation_failure], %{count: 1}, metadata)
    Logger.warning("dungeon tick validation failed for #{dungeon_id}: #{inspect(reason)}")
  end

  defp emit_dungeon_tick_fallback(dungeon_id, state, reason) do
    metadata = %{
      dungeon_id: dungeon_id,
      cycle_number: state.cycle_number,
      reason: inspect(reason)
    }

    :telemetry.execute([:mmgo, :dungeon, :tick, :fallback], %{count: 1}, metadata)

    Logger.warning(
      "dungeon tick fell back to deterministic directives for #{dungeon_id}: #{inspect(reason)}"
    )
  end

  defp anomaly_tag_for(%Node{kind: :boss}, %State{anomaly_level: level}) when level >= 40,
    do: "wrath"

  defp anomaly_tag_for(%Node{kind: :rest}, %State{pressure_level: level}) when level >= 60,
    do: "depleted"

  defp anomaly_tag_for(%Node{kind: :room}, %State{anomaly_level: level}) when level >= 50,
    do: "volatile"

  defp anomaly_tag_for(_node, _state), do: nil

  defp count_active_runs(dungeon_id) do
    Repo.aggregate(
      from(run in Run, where: run.dungeon_id == ^dungeon_id and run.status == :active),
      :count,
      :id
    )
  end

  defp schedule_maintenance!(dungeon_id, maintenance_at) do
    %{"dungeon_id" => dungeon_id}
    |> MaintenanceWorker.new(
      schedule_in: max(DateTime.diff(maintenance_at, DateTime.utc_now(), :second), 0)
    )
    |> Oban.insert()
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
      nil ->
        Repo.rollback(run_changeset("target node is not reachable from the current node"))

      link ->
        case Repo.get_by(LinkState, dungeon_id: link.dungeon_id, link_id: link.id) do
          %LinkState{status: :blocked} ->
            Repo.rollback(run_changeset("target node path is currently blocked by the dungeon"))

          _other ->
            link
        end
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

  defp revealable_hidden_nodes(%Run{} = run, %Spell{} = spell) do
    if utility_reveal_spell?(spell) do
      Node
      |> where([node], node.floor_id == ^run.current_floor_id and node.id != ^run.current_node_id)
      |> order_by([node], asc: node.inserted_at)
      |> Repo.all()
      |> Enum.filter(&hidden_node?/1)
    else
      []
    end
  end

  defp utility_reveal_spell?(%Spell{} = spell) do
    Enum.any?(spell.effects, &(&1.state == "revealed"))
  end

  defp reveal_budget(%Spell{} = spell) do
    spell.effects
    |> Enum.filter(&(&1.state == "revealed"))
    |> Enum.map(&max(&1.intensity, 1))
    |> Enum.max(fn -> 0 end)
  end

  defp hidden_node?(%Node{} = node) do
    metadata = node.metadata || %{}
    value = metadata["hidden"] || metadata[:hidden]
    value in [true, "true", 1, "1"]
  end

  defp merge_utility_node_metadata(metadata, %Spell{} = spell, now, extra \\ %{}) do
    metadata = stringify_keys(metadata || %{})
    environment_states = metadata["environment_states"] || []
    applied_at = DateTime.to_iso8601(now)

    utility_states =
      spell.effects
      |> Enum.map(fn effect ->
        %{
          "state" => effect.state,
          "intensity" => effect.intensity,
          "spell_id" => spell.id,
          "applied_at" => applied_at
        }
      end)

    metadata
    |> Map.put(
      "environment_states",
      (environment_states ++ utility_states)
      |> Enum.uniq_by(&{&1["state"], &1["spell_id"]})
    )
    |> Map.merge(extra)
    |> Map.put("last_utility_spell_id", spell.id)
    |> Map.put("last_utility_spell_name", spell.name)
    |> Map.put("last_utility_applied_at", applied_at)
  end

  defp merge_utility_run_metadata(
         metadata,
         %Character{} = character,
         %Spell{} = spell,
         revealed_states,
         now
       ) do
    metadata = stringify_keys(metadata || %{})

    Map.put(metadata, "last_utility_spell", %{
      "spell_id" => spell.id,
      "spell_name" => spell.name,
      "character_id" => character.id,
      "character_name" => character.name,
      "revealed_node_ids" => Enum.map(revealed_states, & &1.node_id),
      "cast_at" => DateTime.to_iso8601(now)
    })
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
        attrs = default_encounter_attrs(run.dungeon_id, node, now, custom_encounter)

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
        attrs = default_resource_attrs(run.dungeon_id, node, custom_resource)

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

  defp default_encounter_attrs(dungeon_id, %Node{threat_level: threat_level} = node, now, nil)
       when threat_level > 0 do
    node_override = Repo.get_by(NodeOverride, dungeon_id: dungeon_id, node_id: node.id)
    adjusted_threat = max(threat_level + ((node_override && node_override.threat_bias) || 0), 1)

    %{
      "encounter_kind" => default_encounter_kind(node.kind),
      "status" => "pending",
      "threat_level" => adjusted_threat,
      "started_at" => now,
      "metadata" => %{
        "generated" => true,
        "anomaly_tag" => node_override && node_override.anomaly_tag
      }
    }
  end

  defp default_encounter_attrs(_dungeon_id, _node, _now, nil), do: nil

  defp default_encounter_attrs(_dungeon_id, _node, _now, attrs) when is_map(attrs),
    do: stringify_keys(attrs)

  defp default_resource_attrs(dungeon_id, %Node{kind: :rest} = node, nil) do
    node_override = Repo.get_by(NodeOverride, dungeon_id: dungeon_id, node_id: node.id)
    quantity_total = max(1 + ((node_override && node_override.resource_bias) || 0), 0)

    %{
      "resource_code" => "rest_supplies",
      "status" => if(quantity_total == 0, do: "depleted", else: "available"),
      "quantity_total" => quantity_total,
      "quantity_remaining" => quantity_total,
      "metadata" => %{
        "generated" => true,
        "anomaly_tag" => node_override && node_override.anomaly_tag
      }
    }
  end

  defp default_resource_attrs(dungeon_id, %Node{} = node, nil) do
    node_override = Repo.get_by(NodeOverride, dungeon_id: dungeon_id, node_id: node.id)
    quantity_total = max(1 + ((node_override && node_override.resource_bias) || 0), 0)

    if quantity_total == 0 do
      nil
    else
      %{
        "resource_code" => "salvage",
        "status" => "available",
        "quantity_total" => quantity_total,
        "quantity_remaining" => quantity_total,
        "metadata" => %{
          "generated" => true,
          "anomaly_tag" => node_override && node_override.anomaly_tag
        }
      }
    end
  end

  defp default_resource_attrs(_dungeon_id, _node, attrs) when is_map(attrs),
    do: stringify_keys(attrs)

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

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
