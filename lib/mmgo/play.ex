defmodule MMGO.Play do
  @moduledoc """
  Web-facing orchestration for the playable demo surface.

  Domain rules stay in their owning contexts. This module loads and composes the
  state that LiveViews and controllers need to answer what the player can see or
  do right now.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat, as: CombatContext
  alias MMGO.Combat.{Combat, Event, Participant, Resolution}
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Grimoires
  alias MMGO.Grimoires.Grimoire
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Organizations
  alias MMGO.Organizations.{Invitation, Organization, Role}
  alias MMGO.PVP
  alias MMGO.PVP.Duel
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.Spell
  alias MMGO.Survival
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Travel.Journey
  alias MMGO.WorldMap
  alias MMGO.WorldMap.Path
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Realm, Route}

  @local_player_handle "demo-player-1"
  @local_opponent_handle "demo-bot-1"
  @local_player_name "Demo Wizard"
  @local_opponent_name "Shadow Bot"
  @starter_currency 1_000
  @starter_food_units 30
  @starter_ration_code "demo_travel_ration"
  @starter_reagent_code "demo_lumen_dust"
  @starter_reagent_quantity 6
  @starter_spell_name "Ember Spark"
  @demo_duel_stake 100

  def load_demo_state(character_id) when is_binary(character_id) do
    with {:ok, character} <- load_character(character_id) do
      {:ok, state_for_character(character)}
    end
  end

  def load_demo_state(_character_id), do: {:error, :not_found}

  def continue_local_session do
    setup_local_session(reset?: false)
  end

  def start_new_local_session do
    setup_local_session(reset?: true)
  end

  def setup_demo_session do
    continue_local_session()
  end

  def reset_demo_session do
    start_new_local_session()
  end

  defp setup_local_session(opts) do
    reset? = Keyword.fetch!(opts, :reset?)

    with %Realm{} = realm <- Worlds.get_default_realm(),
         %Location{} = starter_location <- starter_location(realm),
         :ok <- maybe_reset_local_account(realm, @local_player_handle, reset?),
         :ok <- maybe_reset_local_account(realm, @local_opponent_handle, reset?),
         {:ok, challenger} <-
           get_or_create_demo_character(realm, @local_player_handle, @local_player_name),
         {:ok, opponent} <-
           get_or_create_demo_character(realm, @local_opponent_handle, @local_opponent_name),
         {:ok, challenger} <- ensure_demo_character_usable(challenger, starter_location),
         {:ok, opponent} <- ensure_demo_character_usable(opponent, starter_location) do
      {:ok, %{challenger: challenger, opponent: opponent}}
    else
      nil -> {:error, :default_realm_not_found}
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  def ensure_demo_character_usable(character_or_id, starter_location \\ nil)

  def ensure_demo_character_usable(character_id, starter_location) when is_binary(character_id) do
    with {:ok, character} <- load_character(character_id) do
      ensure_demo_character_usable(character, starter_location)
    end
  end

  def ensure_demo_character_usable(%Character{} = character, starter_location) do
    starter_location = starter_location || starter_location(Worlds.get_realm!(character.realm_id))

    if is_nil(starter_location) do
      {:error, :starter_location_not_found}
    else
      prepare_demo_character(character, starter_location)
    end
  end

  defp prepare_demo_character(%Character{} = character, %Location{} = starter_location) do
    character =
      character
      |> Character.changeset(%{status: :active})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: starter_location.id})
      |> Repo.update!()

    with :ok <- fund_demo_character(character, @starter_currency),
         {:ok, _food} <- ensure_starter_food(character, @starter_food_units),
         {:ok, _reagent} <- ensure_starter_reagents(character),
         {:ok, _spell} <- ensure_starter_spell(character) do
      {:ok, reload_character(character.id)}
    end
  end

  def current_location_and_routes(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      active_journey = get_active_journey(character)
      current_location = character.current_location

      routes =
        cond do
          is_nil(current_location) -> []
          not is_nil(active_journey) -> []
          true -> Worlds.list_routes_for_location(current_location.id)
        end

      {:ok, %{current_location: current_location, routes: routes, active_journey: active_journey}}
    end
  end

  def get_active_journey(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      character.id
      |> Travel.active_journey()
      |> preload_journey()
    else
      _ -> nil
    end
  end

  def start_journey(character_or_id, destination_slug)
      when is_binary(destination_slug) and destination_slug != "" do
    with {:ok, character} <- normalize_character(character_or_id),
         %{id: location_id} <- character.current_location,
         %Route{} = route <- Worlds.route_from_location_to_slug(location_id, destination_slug),
         travel_opts <- hex_travel_opts(character, destination_slug),
         {:ok, %{journey: journey}} <- Travel.start_journey(character, route, travel_opts) do
      {:ok, %{journey: preload_journey(journey), character: reload_character(character.id)}}
    else
      nil -> {:error, :no_direct_route}
      {:error, reason} -> {:error, reason}
    end
  end

  def start_journey(_character_or_id, _destination_slug), do: {:error, :missing_destination}

  @doc """
  Previews the hex path from `character`'s current location to
  `destination_slug`, returning the hex list, an estimated whole-day travel
  time, and the food that trip would consume.

  Returns `{:error, reason}` when the character isn't placed, there's no
  direct route, or the hex map can't resolve a path between the two slugs
  (missing map file, slugs not on the map, or genuinely unreachable hexes).
  """
  def path_preview(character_or_id, destination_slug)
      when is_binary(destination_slug) and destination_slug != "" do
    with {:ok, character} <- normalize_character(character_or_id),
         %{slug: origin_slug} <- character.current_location,
         %Route{} <-
           Worlds.route_from_location_to_slug(character.current_location.id, destination_slug),
         {:ok, world_map} <- safe_load_world_map(),
         {:ok, %{hexes: hexes, cost: cost}} <-
           Path.path_between_locations(world_map, origin_slug, destination_slug) do
      travel_days = Path.travel_days(world_map, cost)
      plan = Survival.travel_plan(character, travel_days)

      {:ok,
       %{
         hexes: Enum.map(hexes, fn {q, r} -> [q, r] end),
         travel_days: travel_days,
         food_units: plan.required_food_units
       }}
    else
      nil -> {:error, :no_direct_route}
      {:error, reason} -> {:error, reason}
    end
  end

  def path_preview(_character_or_id, _destination_slug), do: {:error, :missing_destination}

  def known_spells_and_duel_state(character_or_id, opponent_id \\ nil) do
    with {:ok, character} <- normalize_character(character_or_id) do
      {:ok,
       %{
         spells: Spells.list_spells_for_character(character.id),
         duel: duel_state(character, opponent_id)
       }}
    end
  end

  @doc """
  Server-authoritative read model for the spellbook screen: the caster, their
  owned spells, and their grimoires (with inscribed entries preloaded).

  Rules stay in `MMGO.Spells`/`MMGO.Grimoires`; this only composes the reads a
  gated `/spellbook` view needs.
  """
  def spellbook_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      {:ok,
       %{
         character: character,
         spells: Spells.list_spells_for_character(character.id),
         grimoires: Grimoires.list_grimoires_for_character(character.id),
         active_grimoire: Grimoires.active_grimoire_for_character(character.id)
       }}
    end
  end

  # Latin-word incantation slots map deterministically onto engine primitives.
  # This is the deterministic safety boundary the GDD requires around any AI
  # narration: the UI never chooses raw effect state, only intent words.
  @school_effect_state %{
    fire: "burning",
    water: "frozen",
    earth: "staggered",
    air: "exposed",
    life: "regenerating",
    death: "silenced",
    chaos: "impact",
    order: "shielded"
  }

  @doc """
  Compiles a composed incantation into a real, persisted spell owned by the
  caster. `attrs` carries the presentation choices (`formula`, `school`, and an
  optional `base_id` from the caster's own library); the resulting effect,
  targeting, and failure profile are derived here so the client can never inject
  arbitrary engine state.
  """
  def compile_spell(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, school} <- normalize_school(attrs["school"] || attrs[:school]),
         {:ok, formula} <- normalize_formula(attrs["formula"] || attrs[:formula]) do
      base = compile_base_spell(character, attrs["base_id"] || attrs[:base_id])
      word_count = formula |> String.split(" ", trim: true) |> length()

      Spells.create_spell(character, %{
        name: compiled_spell_name(school, base),
        formula: formula,
        school: school,
        description: "Круг замкнулся: интенция связана в устойчивую формулу школы #{school}.",
        level_requirement: max(character.level || 1, 1),
        fatigue_cost: 4 + word_count,
        cooldown_turns: 1 + div(word_count, 3),
        targeting: :enemy,
        delivery_form: :single_target,
        tags: ["composed"],
        narrative_tags: [Atom.to_string(school)],
        source_spell_id: base && base.id,
        effects: [
          %{
            applies_to: :target,
            state: Map.fetch!(@school_effect_state, school),
            intensity: 6 + word_count,
            variance: 2,
            duration: 1 + div(word_count, 2)
          }
        ],
        failure_profile: %{
          difficulty: 6 + word_count,
          base_success_rate: max(90 - word_count * 3, 40),
          partial_success_rate: 5
        }
      })
    end
  end

  def compile_spell(_character_or_id, _attrs), do: {:error, :missing_formula}

  @doc "Binds a new empty grimoire owned by the caster."
  def create_grimoire(character_or_id, name) when is_binary(name) do
    with {:ok, character} <- normalize_character(character_or_id) do
      Grimoires.create_grimoire(character, %{name: name, capacity: 7, weight: 2})
    end
  end

  @doc "Activates one of the caster's own grimoires as their loadout."
  def activate_grimoire(character_or_id, grimoire_id) when is_binary(grimoire_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Grimoire{owner_character_id: owner} = grimoire <- safe_get_grimoire(grimoire_id),
         true <- owner == character.id do
      Grimoires.activate_grimoire(character, grimoire)
    else
      false -> {:error, :not_grimoire_owner}
      nil -> {:error, :grimoire_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Inscribes the first known spell that isn't yet in `grimoire_id`. Only the
  owner may write, and the grimoire's own capacity/write-once rules still apply
  in `MMGO.Grimoires`.
  """
  def inscribe_next_spell(character_or_id, grimoire_id) when is_binary(grimoire_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Grimoire{owner_character_id: owner} = grimoire <- safe_get_grimoire(grimoire_id),
         true <- owner == character.id do
      inscribed = MapSet.new(grimoire.entries, & &1.spell_id)

      character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(not MapSet.member?(inscribed, &1.id)))
      |> case do
        nil -> {:error, :no_spell_to_inscribe}
        %Spell{} = spell -> Grimoires.inscribe_spell(grimoire, spell)
      end
    else
      false -> {:error, :not_grimoire_owner}
      nil -> {:error, :grimoire_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_get_grimoire(grimoire_id) do
    Grimoires.get_grimoire!(grimoire_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # ------------------------------------------------------------------
  # Organizations (GDD §17)
  # ------------------------------------------------------------------

  @doc "Read model for the `/orgs` registry: the character, their organizations, and pending invitations."
  def organizations_index(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      {:ok,
       %{
         character: character,
         organizations: Organizations.list_organizations_for_character(character.id),
         invitations: Organizations.pending_invitations_for_character(character.id)
       }}
    end
  end

  @doc "Founds an organization with the session character as the leader."
  def found_organization(character_or_id, kind, name) when is_binary(name) do
    with {:ok, character} <- normalize_character(character_or_id) do
      Organizations.create_organization(character, kind, name)
    end
  end

  @doc """
  Detail read model for one organization, gated on the session character being
  an active member. Returns `{:error, :not_member}` for outsiders.
  """
  def organization_detail(character_or_id, organization_id) when is_binary(organization_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Organization{} = organization <- safe_get_organization(organization_id) do
      case Enum.find(organization.memberships, &(&1.character_id == character.id)) do
        nil ->
          {:error, :not_member}

        membership ->
          {:ok, %{character: character, organization: organization, membership: membership}}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Invites a character (looked up by handle in the inviter's realm) into an organization role."
  def invite_to_organization(character_or_id, organization_id, handle, role_id)
      when is_binary(organization_id) and is_binary(handle) and is_binary(role_id) do
    with {:ok, inviter} <- normalize_character(character_or_id),
         %Organization{} = organization <- safe_get_organization(organization_id),
         %Character{} = invitee <- Accounts.get_character_by_handle(inviter.realm_id, handle),
         %Role{} = role <- Enum.find(organization.roles, &(&1.id == role_id)) do
      Organizations.invite_member(organization, inviter, invitee, role)
    else
      nil -> {:error, :invalid_invite}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Accepts a pending organization invitation owned by the session character."
  def accept_org_invitation(character_or_id, invitation_id) when is_binary(invitation_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Invitation{} = invitation <- safe_get_invitation(invitation_id) do
      Organizations.accept_invitation(invitation, character)
    else
      nil -> {:error, :invitation_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Rejects a pending organization invitation owned by the session character."
  def reject_org_invitation(character_or_id, invitation_id) when is_binary(invitation_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Invitation{} = invitation <- safe_get_invitation(invitation_id) do
      Organizations.reject_invitation(invitation, character)
    else
      nil -> {:error, :invitation_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_get_organization(organization_id) do
    Organizations.get_organization!(organization_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp safe_get_invitation(invitation_id) do
    Repo.get(Invitation, invitation_id)
  end

  defp normalize_school(school) when is_atom(school) and not is_nil(school) do
    if Map.has_key?(@school_effect_state, school),
      do: {:ok, school},
      else: {:error, :invalid_school}
  end

  defp normalize_school(school) when is_binary(school) do
    case Enum.find(Map.keys(@school_effect_state), &(Atom.to_string(&1) == school)) do
      nil -> {:error, :invalid_school}
      atom -> {:ok, atom}
    end
  end

  defp normalize_school(_school), do: {:error, :invalid_school}

  defp normalize_formula(formula) when is_binary(formula) do
    trimmed = String.trim(formula)
    if String.length(trimmed) >= 3, do: {:ok, trimmed}, else: {:error, :formula_too_short}
  end

  defp normalize_formula(_formula), do: {:error, :formula_too_short}

  defp compile_base_spell(_character, nil), do: nil
  defp compile_base_spell(_character, ""), do: nil

  defp compile_base_spell(character, base_id) when is_binary(base_id) do
    character.id
    |> Spells.list_spells_for_character()
    |> Enum.find(&(&1.id == base_id))
  end

  defp compiled_spell_name(school, nil), do: "Formula #{school_word(school)}"
  defp compiled_spell_name(school, base), do: "#{school_word(school)} #{first_word(base.name)}"

  defp school_word(:fire), do: "Ignis"
  defp school_word(:water), do: "Glacies"
  defp school_word(:earth), do: "Terra"
  defp school_word(:air), do: "Ventus"
  defp school_word(:life), do: "Vita"
  defp school_word(:death), do: "Mortis"
  defp school_word(:chaos), do: "Discordia"
  defp school_word(:order), do: "Ordo"

  defp first_word(name) when is_binary(name) do
    name |> String.split(" ", trim: true) |> List.first() || name
  end

  def state_for_character(%Character{} = character) do
    character = Repo.preload(character, :current_location, force: true)
    active_journey = get_active_journey(character)

    routes =
      case current_location_and_routes(character) do
        {:ok, %{routes: routes}} -> routes
        {:error, _reason} -> []
      end

    {:ok, play_summaries} = known_spells_and_duel_state(character)

    %{
      character: character,
      current_location: character.current_location,
      routes: routes,
      active_journey: active_journey,
      food_units: Survival.food_units_available(character),
      spells: play_summaries.spells,
      duel: play_summaries.duel
    }
  end

  @doc """
  Loads the server-authoritative state needed by the in-progress journey
  screen. This is intentionally a presentation read model: travel rules stay
  in `MMGO.Travel` and survival calculations stay in `MMGO.Survival`.
  """
  def travel_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      {:ok,
       %{
         character: state.character,
         current_location: state.current_location,
         journey: state.active_journey,
         journey_progress: journey_progress(state.active_journey),
         food_units: state.food_units,
         carried_weight: Survival.carried_weight(state.character),
         carry_capacity: Survival.carry_capacity(state.character)
       }}
    end
  end

  @doc """
  Loads the server-authoritative inventory read model for a character.

  The active grimoire is returned separately because it is stored in the
  grimoire context, while its weight is already included by `Survival`.
  """
  def inventory_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      items = Inventory.list_inventory_for_character(character.id)

      {:ok,
       %{
         character: character,
         current_location: character.current_location,
         items: items,
         available_quantities: Map.new(items, &{&1.id, Inventory.available_quantity(&1)}),
         active_grimoire: Grimoires.active_grimoire_for_character(character.id),
         food_units: Survival.food_units_available(character),
         carried_weight: Survival.carried_weight(character),
         carry_capacity: Survival.carry_capacity(character)
       }}
    end
  end

  @doc """
  Starts and immediately accepts a duel against the local demo opponent.

  This only orchestrates the existing PvP and combat contexts. The fixed
  local stake keeps the browser demo deterministic and prevents a client from
  choosing its own wager.
  """
  def start_demo_duel(character_or_id, opponent_id) when is_binary(opponent_id) do
    with {:ok, challenger} <- normalize_character(character_or_id),
         {:ok, opponent} <- normalize_character(opponent_id),
         {:ok, duel} <- PVP.challenge_duel(challenger, opponent, @demo_duel_stake),
         {:ok, duel} <- PVP.accept_duel(duel, opponent) do
      duel_combat_state_for(challenger, duel)
    end
  end

  def start_demo_duel(_character_or_id, _opponent_id), do: {:error, :missing_opponent}

  @doc """
  Returns the active duel's combat read model for a character.
  """
  def active_duel_combat_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Duel{} = duel <- PVP.active_duel_for_character(character.id) do
      duel_combat_state_for(character, PVP.get_duel!(duel.id))
    else
      nil -> {:error, :no_active_duel}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Submits a prepared spell for the local player and resolves the current duel
  turn. Neither participant, target side, nor duel id is trusted from the UI.
  """
  def cast_and_resolve_duel_turn(character_or_id, spell_id) when is_binary(spell_id) do
    with {:ok, state} <- active_duel_combat_state(character_or_id),
         %Spell{} = spell <- Enum.find(state.prepared_spells, &(&1.id == spell_id)),
         {:ok, _turn} <-
           CombatContext.submit_action(state.combat, state.participant.id, %{
             action_type: :cast_spell,
             spell_id: spell.id,
             target_side: opposing_side(state.combat, state.participant.side)
           }) do
      resolve_duel_turn(state)
    else
      nil -> {:error, :spell_not_prepared}
      {:error, reason} -> {:error, reason}
    end
  end

  def cast_and_resolve_duel_turn(_character_or_id, _spell_id), do: {:error, :missing_spell}

  @doc """
  Submits a wait action for the local player and resolves the current duel
  turn. This is a real combat action, rather than a frontend-only skip.
  """
  def wait_and_resolve_duel_turn(character_or_id) do
    with {:ok, state} <- active_duel_combat_state(character_or_id),
         {:ok, _turn} <-
           CombatContext.submit_action(state.combat, state.participant.id, %{
             action_type: :wait
           }) do
      resolve_duel_turn(state)
    end
  end

  @doc """
  Cancels the session character's active duel through the PvP context.
  """
  def cancel_active_duel(character_or_id) do
    with {:ok, state} <- active_duel_combat_state(character_or_id) do
      PVP.cancel_duel(state.duel, state.character)
    end
  end

  def list_locations_with_routes(realm_id) when is_binary(realm_id) do
    locations = Worlds.list_locations_for_realm(realm_id)

    routes =
      Repo.all(
        from route in Route,
          where: route.realm_id == ^realm_id,
          preload: [:origin_location, :destination_location]
      )

    Enum.map(locations, fn location ->
      location_routes =
        Enum.filter(routes, fn route ->
          route.origin_location_id == location.id or
            (route.bidirectional and route.destination_location_id == location.id)
        end)

      Map.put(location, :routes, location_routes)
    end)
  end

  def route_destination(%Route{} = route, current_location_id) do
    cond do
      route.origin_location_id == current_location_id -> route.destination_location
      route.destination_location_id == current_location_id -> route.origin_location
      true -> route.destination_location
    end
  end

  # Best-effort hex-path refinement: if the map file is present and both
  # endpoints are placed on it, use the hex-path's travel-day estimate
  # instead of the route's flat `travel_days`. Any failure (missing map,
  # unplaced slugs, unreachable hexes) falls back to the route's own
  # duration untouched.
  defp hex_travel_opts(
         %Character{current_location: %Location{slug: origin_slug}},
         destination_slug
       ) do
    with {:ok, world_map} <- safe_load_world_map(),
         {:ok, %{cost: cost}} <-
           Path.path_between_locations(world_map, origin_slug, destination_slug) do
      [travel_days_override: Path.travel_days(world_map, cost)]
    else
      _ -> []
    end
  end

  defp hex_travel_opts(_character, _destination_slug), do: []

  defp safe_load_world_map do
    {:ok, WorldMap.load()}
  rescue
    _exception -> {:error, :world_map_unavailable}
  end

  defp load_character(character_id) do
    {:ok, reload_character(character_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp normalize_character(%Character{} = character) do
    {:ok, Repo.preload(character, :current_location, force: true)}
  end

  defp normalize_character(character_id) when is_binary(character_id),
    do: load_character(character_id)

  defp normalize_character(_character), do: {:error, :not_found}

  defp reload_character(character_id) do
    character_id
    |> Accounts.get_character!()
    |> Repo.preload(:current_location)
  end

  defp get_or_create_demo_character(realm, handle, name) do
    account =
      case Repo.get_by(Account, handle: handle) do
        %Account{} = existing -> existing
        nil -> create_demo_account!(handle, name)
      end

    character =
      case Repo.get_by(Character, account_id: account.id, realm_id: realm.id) do
        %Character{} = existing -> existing
        nil -> create_demo_character!(account, realm, name)
      end

    {:ok, character}
  end

  defp create_demo_account!(handle, name) do
    case Repo.insert(
           Account.registration_changeset(%Account{}, %{display_name: name, handle: handle})
         ) do
      {:ok, account} -> account
      {:error, _changeset} -> Repo.get_by!(Account, handle: handle)
    end
  end

  defp create_demo_character!(account, realm, name) do
    case Repo.insert(
           %Character{account_id: account.id, realm_id: realm.id}
           |> Character.changeset(%{
             name: name,
             status: :active,
             metadata: %{"source" => "local_play_session"}
           })
         ) do
      {:ok, character} -> character
      {:error, _changeset} -> Repo.get_by!(Character, account_id: account.id, realm_id: realm.id)
    end
  end

  defp maybe_reset_local_account(_realm, _handle, false), do: :ok

  defp maybe_reset_local_account(%Realm{} = realm, handle, true) do
    case Accounts.get_character_by_handle(realm.id, handle) do
      %Character{} = character ->
        reset_local_character(realm, character)

      nil ->
        :ok
    end
  end

  defp reset_local_character(%Realm{} = realm, %Character{} = character) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(journey in Journey,
        where: journey.character_id == ^character.id and journey.status == :active
      ),
      set: [status: :cancelled, completed_at: now, updated_at: now]
    )

    cancel_local_duels(character)

    Repo.delete_all(from(item in InventoryItem, where: item.character_id == ^character.id))

    Repo.delete_all(
      from(grimoire in Grimoire, where: grimoire.owner_character_id == ^character.id)
    )

    Repo.delete_all(from(spell in Spell, where: spell.creator_character_id == ^character.id))

    :ok = zero_out_character_balance(realm, character)

    character
    |> Character.changeset(%{
      status: :new,
      level: 1,
      xp: 0,
      metadata: %{"source" => "local_play_session"}
    })
    |> Repo.update!()

    :ok
  end

  defp cancel_local_duels(%Character{} = character) do
    Duel
    |> where(
      [duel],
      (duel.challenger_character_id == ^character.id or
         duel.opponent_character_id == ^character.id) and
        duel.status in [:pending, :active]
    )
    |> Repo.all()
    |> Enum.each(fn duel ->
      cond do
        duel.status == :pending and duel.opponent_character_id == character.id ->
          PVP.reject_duel(duel, character)

        true ->
          PVP.cancel_duel(duel, character)
      end
    end)
  end

  defp zero_out_character_balance(%Realm{} = realm, %Character{} = character) do
    with {:ok, account} <- Economy.ensure_character_account(character),
         %EconomyAccount{} = treasury_account <- Economy.treasury_account_for_realm(realm.id) do
      if account.current_balance > 0 do
        {:ok, _result} =
          Economy.transfer(account, treasury_account, account.current_balance, %{
            "reason" => "local_play_session_reset"
          })
      end

      :ok
    else
      nil -> :ok
      {:error, _changeset} -> :ok
    end
  end

  defp fund_demo_character(%Character{} = character, target_balance) do
    {:ok, account} = Economy.ensure_character_account(character)

    shortfall = target_balance - account.current_balance

    if shortfall > 0 do
      realm = Worlds.get_realm!(character.realm_id)

      case Economy.grant_from_treasury(realm, character, shortfall, %{
             "reason" => "demo_character_funding"
           }) do
        {:ok, _result} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      :ok
    end
  end

  defp ensure_starter_food(character, target_food_units) do
    available_food_units = Survival.food_units_available(character)

    if available_food_units >= target_food_units do
      {:ok, :already_stocked}
    else
      ration_template = get_or_create_starter_ration!()
      missing_units = target_food_units - available_food_units
      quantity = ceil_div(missing_units, ration_template.nutrition_units)

      Inventory.grant_item(character, ration_template, %{quantity: quantity})
    end
  end

  defp get_or_create_starter_ration! do
    get_or_create_item_template!(%{
      code: @starter_ration_code,
      name: "Demo Travel Ration",
      item_type: :food,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 1,
      actions: [],
      metadata: %{"source" => "local_play_session"}
    })
  end

  defp ensure_starter_reagents(character) do
    Inventory.grant_item(character, get_or_create_starter_reagent!(), %{
      quantity: @starter_reagent_quantity,
      metadata: %{"source" => "starter_kit"}
    })
  end

  defp get_or_create_starter_reagent! do
    get_or_create_item_template!(%{
      code: @starter_reagent_code,
      name: "Lumen Dust",
      item_type: :ingredient,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 0,
      tags: ["starter", "spell_ingredient"],
      actions: [],
      metadata: %{"source" => "local_play_session"}
    })
  end

  defp get_or_create_item_template!(attrs) do
    case Repo.get_by(ItemTemplate, code: attrs.code) do
      %ItemTemplate{} = template ->
        template

      nil ->
        case Inventory.create_item_template(attrs) do
          {:ok, template} -> template
          {:error, _changeset} -> Repo.get_by!(ItemTemplate, code: attrs.code)
        end
    end
  end

  defp ensure_starter_spell(character) do
    spell =
      case Repo.get_by(Spell, creator_character_id: character.id, name: @starter_spell_name) do
        %Spell{} = spell ->
          spell

        nil ->
          create_starter_spell!(character)
      end

    ensure_starter_grimoire(character, spell)
    {:ok, spell}
  end

  defp create_starter_spell!(character) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: @starter_spell_name,
        formula: "Ignis Minima",
        school: :fire,
        description: "A compact starter flame for testing the first combat loop.",
        level_requirement: 1,
        fatigue_cost: 2,
        cooldown_turns: 1,
        targeting: :enemy,
        delivery_form: :single_target,
        tags: ["starter"],
        narrative_tags: ["spark"],
        effects: [
          %{applies_to: :target, state: "burning", intensity: 8, variance: 1, duration: 1}
        ],
        failure_profile: %{difficulty: 8, base_success_rate: 92, partial_success_rate: 5}
      })

    spell
  end

  defp ensure_starter_grimoire(character, spell) do
    case Grimoires.active_grimoire_for_character(character.id) do
      %Grimoire{} = grimoire ->
        grimoire

      nil ->
        {:ok, grimoire} =
          Grimoires.create_grimoire(character, %{
            name: "Starter Grimoire",
            capacity: 5,
            weight: 1,
            metadata: %{"source" => "starter_kit"}
          })

        {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

        {:ok, %{activate_grimoire: active_grimoire}} =
          Grimoires.activate_grimoire(character, grimoire)

        active_grimoire
    end
  end

  defp starter_location(nil), do: nil

  defp starter_location(%Realm{} = realm) do
    cond do
      not is_nil(realm.entry_location_id) -> Worlds.get_location!(realm.entry_location_id)
      location = Worlds.get_location_by_slug(realm.id, "capital-city") -> location
      true -> nil
    end
  end

  defp duel_state(%Character{} = character, opponent_id) do
    active_duel = character.id |> PVP.active_duel_for_character() |> preload_duel()

    %{
      active_duel: active_duel,
      pending_duels: Enum.map(PVP.pending_duels_for_character(character.id), &preload_duel/1),
      opponent: load_optional_character(opponent_id)
    }
  end

  defp load_optional_character(nil), do: nil

  defp load_optional_character(character_id) when is_binary(character_id) do
    case load_character(character_id) do
      {:ok, character} -> character
      {:error, _reason} -> nil
    end
  end

  defp preload_journey(nil), do: nil
  defp preload_journey(journey), do: Repo.preload(journey, [:from_location, :to_location])

  defp duel_combat_state_for(%Character{} = _character, %Duel{combat_id: nil}),
    do: {:error, :duel_has_no_combat}

  defp duel_combat_state_for(%Character{} = character, %Duel{} = duel) do
    duel = PVP.get_duel!(duel.id)
    combat = CombatContext.get_combat!(duel.combat_id)

    case Enum.find(combat.participants, &(&1.character_id == character.id)) do
      %Participant{} = participant ->
        prepared_spell_ids = prepared_spell_ids(participant)

        {:ok,
         %{
           character: character,
           duel: duel,
           combat: combat,
           participant: participant,
           prepared_spells:
             character.id
             |> Spells.list_spells_for_character()
             |> Enum.filter(&MapSet.member?(prepared_spell_ids, &1.id)),
           sides: combat_side_summaries(combat),
           events: combat_events(combat.id)
         }}

      nil ->
        {:error, :not_a_duel_participant}
    end
  end

  defp resolve_duel_turn(state) do
    with {:ok, resolved_combat} <- CombatContext.resolve_turn(state.combat),
         {:ok, _result} <- Resolution.finalize(resolved_combat) do
      refreshed_duel = PVP.get_duel!(state.duel.id)
      duel_combat_state_for(state.character, refreshed_duel)
    end
  end

  defp prepared_spell_ids(%Participant{grimoire: nil}), do: MapSet.new()

  defp prepared_spell_ids(%Participant{grimoire: grimoire}) do
    grimoire.entries
    |> Enum.map(& &1.spell_id)
    |> MapSet.new()
  end

  defp opposing_side(%Combat{} = combat, own_side) do
    combat.participants
    |> Enum.map(& &1.side)
    |> Enum.uniq()
    |> Enum.find(&(&1 != own_side))
  end

  defp combat_side_summaries(%Combat{} = combat) do
    combat.sides
    |> Enum.map(fn {side_id, values} ->
      %{
        id: side_id,
        label: Map.get(values, "label") || Map.get(values, :label) || String.capitalize(side_id),
        shared_hp: Map.get(values, "shared_hp") || Map.get(values, :shared_hp) || 0,
        max_shared_hp: Map.get(values, "max_shared_hp") || Map.get(values, :max_shared_hp) || 0,
        participants:
          combat.participants
          |> Enum.filter(&(&1.side == side_id))
          |> Enum.map(& &1.display_name)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp combat_events(combat_id) do
    Repo.all(
      from event in Event,
        where: event.combat_id == ^combat_id,
        order_by: [asc: event.turn_number, asc: event.sequence],
        limit: 12
    )
  end

  defp journey_progress(nil), do: nil

  defp journey_progress(%Journey{} = journey) do
    duration_seconds = max(DateTime.diff(journey.arrival_at, journey.started_at, :second), 1)

    elapsed_seconds =
      DateTime.utc_now()
      |> DateTime.diff(journey.started_at, :second)
      |> max(0)
      |> min(duration_seconds)

    elapsed_game_days =
      elapsed_seconds
      |> Clock.real_seconds_to_game_days()
      |> floor()
      |> min(journey.travel_days)

    %{
      elapsed_game_days: elapsed_game_days,
      remaining_game_days: max(journey.travel_days - elapsed_game_days, 0),
      percent: floor(elapsed_seconds / duration_seconds * 100),
      remaining_seconds: max(duration_seconds - elapsed_seconds, 0)
    }
  end

  defp preload_duel(nil), do: nil
  defp preload_duel(duel), do: PVP.get_duel!(duel.id)

  defp ceil_div(value, divisor) when divisor > 0 do
    div(value + divisor - 1, divisor)
  end
end
