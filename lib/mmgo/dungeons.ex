defmodule MMGO.Dungeons do
  import Ecto.Query, warn: false

  alias MMGO.Actors
  alias Ecto.Changeset
  alias MMGO.Accounts.{Character, CharacterProfiles}
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
  alias MMGO.Notifications
  alias MMGO.Parties
  alias MMGO.Parties.{Expedition, ExpeditionMember}
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  @return_ritual_tag "return_ritual"
  @scavenging_game_days_per_unit 1
  @scavenging_xp_per_unit 3

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

  def list_links_for_dungeon(dungeon_id) when is_binary(dungeon_id) do
    Repo.all(
      from link in Link,
        where: link.dungeon_id == ^dungeon_id,
        order_by: [asc: link.inserted_at]
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

  def latest_failed_run_for_character(character_id) when is_binary(character_id) do
    Run
    |> join(:inner, [run], member in ExpeditionMember,
      on: member.expedition_id == run.expedition_id
    )
    |> where(
      [run, member],
      run.status == :failed and member.character_id == ^character_id and
        member.status == :completed
    )
    |> order_by([run, _member], desc: run.ended_at, desc: run.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
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

      node_overrides = refresh_node_overrides!(dungeon.id, updated_state)
      link_states = refresh_link_states!(dungeon.id, updated_state)
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

  @doc """
  Returns the caster-owned loadout facts needed to begin a Return Ritual.

  A generic ritual tag is deliberately not enough: the active grimoire must
  contain a spell explicitly marked `return_ritual`. This keeps the dungeon
  rule tied to a prepared, durable spell instead of a name or UI convention.
  """
  def return_ritual_loadout(%Character{} = character) do
    active_grimoire = active_grimoire_for_return_ritual(character)
    prepared_spell = return_ritual_spell_from(active_grimoire)

    %{
      wizardry_specialist?: ritual_caster?(character),
      active_grimoire?: not is_nil(active_grimoire),
      active_grimoire_id: active_grimoire && active_grimoire.id,
      prepared?: not is_nil(prepared_spell),
      prepared_spell_id: prepared_spell && prepared_spell.id,
      prepared_spell_name: prepared_spell && prepared_spell.name
    }
  end

  def return_ritual_loadout(_character) do
    %{
      wizardry_specialist?: false,
      active_grimoire?: false,
      active_grimoire_id: nil,
      prepared?: false,
      prepared_spell_id: nil,
      prepared_spell_name: nil
    }
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
      expedition = lock_expedition!(run.expedition_id)
      dungeon = Repo.get!(Dungeon, run.dungeon_id)

      cond do
        run.status != :active ->
          Repo.rollback(encounter_changeset("run is not active"))

        run.current_node_id != encounter.node_id ->
          Repo.rollback(encounter_changeset("encounter is not at the party's current node"))

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
          survival = Parties.expedition_survival_state(expedition)
          party_shared_hp = party_shared_hp(expedition_members, survival.shared_hp_drain)

          combat_attrs = %{
            participants: build_party_participants(expedition_members) ++ encounter_participants,
            sides: %{
              party: %{
                "label" => "Отряд",
                "shared_hp" => party_shared_hp,
                "max_shared_hp" => party_shared_hp
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
              "location_id" => expedition.location_id,
              "encounter_kind" => encounter.encounter_kind,
              "location_kind" => "dungeon",
              "survival" => %{
                "food_units_remaining" => survival.food_units_remaining,
                "foodless_game_days" => survival.foodless_game_days,
                "shared_hp_drain" => survival.shared_hp_drain
              },
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

      current_encounter = Repo.get_by(Encounter, run_id: run.id, node_id: run.current_node_id)

      if current_encounter && current_encounter.status in [:pending, :active] do
        Repo.rollback(run_changeset("current encounter must be resolved before moving"))
      end

      expedition = lock_expedition!(run.expedition_id)
      survival_result = Parties.advance_expedition_survival(expedition, link.travel_cost)

      updated_expedition =
        expedition
        |> Expedition.changeset(%{metadata: survival_result.metadata})
        |> Repo.update!()

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
          steps_taken: run.steps_taken + survival_result.effective_travel_cost
        })
        |> Repo.update!()

      content =
        materialize_node_content!(updated_run, target_node, now, content_attrs_from_opts(opts))

      %{
        run: preload_run(updated_run),
        expedition: updated_expedition,
        node_state: target_state,
        link: link,
        content: content,
        survival: survival_result.survival
      }
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

      {xp_rewards, route_plan_bonus} =
        if outcome == :cleared do
          expedition = lock_expedition!(run_expedition_id!(updated_encounter.run_id))

          {xp_amount, route_plan_bonus, _updated_expedition} =
            apply_route_plan_bonus!(
              expedition,
              encounter_xp(updated_encounter),
              updated_encounter.id,
              now
            )

          {
            Parties.distribute_xp_shares(Repo, expedition, xp_amount, %{
              "source_type" => "encounter",
              "reward_kind" => "xp",
              "run_id" => updated_encounter.run_id,
              "encounter_id" => updated_encounter.id,
              "granted_at" => now,
              "encounter_kind" => updated_encounter.encounter_kind,
              "club_route_plan_bonus" => route_plan_bonus
            }),
            route_plan_bonus
          }
        else
          {[], nil}
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
        xp_rewards: xp_rewards,
        route_plan_bonus: route_plan_bonus
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

  @doc """
  Harvests a current-node dungeon cache under its row lock.

  Every harvested unit consumes one persisted expedition game-day and grants a
  small equal XP share to each active expedition member. Inventory rewards stay
  with the harvesting character, preserving the existing loot ownership rule.
  """
  def harvest_resource(
        %ResourceCache{} = resource_cache,
        %Character{} = character,
        quantity,
        attrs \\ %{}
      )
      when is_integer(quantity) do
    attrs = stringify_keys(attrs)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      resource_cache =
        ResourceCache
        |> where([resource_cache], resource_cache.id == ^resource_cache.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload(:item_template)

      run = lock_run!(resource_cache.run_id)
      expedition = lock_expedition!(run.expedition_id)
      character = Repo.get!(Character, character.id)
      validate_resource_claim!(resource_cache, character, run, expedition, quantity)
      harvest_game_days = scavenging_game_days(quantity)

      reward_result =
        case resource_cache.item_template do
          nil -> {:ok, %{resource_code: resource_cache.resource_code, quantity: quantity}}
          item_template -> Inventory.grant_item(character, item_template, %{quantity: quantity})
        end

      case reward_result do
        {:ok, reward} ->
          remaining_quantity = resource_cache.quantity_remaining - quantity

          survival_result =
            Parties.advance_expedition_survival(expedition, harvest_game_days,
              activity: :scavenging
            )

          updated_expedition =
            expedition
            |> Expedition.changeset(%{metadata: survival_result.metadata})
            |> Repo.update!()

          updated_run =
            run
            |> Run.changeset(%{
              last_progressed_at: now,
              metadata: record_scavenging_time(run.metadata, harvest_game_days, now)
            })
            |> Repo.update!()

          xp_per_member = scavenging_xp_per_member(quantity)
          active_member_count = active_expedition_members(expedition.id) |> length()
          party_xp_awarded = xp_per_member * active_member_count

          xp_rewards =
            Parties.distribute_xp_shares(Repo, expedition, party_xp_awarded, %{
              "source" => "dungeon_scavenging",
              "source_type" => "run",
              "reward_kind" => "xp",
              "run_id" => run.id,
              "resource_cache_id" => resource_cache.id,
              "game_days_spent" => harvest_game_days,
              "xp_per_member" => xp_per_member,
              "reward_code_suffix" => "scavenge:#{resource_cache.id}:#{remaining_quantity}",
              "granted_at" => now
            })

          xp_awarded =
            Enum.find_value(xp_rewards, 0, fn reward ->
              if reward.character_id == character.id, do: reward.amount
            end)

          updated_character = Repo.get!(Character, character.id)

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
                |> Map.put("last_harvest_game_days", harvest_game_days)
                |> Map.put("last_harvest_xp", party_xp_awarded)
                |> Map.put("last_harvest_xp_per_member", xp_per_member)
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
              last_seen_at: now
            })
            |> Repo.update!()

          %{
            resource_cache: updated_resource_cache,
            node_state: updated_state,
            reward: reward,
            character: updated_character,
            xp_awarded: xp_awarded,
            xp_rewards: xp_rewards,
            party_xp_awarded: party_xp_awarded,
            harvest_game_days: harvest_game_days,
            run: preload_run(updated_run),
            expedition: updated_expedition,
            survival: survival_result.survival
          }

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
      %{position: %{node: current_node}} = validate_extraction_ready!(run, nil, :ascent, nil)

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

      %{
        position: %{node: current_node, floor: current_floor},
        ritual_loadout: ritual_loadout
      } = validate_extraction_ready!(run, caster, :return_ritual, nil)

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
          metadata: %{
            "ritual_game_days" => ritual_game_days,
            "origin_floor_number" => current_floor.number,
            "origin_node_id" => current_node.id,
            "prepared_grimoire_id" => ritual_loadout.active_grimoire_id,
            "prepared_spell_id" => ritual_loadout.prepared_spell_id
          }
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
    position = current_run_position(run)
    ritual_loadout = maybe_return_ritual_loadout(extraction_type, caster)

    cond do
      run.status != :active ->
        Repo.rollback(extraction_changeset("run is not active"))

      expedition.status != :active ->
        Repo.rollback(extraction_changeset("expedition is not active"))

      is_nil(position) ->
        Repo.rollback(extraction_changeset("run has no valid current dungeon node"))

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

      extraction_type == :return_ritual and not ritual_loadout.active_grimoire? ->
        Repo.rollback(extraction_changeset("ritual caster must have an active grimoire"))

      extraction_type == :return_ritual and not ritual_loadout.prepared? ->
        Repo.rollback(
          extraction_changeset("active grimoire must contain a prepared return ritual")
        )

      true ->
        %{position: position, ritual_loadout: ritual_loadout}
    end
  end

  defp ritual_caster?(%Character{} = character) do
    CharacterProfiles.mastered_track?(character, :wizardry) or
      case MMGO.Academy.active_specialization(character.id) do
        %MMGO.Academy.Specialization{track: :wizardry, realm_id: realm_id}
        when realm_id == character.realm_id ->
          true

        _other ->
          false
      end
  end

  defp ritual_caster?(_character), do: false

  defp maybe_return_ritual_loadout(:return_ritual, %Character{} = caster),
    do: return_ritual_loadout(caster)

  defp maybe_return_ritual_loadout(_extraction_type, _caster), do: nil

  defp active_grimoire_for_return_ritual(%Character{} = character) do
    case Grimoires.active_grimoire_for_character(character.id) do
      %{realm_id: realm_id} = grimoire when realm_id == character.realm_id ->
        Grimoires.get_grimoire!(grimoire.id)

      _other ->
        nil
    end
  end

  defp return_ritual_spell_from(nil), do: nil

  defp return_ritual_spell_from(%{entries: entries}) do
    Enum.find_value(entries, fn
      %{spell: %{tags: tags} = spell} when is_list(tags) ->
        if @return_ritual_tag in tags, do: spell

      _entry ->
        nil
    end)
  end

  defp return_ritual_spell_from(_grimoire), do: nil

  defp current_run_position(%Run{} = run) do
    with %Node{} = node <- Repo.get(Node, run.current_node_id),
         true <- node.floor_id == run.current_floor_id,
         %Floor{} = floor <- Repo.get(Floor, node.floor_id),
         true <- floor.dungeon_id == run.dungeon_id do
      %{node: node, floor: floor}
    else
      _other -> nil
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

  defp refresh_node_overrides!(dungeon_id, %State{} = state) do
    nodes =
      Node
      |> join(:inner, [node], floor in assoc(node, :floor))
      |> where([_node, floor], floor.dungeon_id == ^dungeon_id)
      |> Repo.all()

    Enum.map(nodes, fn node ->
      base_status =
        if state.pressure_level >= 60 and node.kind == :rest, do: :depleted, else: :stable

      threat_bias =
        if node.kind in [:room, :hazard, :boss],
          do: min(div(state.pressure_level, 5), 20),
          else: 0

      resource_bias =
        if node.kind == :rest,
          do: -min(div(state.pressure_level, 10), 5),
          else: max(5 - div(state.pressure_level, 20), -5)

      anomaly_tag = anomaly_tag_for(node, state)

      case Repo.get_by(NodeOverride, dungeon_id: dungeon_id, node_id: node.id) do
        nil ->
          %NodeOverride{}
          |> NodeOverride.changeset(%{
            dungeon_id: dungeon_id,
            node_id: node.id,
            status: base_status,
            threat_bias: threat_bias,
            resource_bias: resource_bias,
            anomaly_tag: anomaly_tag,
            metadata: %{"cycle_number" => state.cycle_number}
          })
          |> Repo.insert!()

        %NodeOverride{} = node_override ->
          node_override
          |> NodeOverride.changeset(%{
            status: base_status,
            threat_bias: threat_bias,
            resource_bias: resource_bias,
            anomaly_tag: anomaly_tag,
            metadata: Map.put(node_override.metadata || %{}, "cycle_number", state.cycle_number)
          })
          |> Repo.update!()
      end
    end)
  end

  defp refresh_link_states!(dungeon_id, %State{} = state) do
    links = Repo.all(from link in Link, where: link.dungeon_id == ^dungeon_id)

    Enum.map(links, fn link ->
      status =
        if rem(state.cycle_number + link.travel_cost, 4) == 0 and state.pressure_level >= 20,
          do: :blocked,
          else: :active

      case Repo.get_by(LinkState, dungeon_id: dungeon_id, link_id: link.id) do
        nil ->
          %LinkState{}
          |> LinkState.changeset(%{
            dungeon_id: dungeon_id,
            link_id: link.id,
            status: status,
            metadata: %{"cycle_number" => state.cycle_number}
          })
          |> Repo.insert!()

        %LinkState{} = link_state ->
          link_state
          |> LinkState.changeset(%{
            status: status,
            metadata: Map.put(link_state.metadata || %{}, "cycle_number", state.cycle_number)
          })
          |> Repo.update!()
      end
    end)
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

  defp apply_route_plan_bonus!(%Expedition{} = expedition, base_xp, encounter_id, now) do
    case Map.get(expedition.metadata || %{}, "club_route_plan") do
      %{"status" => "available", "xp_bonus_bps" => bonus_bps} = route_plan
      when is_integer(bonus_bps) and bonus_bps > 0 ->
        bonus_bps = min(bonus_bps, 2_500)
        xp_bonus = max(div(max(base_xp, 1) * bonus_bps + 9_999, 10_000), 1)

        consumed_route_plan =
          route_plan
          |> Map.put("status", "consumed")
          |> Map.put("consumed_at", DateTime.to_iso8601(now))
          |> Map.put("consumed_for_encounter_id", encounter_id)
          |> Map.put("xp_awarded", xp_bonus)

        updated_expedition =
          expedition
          |> Expedition.changeset(%{
            metadata: Map.put(expedition.metadata || %{}, "club_route_plan", consumed_route_plan)
          })
          |> Repo.update!()

        {base_xp + xp_bonus, %{"xp_awarded" => xp_bonus, "xp_bonus_bps" => bonus_bps},
         updated_expedition}

      _other ->
        {base_xp, nil, expedition}
    end
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

  defp party_shared_hp(expedition_members, shared_hp_drain) do
    expedition_members
    |> length()
    |> max(1)
    |> Kernel.*(100)
    |> Kernel.-(shared_hp_drain)
    |> max(1)
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

  defp encounter_label(%Encounter{encounter_kind: "boss"}), do: "Хранитель глубин"
  defp encounter_label(%Encounter{encounter_kind: "hazard"}), do: "Опасная аномалия"
  defp encounter_label(%Encounter{encounter_kind: "skirmish"}), do: "Стычка"
  defp encounter_label(%Encounter{}), do: "Неизвестная угроза"

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
    run = Repo.get!(Run, loot_drop.run_id)

    cond do
      loot_drop.status != :available ->
        Repo.rollback(loot_changeset("loot has already been claimed"))

      run.current_node_id != loot_drop.node_id ->
        Repo.rollback(loot_changeset("loot must be claimed at the current dungeon node"))

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
         %Run{} = run,
         %Expedition{} = expedition,
         quantity
       ) do
    cond do
      quantity <= 0 ->
        Repo.rollback(resource_changeset("quantity must be greater than zero"))

      run.status != :active ->
        Repo.rollback(resource_changeset("dungeon run is not active"))

      expedition.status != :active ->
        Repo.rollback(resource_changeset("expedition is not active"))

      resource_cache.status != :available ->
        Repo.rollback(resource_changeset("resource cache is depleted"))

      quantity > resource_cache.quantity_remaining ->
        Repo.rollback(resource_changeset("quantity exceeds the remaining resources"))

      run.current_node_id != resource_cache.node_id ->
        Repo.rollback(
          resource_changeset("resource must be harvested at the current dungeon node")
        )

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

  defp record_scavenging_time(metadata, game_days, now) do
    metadata = if is_map(metadata), do: metadata, else: %{}

    previous_game_days =
      case Map.get(metadata, "scavenging_game_days") do
        value when is_integer(value) and value >= 0 -> value
        _other -> 0
      end

    metadata
    |> Map.put("scavenging_game_days", previous_game_days + game_days)
    |> Map.put("last_scavenged_at", DateTime.to_iso8601(now))
  end

  defp scavenging_game_days(quantity), do: quantity * @scavenging_game_days_per_unit
  defp scavenging_xp_per_member(quantity), do: max(quantity * @scavenging_xp_per_unit, 1)

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
