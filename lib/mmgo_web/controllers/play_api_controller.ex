defmodule MMGOWeb.PlayApiController do
  use MMGOWeb, :controller

  import Ecto.Query

  alias MMGO.{Accounts, Combat, Dungeons, Grimoires, Parties, PVP, Repo, Worlds}
  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Engine, Turn}
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Dungeons.{Encounter, Link, Node, NodeState, Run}
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
          nil -> nil
          %Run{} = run ->
            run = Repo.preload(run, [:dungeon, :current_node])
            %{run_id: run.id, dungeon_id: run.dungeon_id, dungeon_name: run.dungeon && run.dungeon.name, current_node_name: run.current_node && run.current_node.name, steps_taken: run.steps_taken, status: to_string(run.status)}
        end

      active_party = Parties.active_party_for_character(character.id)

      party_payload =
        case active_party do
          nil -> nil
          party ->
            party = Repo.preload(party, [memberships: :character])
            members = Enum.filter(party.memberships, &(&1.status == :active))
            %{
              id: party.id,
              name: party.name,
              members: Enum.map(members, &%{id: &1.character_id, name: &1.character && &1.character.name, role: to_string(&1.role)})
            }
        end

      realm = Worlds.get_default_realm()
      dungeons = if realm, do: Dungeons.list_dungeons_for_realm(realm.id), else: []
      dungeon_list = Enum.map(dungeons, &%{id: &1.id, name: &1.name, slug: &1.slug})

      spell_count =
        case Grimoires.active_grimoire_for_character(character.id) do
          nil -> 0
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

  def create_duel(conn, %{"opponent_id" => opponent_id, "wager_amount" => wager_str}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {wager, ""} <- Integer.parse(wager_str),
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
    combat = Combat.get_combat!(combat_id) |> Repo.preload(participants: [:character, :actor_template, grimoire: :entries])

    # Run up to 5 turns or until resolution
    result = run_combat_turns(combat, 5)
    {:ok, result}
  end

  defp run_combat_turns(combat, 0) do
    # Close combat as draw
    combat
    |> CombatSchema.changeset(%{status: :finished, metadata: Map.put(combat.metadata || %{}, "resolution", "draw")})
    |> Repo.update!()
    %{winner: "draw", turns: combat.turn_number - 1}
  end

  defp run_combat_turns(combat, remaining) do
    turn = Repo.get_by!(Turn, combat_id: combat.id, number: combat.turn_number)
    participants = combat.participants

    # Preload spells for grimoire entries
    spell_ids = Enum.flat_map(participants, fn p ->
      (p.grimoire && p.grimoire.entries || [])
      |> Enum.map(& &1.spell_id)
      |> Enum.reject(&is_nil/1)
    end)
    spells_map = if spell_ids != [] do
      from(s in MMGO.Spells.Spell, where: s.id in ^spell_ids)
      |> Repo.all()
      |> Map.new(fn s -> {s.id, s} end)
    else
      %{}
    end

    # Generate simple actions for each participant
    now = DateTime.utc_now()
    actions = Enum.map(participants, fn p ->
      spell_entry = Enum.find(p.grimoire && p.grimoire.entries || [], fn e -> e.spell_id end)
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
      winner = case final_combat.metadata do
        %{"winner_id" => id} ->
          Enum.find(participants, &(&1.id == id || &1.character_id == id))
          |> then(fn p -> p && (p.character && p.character.name || "NPC") end)
        _ -> "draw"
      end
      %{winner: winner || "draw", turns: combat.turn_number, status: to_string(final_combat.status)}
    else
      run_combat_turns(final_combat, remaining - 1)
    end
  end

  # ── Spells ───────────────────────────────────────────────────────────────

  def list_spells(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn) do
      spells =
        case Grimoires.active_grimoire_for_character(character.id) do
          nil -> []
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
          # Auto-inscribe in active grimoire or create one
          grimoire = case Grimoires.active_grimoire_for_character(character.id) do
            nil -> {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: "#{character.name}'s Grimoire", status: :active}); grimoire
            g -> g
          end
          {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

          json(conn, %{ok: true, spell: %{
            id: spell.id,
            name: spell.name,
            school: to_string(spell.school),
            targeting: to_string(spell.targeting),
            delivery_form: to_string(spell.delivery_form),
            effects: Enum.map(spell.effects || [], fn e -> %{state: e.state, intensity: e.intensity} end)
          }})

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

  # ── Dungeons ─────────────────────────────────────────────────────────────

  def enter_dungeon(conn, %{"dungeon_id" => dungeon_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         dungeon when not is_nil(dungeon) <- Dungeons.get_dungeon!(dungeon_id),
         {:ok, expedition} <- ensure_expedition(character, dungeon),
         {:ok, %{run: run}} <- Dungeons.enter_dungeon(expedition, dungeon) do
      run = Repo.preload(run, [:current_node, :dungeon])
      json(conn, %{ok: true, run: %{
        run_id: run.id,
        dungeon_name: dungeon.name,
        current_node_name: run.current_node.name,
        current_node_kind: to_string(run.current_node.kind),
        steps_taken: run.steps_taken
      }})
    else
      nil -> json(conn, %{ok: false, error: "dungeon not found"})
      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(changeset)})
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(reason)})
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
            {:ok, _} -> json(conn, %{ok: true})
            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(reason)})
          end
      end
    end
  end

  def dungeon_state(conn, _params) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id) do

      run = Repo.preload(run, [:dungeon, :current_node])
      encounters = Dungeons.list_encounters_for_run(run.id)
        |> Enum.map(&%{id: &1.id, kind: &1.encounter_kind, status: to_string(&1.status)})

      json(conn, %{ok: true, state: build_dungeon_state(run, encounters)})
    else
      nil -> json(conn, %{ok: false, error: "no active dungeon run"})
      _ -> json(conn, %{ok: false, error: "could not load dungeon state"})
    end
  end

  defp build_dungeon_state(run, encounters) do
    dungeon_id = run.dungeon_id

    # All nodes for this dungeon (across all floors)
    all_nodes = from(n in Node,
      join: f in assoc(n, :floor),
      where: f.dungeon_id == ^dungeon_id,
      select: n
    ) |> Repo.all()

    # All links for this dungeon
    all_links = from(l in Link,
      where: l.dungeon_id == ^dungeon_id
    ) |> Repo.all()

    # Which nodes have been visited in this run
    visited_node_ids = from(ns in NodeState,
      where: ns.run_id == ^run.id,
      select: ns.node_id
    ) |> Repo.all() |> MapSet.new()

    # Reachable = connected to current node via any link (bidirectional aware)
    current_id = run.current_node_id
    reachable_ids = all_links
      |> Enum.flat_map(fn l ->
        cond do
          l.from_node_id == current_id -> [l.to_node_id]
          l.bidirectional && l.to_node_id == current_id -> [l.from_node_id]
          true -> []
        end
      end)
      |> MapSet.new()

    nodes = all_nodes |> Enum.map(fn n ->
      state = cond do
        n.id == current_id -> "here"
        MapSet.member?(visited_node_ids, n.id) -> "visited"
        MapSet.member?(reachable_ids, n.id) -> "reachable"
        true -> "hidden"
      end
      %{id: n.id, name: n.name, kind: to_string(n.kind), x: n.x, y: n.y, state: state}
    end)

    corridors = all_links |> Enum.map(fn l ->
      %{from_id: l.from_node_id, to_id: l.to_node_id, bidirectional: l.bidirectional}
    end)

    %{
      run_id: run.id,
      dungeon_name: run.dungeon && run.dungeon.name,
      current_node_id: current_id,
      current_node: %{
        id: current_id,
        name: run.current_node && run.current_node.name,
        kind: to_string(run.current_node && run.current_node.kind)
      },
      steps_taken: run.steps_taken,
      status: to_string(run.status),
      nodes: nodes,
      corridors: corridors,
      encounters: encounters
    }
  end

  def move_in_dungeon(conn, %{"to_node_id" => node_id}) do
    with {:ok, _conn, character} <- PlaySession.fetch_current_character(conn),
         %Expedition{} = expedition <- Parties.active_expedition_for_character(character.id),
         %Run{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{run: updated_run}} <- Dungeons.move_run(run, node_id) do

      updated_run = Repo.preload(updated_run, [:current_node, :dungeon])
      encounters = Dungeons.list_encounters_for_run(updated_run.id)
        |> Enum.map(&%{id: &1.id, kind: &1.encounter_kind, status: to_string(&1.status)})

      json(conn, %{ok: true, state: build_dungeon_state(updated_run, encounters)})
    else
      nil -> json(conn, %{ok: false, error: "no active dungeon run"})
      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(changeset)})
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(reason)})
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
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(changeset)})
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: format_error(reason)})
      false ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "encounter does not belong to your active run"})
    end
  end

  def fight_encounter(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "encounter_id required"})
  end

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
             {:ok, %{expedition: expedition}} <- Parties.start_expedition(party, %{expedition_type: "dungeon"}) do
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
      challenger_name: challenger_name,
      opponent_name: opponent_name,
      combat_status: combat_status
    }
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
