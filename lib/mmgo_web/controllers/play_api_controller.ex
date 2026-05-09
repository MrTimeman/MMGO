defmodule MMGOWeb.PlayApiController do
  use MMGOWeb, :controller

  import Ecto.Query

  alias MMGO.{Accounts, Combat, Dungeons, Grimoires, Parties, Play, PVP, Repo, Worlds}
  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Engine, Turn}
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Dungeons.{Encounter, Link, LinkState, Node, NodeState, Run}
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Parties.{Expedition, Membership}
  alias MMGOWeb.PlaySession

  # ── Hub ──────────────────────────────────────────────────────────────────

  def hub(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn) do
      duels =
        PVP.list_open_duels_for_character(character.id)
        |> Repo.preload([:opponent_character, :challenger_character, :combat])

      active_expedition = Parties.active_expedition_for_character(character.id)

      active_run =
        case active_expedition do
          nil -> nil
          %Expedition{} = expedition -> Dungeons.active_run_for_expedition(expedition.id)
        end

      run_payload =
        case active_run do
          nil ->
            nil

          %Run{} = run ->
            run = Repo.preload(run, [:dungeon, :current_node])

            %{
              run_id: run.id,
              dungeon_id: run.dungeon_id,
              dungeon_name: run.dungeon && run.dungeon.name,
              current_node_name: run.current_node && run.current_node.name,
              steps_taken: run.steps_taken,
              status: to_string(run.status)
            }
        end

      active_party = Parties.active_party_for_character(character.id)

      party_payload =
        case active_party do
          nil ->
            nil

          party ->
            party = Repo.preload(party, memberships: :character)
            members = Enum.filter(party.memberships, &(&1.status == :active))

            %{
              id: party.id,
              name: party.name,
              members:
                Enum.map(
                  members,
                  &%{
                    id: &1.character_id,
                    name: &1.character && &1.character.name,
                    role: to_string(&1.role)
                  }
                )
            }
        end

      realm = Worlds.get_default_realm()
      dungeons = if realm, do: Dungeons.list_dungeons_for_realm(realm.id), else: []

      dungeon_list =
        Enum.map(
          dungeons,
          &%{id: &1.id, name: &1.name, slug: &1.slug, status: to_string(&1.status)}
        )

      spell_count =
        case Grimoires.active_grimoire_for_character(character.id) do
          nil ->
            0

          %Grimoire{} = grimoire ->
            Repo.aggregate(from(e in GrimoireEntry, where: e.grimoire_id == ^grimoire.id), :count)
        end

      json(conn, %{
        ok: true,
        state: %{
          character: %{name: character.name, level: character.level, id: character.id},
          duels: Enum.map(duels, &duel_payload/1),
          active_run: run_payload,
          party: party_payload,
          dungeons: dungeon_list,
          spells: %{count: spell_count}
        }
      })
    end
  end

  def state(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  # ── Character Search ─────────────────────────────────────────────────────

  def search_characters(conn, %{"q" => query}) when byte_size(query) > 0 do
    pattern = "%#{query}%"

    characters =
      from(c in Character,
        join: a in assoc(c, :account),
        where: ilike(c.name, ^pattern) or ilike(a.handle, ^pattern),
        limit: 10,
        select: %{id: c.id, name: c.name, level: c.level, handle: a.handle}
      )
      |> Repo.all()

    json(conn, %{ok: true, characters: characters})
  end

  def search_characters(conn, _params) do
    json(conn, %{ok: true, characters: []})
  end

  # ── Duels ────────────────────────────────────────────────────────────────

  def create_duel(conn, %{"opponent_id" => opponent_id, "wager_amount" => wager_param}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, wager} <- parse_positive_integer(wager_param),
         %Character{} = opponent <- Accounts.get_character!(opponent_id),
         {:ok, duel} <- PVP.challenge_duel(character, opponent, wager),
         {:ok, accepted_duel} <- PVP.accept_duel(duel),
         {:ok, result} <- resolve_combat(accepted_duel.combat_id) do
      json(conn, %{ok: true, result: result})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} when is_atom(reason) ->
        json(conn, %{ok: false, error: format_error(reason)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})

      _ ->
        json(conn, %{ok: false, error: "invalid_request"})
    end
  end

  def create_duel(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "opponent_id and wager_amount required"})
  end

  defp resolve_combat(nil), do: {:ok, %{winner: "draw", turns: 0}}

  defp resolve_combat(combat_id) when is_binary(combat_id) do
    combat =
      Combat.get_combat!(combat_id)
      |> Repo.preload(participants: [:character, :actor_template, grimoire: :entries])

    # Run up to 5 turns or until resolution
    result = run_combat_turns(combat, 5)
    {:ok, result}
  end

  defp run_combat_turns(combat, 0) do
    # Close combat as draw
    combat
    |> CombatSchema.changeset(%{
      status: :finished,
      metadata: Map.put(combat.metadata || %{}, "resolution", "draw")
    })
    |> Repo.update!()

    %{winner: "draw", turns: combat.turn_number - 1}
  end

  defp run_combat_turns(combat, remaining) do
    turn = Repo.get_by!(Turn, combat_id: combat.id, number: combat.turn_number)
    participants = combat.participants

    # Preload spells for grimoire entries
    spell_ids =
      Enum.flat_map(participants, fn p ->
        ((p.grimoire && p.grimoire.entries) || [])
        |> Enum.map(& &1.spell_id)
        |> Enum.reject(&is_nil/1)
      end)

    spells_map =
      if spell_ids != [] do
        from(s in MMGO.Spells.Spell, where: s.id in ^spell_ids)
        |> Repo.all()
        |> Map.new(fn s -> {s.id, s} end)
      else
        %{}
      end

    # Generate simple actions for each participant
    now = DateTime.utc_now()

    actions =
      Enum.map(participants, fn p ->
        spell_entry = Enum.find((p.grimoire && p.grimoire.entries) || [], fn e -> e.spell_id end)
        target = Enum.find(Enum.reject(participants, &(&1.id == p.id)), fn _ -> true end)

        %Action{
          participant_id: p.id,
          combat_turn_id: turn.id,
          action_type: if(spell_entry, do: :cast_spell, else: :wait),
          spell_id: spell_entry && spell_entry.spell_id,
          spell: spells_map[spell_entry && spell_entry.spell_id],
          target_participant_id: target && target.id,
          target_side: target && target.side,
          submitted_at: now
        }
      end)

    resolution = Engine.resolve_turn(combat, turn, participants, actions)

    # Apply resolution directly for auto-resolution
    {:ok, final_combat} =
      combat
      |> CombatSchema.changeset(resolution.combat_attrs)
      |> Repo.update()

    # Update turn
    turn
    |> Turn.changeset(resolution.turn_attrs)
    |> Repo.update()

    # Create next turn if needed
    if resolution.create_next_turn? do
      %Turn{combat_id: combat.id, number: combat.turn_number + 1, status: :open}
      |> Repo.insert!()
    end

    if final_combat.status in [:finished, :resolved] do
      winner =
        case final_combat.metadata do
          %{"winner_id" => id} ->
            Enum.find(participants, &(&1.id == id || &1.character_id == id))
            |> then(fn p -> p && ((p.character && p.character.name) || "NPC") end)

          _ ->
            "draw"
        end

      %{
        winner: winner || "draw",
        turns: combat.turn_number,
        status: to_string(final_combat.status)
      }
    else
      run_combat_turns(final_combat, remaining - 1)
    end
  end

  # ── Spells ───────────────────────────────────────────────────────────────

  def list_spells(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn) do
      spells =
        case Grimoires.active_grimoire_for_character(character.id) do
          nil ->
            []

          %Grimoire{} = grimoire ->
            grimoire = Repo.preload(grimoire, entries: :spell)

            grimoire.entries
            |> Enum.map(& &1.spell)
            |> Enum.reject(&is_nil/1)
            |> Enum.map(fn spell ->
              %{
                id: spell.id,
                name: spell.name,
                school: to_string(spell.school),
                targeting: to_string(spell.targeting),
                delivery_form: to_string(spell.delivery_form),
                spell_type: to_string(spell.spell_type),
                fatigue_cost: spell.fatigue_cost
              }
            end)
        end

      json(conn, %{ok: true, spells: spells})
    end
  end

  def create_spell(conn, %{"name" => name, "formula" => formula, "school" => school}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn) do
      attrs = %{
        "name" => name,
        "formula" => formula,
        "school" => school,
        "targeting" => Map.get(conn.params, "targeting", "enemy"),
        "delivery_form" => Map.get(conn.params, "delivery_form", "beam")
      }

      case MMGO.Spells.Compiler.compile_and_store(character, attrs) do
        {:ok, %{spell: spell}} ->
          case activate_grimoire_with_spell(character, spell) do
            {:ok, _grimoire} ->
              json(conn, %{ok: true, spell: spell_payload(spell)})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: "grimoire inscription failed: #{format_error(reason)}"})
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{ok: false, error: format_error(changeset)})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{ok: false, error: format_error(reason)})
      end
    end
  end

  def create_spell(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "name, formula, and school required"})
  end

  def create_journey(conn, %{"route_id" => route_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _result} <- Play.start_journey(character, route_id),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def create_journey(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "route_id required"})
  end

  def cast_utility_spell(conn, %{"spell_id" => spell_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _spell} <- Play.cast_utility_spell(character, spell_id),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def cast_utility_spell(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "spell_id required"})
  end

  defp activate_grimoire_with_spell(character, spell) do
    case Grimoires.active_grimoire_for_character(character.id) do
      nil ->
        with {:ok, draft} <-
               Grimoires.create_grimoire(character, %{name: "#{character.name}'s Grimoire"}),
             {:ok, _entry} <- Grimoires.inscribe_spell(draft, spell),
             {:ok, %{activate_grimoire: grimoire}} <-
               Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(draft.id)) do
          {:ok, grimoire}
        end

      %Grimoire{} = active_grimoire ->
        active_grimoire = Repo.preload(active_grimoire, entries: :spell)
        copy_active_grimoire_with_spell(character, active_grimoire, spell)
    end
  end

  defp copy_active_grimoire_with_spell(character, active_grimoire, spell) do
    next_size = length(active_grimoire.entries) + 1
    capacity = active_grimoire.capacity |> max(next_size) |> min(45)

    with {:ok, draft} <-
           Grimoires.create_grimoire(character, %{
             name: next_grimoire_name(active_grimoire.name),
             capacity: capacity,
             weight: active_grimoire.weight
           }),
         :ok <- copy_grimoire_entries(draft, active_grimoire.entries),
         {:ok, _new_entry} <- Grimoires.inscribe_spell(draft, spell),
         {:ok, %{activate_grimoire: grimoire}} <-
           Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(draft.id)) do
      {:ok, grimoire}
    end
  end

  defp copy_grimoire_entries(draft, entries) do
    entries
    |> Enum.sort_by(& &1.slot_index)
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      case Grimoires.inscribe_spell(draft, entry.spell, %{slot_index: entry.slot_index}) do
        {:ok, _entry} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp next_grimoire_name(name) when is_binary(name) do
    "#{String.slice(name, 0, 100)} +"
  end

  defp spell_payload(spell) do
    %{
      id: spell.id,
      name: spell.name,
      school: to_string(spell.school),
      targeting: to_string(spell.targeting),
      delivery_form: to_string(spell.delivery_form),
      formula: spell.formula,
      fatigue_cost: spell.fatigue_cost,
      cooldown_turns: spell.cooldown_turns,
      effects:
        Enum.map(spell.effects || [], fn effect ->
          %{state: effect.state, intensity: effect.intensity}
        end)
    }
  end

  # ── Dungeons ─────────────────────────────────────────────────────────────

  def enter_dungeon(conn, %{"dungeon_id" => dungeon_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         dungeon when not is_nil(dungeon) <- Dungeons.get_dungeon!(dungeon_id),
         {:ok, expedition} <- ensure_expedition(character, dungeon),
         {:ok, %{run: run}} <- Dungeons.enter_dungeon(expedition, dungeon) do
      run = Repo.preload(run, [:current_node, :dungeon])

      json(conn, %{
        ok: true,
        run: %{
          run_id: run.id,
          dungeon_name: dungeon.name,
          current_node_name: run.current_node.name,
          current_node_kind: to_string(run.current_node.kind),
          steps_taken: run.steps_taken
        }
      })
    else
      nil ->
        json(conn, %{ok: false, error: "dungeon not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def enter_dungeon(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "dungeon_id required"})
  end

  def leave_party(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn) do
      case Parties.active_expedition_for_character(character.id) do
        %Expedition{} = expedition -> Parties.end_expedition(expedition, %{status: :aborted})
        nil -> :ok
      end

      case Parties.active_party_for_character(character.id) do
        nil ->
          json(conn, %{ok: true})

        party ->
          case Parties.remove_member(party, character) do
            {:ok, _} ->
              json(conn, %{ok: true})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: format_error(reason)})
          end
      end
    end
  end

  def dungeon_state(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      run = Repo.preload(run, [:dungeon, :current_node])

      json(conn, %{ok: true, state: dungeon_state_payload(run)})
    else
      nil -> json(conn, %{ok: false, error: "no active dungeon run"})
      _ -> json(conn, %{ok: false, error: "could not load dungeon state"})
    end
  end

  defp dungeon_state_payload(%Run{} = run) do
    run =
      run
      |> Repo.preload([:dungeon, current_node: :floor])

    encounters =
      Dungeons.list_encounters_for_run(run.id)
      |> Enum.map(&encounter_payload/1)

    resources =
      Dungeons.list_resource_caches_for_run(run.id)
      |> Enum.map(&resource_payload/1)

    loot_drops =
      Dungeons.list_loot_drops_for_run(run.id)
      |> Enum.map(&loot_drop_payload/1)

    active_extraction = Dungeons.active_extraction(run.id)

    build_dungeon_state(run, encounters, resources, loot_drops, active_extraction)
  end

  defp build_dungeon_state(run, encounters, resources, loot_drops, active_extraction) do
    dungeon_id = run.dungeon_id

    all_nodes =
      from(n in Node,
        join: f in assoc(n, :floor),
        where: f.dungeon_id == ^dungeon_id,
        order_by: [asc: f.number, asc: n.y, asc: n.x],
        preload: [floor: f]
      )
      |> Repo.all()

    all_links =
      from(l in Link,
        where: l.dungeon_id == ^dungeon_id,
        order_by: [asc: l.inserted_at]
      )
      |> Repo.all()

    link_states =
      from(ls in LinkState,
        where: ls.dungeon_id == ^dungeon_id,
        select: {ls.link_id, ls.status}
      )
      |> Repo.all()
      |> Map.new()

    node_states =
      from(ns in NodeState,
        where: ns.run_id == ^run.id
      )
      |> Repo.all()
      |> Map.new(&{&1.node_id, &1})

    current_id = run.current_node_id

    reachable_ids =
      all_links
      |> Enum.reject(&(Map.get(link_states, &1.id) == :blocked))
      |> Enum.flat_map(fn l ->
        cond do
          l.from_node_id == current_id -> [l.to_node_id]
          l.bidirectional && l.to_node_id == current_id -> [l.from_node_id]
          true -> []
        end
      end)
      |> MapSet.new()

    encounter_by_node = Enum.group_by(encounters, & &1.node_id)
    resource_by_node = Enum.group_by(resources, & &1.node_id)
    loot_by_node = Enum.group_by(loot_drops, & &1.node_id)

    nodes =
      all_nodes
      |> Enum.map(fn n ->
        build_node_payload(
          n,
          Map.get(node_states, n.id),
          current_id,
          reachable_ids,
          Map.get(encounter_by_node, n.id, []),
          Map.get(resource_by_node, n.id, []),
          Map.get(loot_by_node, n.id, [])
        )
      end)

    node_by_id = Map.new(nodes, &{&1.id, &1})
    current_node = Map.get(node_by_id, current_id)

    exits =
      reachable_ids
      |> Enum.map(&Map.get(node_by_id, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&{&1.floor_number || 0, &1.name})

    corridors =
      all_links
      |> Enum.map(fn l ->
        from_node = Map.get(node_by_id, l.from_node_id)
        to_node = Map.get(node_by_id, l.to_node_id)
        from_visible? = visible_node?(from_node)
        to_visible? = visible_node?(to_node)
        status = Map.get(link_states, l.id, :active)

        %{
          id: l.id,
          from_id: l.from_node_id,
          to_id: l.to_node_id,
          bidirectional: l.bidirectional,
          travel_cost: l.travel_cost,
          status: to_string(status),
          known: from_visible? and to_visible?,
          visible: from_visible? or to_visible?
        }
      end)

    visible_nodes = Enum.filter(nodes, &visible_node?/1)
    pending_encounters = Enum.count(encounters, &(&1.status in ["pending", "active"]))
    current_encounters = if current_node, do: current_node.encounters, else: []

    current_has_active_encounter? = Enum.any?(current_encounters, &(&1.status == "active"))

    can_extract_via_ascent? =
      current_node &&
        current_node.kind in ["entrance", "stairs_up", "exit"] &&
        not current_has_active_encounter? &&
        is_nil(active_extraction)

    return_ritual_available? =
      current_node &&
        not current_has_active_encounter? &&
        is_nil(active_extraction)

    %{
      run_id: run.id,
      dungeon_name: run.dungeon && run.dungeon.name,
      floor: floor_payload(run.current_node && run.current_node.floor),
      current_node_id: current_id,
      current_node: current_node && Map.put(current_node, :exits, exits),
      steps_taken: run.steps_taken,
      status: to_string(run.status),
      objective: dungeon_objective(current_node, exits, active_extraction),
      progress: %{
        known_nodes: length(visible_nodes),
        total_nodes: length(nodes),
        explored_percent: explored_percent(visible_nodes, nodes),
        pending_encounters: pending_encounters,
        cleared_encounters: Enum.count(encounters, &(&1.status == "cleared")),
        available_resources: Enum.count(resources, &(&1.status == "available")),
        available_loot: Enum.count(loot_drops, &(&1.status == "available")),
        danger_label: danger_label(current_node && current_node.threat_level)
      },
      extraction: %{
        can_ascent: can_extract_via_ascent?,
        return_ritual_available: return_ritual_available?,
        active: extraction_payload(active_extraction)
      },
      nodes: nodes,
      corridors: corridors,
      encounters: encounters,
      resources: resources,
      loot_drops: loot_drops
    }
  end

  def move_in_dungeon(conn, %{"to_node_id" => node_id}) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{run: updated_run}} <- Dungeons.move_run(run, node_id) do
      json(conn, %{ok: true, state: dungeon_state_payload(updated_run)})
    else
      nil ->
        json(conn, %{ok: false, error: "no active dungeon run"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def move_in_dungeon(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "to_node_id required"})
  end

  def fight_encounter(conn, %{"encounter_id" => encounter_id}) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Encounter{} = encounter <- Dungeons.get_encounter!(encounter_id),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         true <- encounter.run_id == run.id,
         {:ok, %{combat: combat}} <- Dungeons.start_encounter_combat(encounter),
         {:ok, result} <- resolve_combat(combat.id),
         {:ok, _resolved} <- Dungeons.sync_encounter_combat(combat) do
      json(conn, %{ok: true, result: result})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "encounter does not belong to your active run"})
    end
  end

  def fight_encounter(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "encounter_id required"})
  end

  def harvest_resource(conn, %{"resource_cache_id" => resource_cache_id}) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         resource_cache <- Dungeons.get_resource_cache!(resource_cache_id),
         true <- resource_cache.run_id == run.id,
         quantity when quantity > 0 <- resource_cache.quantity_remaining,
         {:ok, _result} <- Dungeons.harvest_resource(resource_cache, character, quantity) do
      json(conn, %{ok: true, state: dungeon_state_payload(run)})
    else
      nil ->
        json(conn, %{ok: false, error: "no active dungeon run"})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "resource does not belong to your active run"})

      0 ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "resource cache is depleted"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def harvest_resource(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "resource_cache_id required"})
  end

  def claim_loot(conn, %{"loot_drop_id" => loot_drop_id}) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         loot_drop <- Dungeons.get_loot_drop!(loot_drop_id),
         true <- loot_drop.run_id == run.id,
         {:ok, _result} <- Dungeons.claim_loot(loot_drop, character) do
      json(conn, %{ok: true, state: dungeon_state_payload(run)})
    else
      nil ->
        json(conn, %{ok: false, error: "no active dungeon run"})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "loot does not belong to your active run"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def claim_loot(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "loot_drop_id required"})
  end

  def extract_dungeon(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, result} <- Dungeons.extract_via_ascent(run) do
      json(conn, %{ok: true, result: run_exit_payload(result)})
    else
      nil ->
        json(conn, %{ok: false, error: "no active dungeon run"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def return_ritual(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{extraction: extraction}} <-
           Dungeons.start_return_ritual(run, character, ritual_game_days: 0),
         {:ok, result} <- Dungeons.complete_extraction_by_id(extraction.id, force: true) do
      json(conn, %{ok: true, result: run_exit_payload(result)})
    else
      nil ->
        json(conn, %{ok: false, error: "no active dungeon run"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_error(reason)})
    end
  end

  defp build_node_payload(
         %Node{} = node,
         node_state,
         current_id,
         reachable_ids,
         encounters,
         resources,
         loot_drops
       ) do
    reachable? = MapSet.member?(reachable_ids, node.id)

    state =
      cond do
        node.id == current_id -> "here"
        node_state && node_state.status == :blocked -> "blocked"
        node_state && node_state.status == :cleared -> "cleared"
        node_state -> "visited"
        reachable? -> "reachable"
        true -> "hidden"
      end

    %{
      id: node.id,
      slug: node.slug,
      name: node.name,
      kind: to_string(node.kind),
      kind_label: node_kind_label(node.kind),
      description: node_description(node),
      x: node.x,
      y: node.y,
      floor_id: node.floor_id,
      floor_number: node.floor && node.floor.number,
      floor_name: node.floor && node.floor.name,
      threat_level: node.threat_level,
      threat_label: danger_label(node.threat_level),
      state: state,
      reachable: reachable?,
      visit_count: (node_state && node_state.visit_count) || 0,
      encounter_status: node_state && to_string(node_state.encounter_status),
      resource_status: node_state && to_string(node_state.resource_status),
      environment_states: environment_states(node_state),
      encounters: encounters,
      resources: resources,
      loot_drops: loot_drops
    }
  end

  defp visible_node?(%{state: "hidden"}), do: false
  defp visible_node?(nil), do: false
  defp visible_node?(_node), do: true

  defp floor_payload(nil), do: nil

  defp floor_payload(floor) do
    %{id: floor.id, number: floor.number, name: floor.name}
  end

  defp encounter_payload(%Encounter{} = encounter) do
    %{
      id: encounter.id,
      node_id: encounter.node_id,
      kind: encounter.encounter_kind,
      label: encounter_label(encounter.encounter_kind),
      status: to_string(encounter.status),
      threat_level: encounter.threat_level,
      threat_label: danger_label(encounter.threat_level)
    }
  end

  defp resource_payload(resource_cache) do
    item_name = resource_cache.item_template && resource_cache.item_template.name

    %{
      id: resource_cache.id,
      node_id: resource_cache.node_id,
      code: resource_cache.resource_code,
      label: item_name || resource_label(resource_cache.resource_code),
      status: to_string(resource_cache.status),
      quantity_total: resource_cache.quantity_total,
      quantity_remaining: resource_cache.quantity_remaining
    }
  end

  defp loot_drop_payload(loot_drop) do
    item_name = loot_drop.item_template && loot_drop.item_template.name

    %{
      id: loot_drop.id,
      node_id: loot_drop.node_id,
      label: loot_label(loot_drop, item_name),
      status: to_string(loot_drop.status),
      reward_kind: to_string(loot_drop.reward_kind),
      amount: loot_drop.amount
    }
  end

  defp extraction_payload(nil), do: nil

  defp extraction_payload(extraction) do
    %{
      id: extraction.id,
      type: to_string(extraction.extraction_type),
      status: to_string(extraction.status),
      completes_at: extraction.completes_at && DateTime.to_iso8601(extraction.completes_at)
    }
  end

  defp run_exit_payload(%{run: run} = result) do
    %{
      run_id: run.id,
      status: to_string(run.status),
      xp_reward_count: length(Map.get(result, :xp_rewards, [])),
      dropped_item_count: length(Map.get(result, :drops, []))
    }
  end

  defp dungeon_objective(nil, _exits, _active_extraction), do: "Карта подземелья загружается."

  defp dungeon_objective(_current_node, _exits, active_extraction)
       when not is_nil(active_extraction) do
    "Ритуал возврата уже начат. Держите позицию, пока башенный круг тянет отряд наверх."
  end

  defp dungeon_objective(current_node, exits, _active_extraction) do
    active_encounter? = Enum.any?(current_node.encounters, &(&1.status == "active"))
    pending_encounter? = Enum.any?(current_node.encounters, &(&1.status == "pending"))
    available_resource? = Enum.any?(current_node.resources, &(&1.status == "available"))
    available_loot? = Enum.any?(current_node.loot_drops, &(&1.status == "available"))

    cond do
      active_encounter? ->
        "Бой уже начат. Сначала завершите столкновение, затем решайте куда идти."

      pending_encounter? ->
        "В комнате есть угроза. Можно сразиться, обойти ее или уйти к точке подъема."

      available_loot? ->
        "Добыча лежит здесь. Заберите ценное или уходите налегке, если путь важнее груза."

      available_resource? ->
        "Здесь есть припасы. Пополните запас перед следующим переходом."

      current_node.kind in ["entrance", "stairs_up", "exit"] ->
        "Это точка подъема. Можно завершить вылазку или продолжить глубже."

      exits == [] ->
        "Тупик. Нужен другой путь, разведка или ритуал возврата."

      true ->
        "Выберите следующий выход. Каждый переход углубляет вылазку и поднимает риск."
    end
  end

  defp explored_percent(_visible_nodes, []), do: 0

  defp explored_percent(visible_nodes, nodes) do
    round(length(visible_nodes) / max(length(nodes), 1) * 100)
  end

  defp environment_states(nil), do: []

  defp environment_states(%NodeState{} = node_state) do
    case Map.get(node_state.metadata || %{}, "environment_states") do
      states when is_list(states) -> states
      _other -> []
    end
  end

  defp node_description(%Node{} = node) do
    metadata = node.metadata || %{}

    Map.get(metadata, "description") ||
      Map.get(metadata, :description) ||
      default_node_description(node.kind)
  end

  defp default_node_description(:entrance),
    do: "Стабильная арка под Башней. Свет сверху еще держится, но ниже уже слышно движение."

  defp default_node_description(:rest),
    do:
      "Полусухое место с чужими отметками на камне. Здесь можно собрать припасы и привести отряд в порядок."

  defp default_node_description(:hazard),
    do: "Проход испорчен аномалией. Воздух дрожит, камень реагирует на шаги слишком поздно."

  defp default_node_description(:boss),
    do: "Узел глубины давит на слух. Здесь живет сильная угроза, и подземелье будто ждет решения."

  defp default_node_description(:stairs_up),
    do: "Старый подъем к безопасному маршруту. До поверхности далеко, но направление надежное."

  defp default_node_description(:stairs_down),
    do: "Лестница уходит ниже. Холодный воздух тянет вниз, обещая лучшие находки и худшие ошибки."

  defp default_node_description(:exit),
    do: "Закрепленная точка выхода. Отсюда можно вывести отряд и сохранить результат вылазки."

  defp default_node_description(_kind),
    do: "Комната еще не нанесена на карту полностью. Стены отмечены следами прежних отрядов."

  defp node_kind_label(:entrance), do: "вход"
  defp node_kind_label(:rest), do: "привал"
  defp node_kind_label(:hazard), do: "аномалия"
  defp node_kind_label(:boss), do: "страж"
  defp node_kind_label(:stairs_up), do: "подъем"
  defp node_kind_label(:stairs_down), do: "спуск"
  defp node_kind_label(:exit), do: "выход"
  defp node_kind_label(_kind), do: "зал"

  defp danger_label(nil), do: "неизвестно"
  defp danger_label(level) when level >= 75, do: "смертельно"
  defp danger_label(level) when level >= 50, do: "высокая угроза"
  defp danger_label(level) when level >= 25, do: "опасно"
  defp danger_label(level) when level > 0, do: "низкая угроза"
  defp danger_label(_level), do: "тихо"

  defp encounter_label("boss"), do: "Страж глубины"
  defp encounter_label("hazard"), do: "Аномальная зона"
  defp encounter_label("skirmish"), do: "Стычка"

  defp encounter_label(kind) when is_binary(kind) do
    kind
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp resource_label("rest_supplies"), do: "припасы привала"
  defp resource_label("salvage"), do: "подземный лом"

  defp resource_label(code) when is_binary(code) do
    code
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp loot_label(%{reward_kind: :currency, amount: amount}, _item_name), do: "#{amount} золота"
  defp loot_label(_loot_drop, item_name) when is_binary(item_name), do: item_name
  defp loot_label(_loot_drop, _item_name), do: "добыча"

  defp ensure_expedition(character, dungeon) do
    # Set character location to dungeon entrance
    character
    |> Ecto.Changeset.change(%{current_location_id: dungeon.entrance_location_id})
    |> Repo.update!()

    case Parties.active_expedition_for_character(character.id) do
      %Expedition{} = expedition ->
        # Update expedition location to dungeon entrance if needed
        if expedition.location_id != dungeon.entrance_location_id do
          expedition
          |> Ecto.Changeset.change(%{location_id: dungeon.entrance_location_id})
          |> Repo.update!()
          |> then(&{:ok, &1})
        else
          {:ok, expedition}
        end

      nil ->
        with {:ok, party} <- ensure_party(character),
             {:ok, %{expedition: expedition}} <-
               Parties.start_expedition(party, %{expedition_type: "dungeon"}) do
          {:ok, expedition}
        end
    end
  end

  defp ensure_party(character) do
    case Parties.active_party_for_character(character.id) do
      nil ->
        # Deactivate any stale memberships from disbanded parties
        Repo.update_all(
          from(m in Membership, where: m.character_id == ^character.id and m.status == :active),
          set: [status: :left, left_at: DateTime.utc_now()]
        )

        case Parties.create_party(character) do
          {:ok, %{party: party}} -> {:ok, party}
          err -> err
        end

      party ->
        {:ok, party}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp duel_payload(duel) do
    challenger_name = duel.challenger_character && duel.challenger_character.name
    opponent_name = duel.opponent_character && duel.opponent_character.name
    combat_status = duel.combat && to_string(duel.combat.status)

    %{
      id: duel.id,
      status: to_string(duel.status),
      stake_amount: duel.stake_amount,
      pot_amount: duel.pot_amount,
      challenger_character_id: duel.challenger_character_id,
      opponent_character_id: duel.opponent_character_id,
      challenger_name: challenger_name,
      opponent_name: opponent_name,
      combat_status: combat_status
    }
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_wager}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_wager}

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", safe_to_string(value))
      end)
    end)
  end

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", safe_to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_error(%{__struct__: _} = struct), do: inspect(struct)
  defp format_error(error), do: to_string(error)

  defp safe_to_string(value) do
    to_string(value)
  rescue
    _ -> inspect(value)
  end
end
