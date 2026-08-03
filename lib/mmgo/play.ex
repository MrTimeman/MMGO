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
  alias MMGO.Academy
  alias MMGO.Academia
  alias MMGO.Alchemy
  alias MMGO.Atmosphere
  alias MMGO.Bases
  alias MMGO.Bases.{Base, StorageItem}
  alias MMGO.BlackMarket
  alias MMGO.Clubs
  alias MMGO.Clubs.Club
  alias MMGO.Clubs.Event, as: ClubEvent
  alias MMGO.Clubs.Invitation, as: ClubInvitation
  alias MMGO.Clubs.Membership, as: ClubMembership
  alias MMGO.Combat, as: CombatContext
  alias MMGO.Combat.{Action, Combat, Event, Participant, Resolution, Turn, TurnArtifacts}
  alias MMGO.Dungeons
  alias MMGO.Dungeons.{Dungeon, Encounter, LootDrop, Run}
  alias MMGO.Dungeons.ResourceCache, as: DungeonResourceCache
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Events, as: WorldEvents
  alias MMGO.Events.Instance, as: EventInstance
  alias MMGO.Federation
  alias MMGO.Grimoires
  alias MMGO.Grimoires.Grimoire
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Market
  alias MMGO.NPCShops
  alias MMGO.Notifications
  alias MMGO.Organizations
  alias MMGO.Organizations.{Invitation, Organization, Role}
  alias MMGO.Overworld
  alias MMGO.Overworld.Encounter, as: OverworldEncounter
  alias MMGO.Parties
  alias MMGO.Parties.{Expedition, Party}
  alias MMGO.PVP
  alias MMGO.PVP.Duel
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Scavenging.{Attempt, ResourceCache}
  alias MMGO.SecretCult
  alias MMGO.Spells
  alias MMGO.Spells.{Compiler, Spell}
  alias MMGO.Survival
  alias MMGO.Crafting
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Travel.Journey
  alias MMGO.WorldMap
  alias MMGO.WorldMap.Path
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Realm, Route}

  @local_player_handle "demo-player-1"
  @local_opponent_handle "demo-bot-1"
  @local_player_name "Учебный маг"
  @local_opponent_name "Теневой страж"
  @starter_currency 1_000
  @starter_food_units 30
  @starter_ration_code "demo_travel_ration"
  @starter_reagent_code "demo_lumen_dust"
  @starter_reagent_quantity 6
  @starter_build_material_code "construction_material"
  @starter_build_material_quantity 8
  @starter_spell_name "Искра углей"
  @demo_duel_stake 100
  @overworld_actions ~w(greet trade attack avoid)
  @organization_permissions ~w(invite_members manage_roles manage_treasury grant_fast_travel)
  @activity_actions %{
    "academy" => %{type: :navigate, to: "/academy/bulletin-board"},
    "spells" => %{type: :navigate, to: "/spellbook"},
    "routes" => %{type: :navigate, to: "/map"},
    "npc_shops" => %{type: :navigate, to: "/trade"},
    "party_hub" => %{type: :navigate, to: "/party"},
    "base" => %{type: :navigate, to: "/base"},
    "party" => %{type: :navigate, to: "/party"},
    "dungeon" => %{type: :navigate, to: "/dungeon"},
    "base_storage" => %{type: :navigate, to: "/base"},
    "craft" => %{type: :navigate, to: "/craft"},
    "alchemy" => %{type: :navigate, to: "/alchemy"},
    "rest" => %{type: :navigate, to: "/base"},
    "scavenge" => %{type: :notice, message: "Осмотрите доступные ресурсы ниже."},
    "road" => %{type: :notice, message: "Следите за путниками поблизости."}
  }

  @doc """
  Loads the browser-facing state for a character whose ownership has already
  been established by the caller's scope boundary.
  """
  def load_state(character_id) when is_binary(character_id) do
    with {:ok, character} <- load_character(character_id) do
      {:ok, state_for_character(character)}
    end
  end

  def load_state(_character_id), do: {:error, :not_found}

  @doc false
  def load_demo_state(character_id), do: load_state(character_id)

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

  @doc """
  Activates and stocks a newly provisioned player character once.

  Unlike the local demo helper, an active character is returned untouched on
  future logins. This keeps a real player's location, inventory, and balance
  out of the demo reset path.
  """
  def ensure_character_usable(character_or_id)

  def ensure_character_usable(character_id) when is_binary(character_id) do
    with {:ok, character} <- load_character(character_id) do
      ensure_character_usable(character)
    end
  end

  def ensure_character_usable(%Character{status: :active} = character) do
    {:ok, reload_character(character.id)}
  end

  def ensure_character_usable(%Character{status: :new} = character) do
    case starter_location(Worlds.get_realm!(character.realm_id)) do
      %Location{} = location -> prepare_new_character(character, location)
      nil -> {:error, :starter_location_not_found}
    end
  end

  def ensure_character_usable(%Character{}), do: {:error, :character_not_playable}
  def ensure_character_usable(_character), do: {:error, :not_found}

  defp prepare_demo_character(%Character{} = character, %Location{} = starter_location) do
    character =
      character
      |> Character.changeset(%{status: :active})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: starter_location.id})
      |> Repo.update!()

    with :ok <- fund_character(character, @starter_currency, "demo_character_funding"),
         {:ok, _food} <- ensure_starter_food(character, @starter_food_units),
         {:ok, _reagent} <- ensure_starter_reagents(character),
         {:ok, _materials} <- ensure_starter_build_materials(character),
         {:ok, _spell} <- ensure_starter_spell(character) do
      {:ok, reload_character(character.id)}
    end
  end

  defp prepare_new_character(%Character{} = character, %Location{} = starter_location) do
    character =
      character
      |> Character.changeset(%{status: :active, metadata: %{"source" => "telegram_mini_app"}})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: starter_location.id})
      |> Repo.update!()

    with :ok <- fund_character(character, @starter_currency, "starter_character_funding"),
         {:ok, _food} <- ensure_starter_food(character, @starter_food_units),
         {:ok, _reagent} <- ensure_starter_reagents(character),
         {:ok, _materials} <- ensure_starter_build_materials(character),
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
  Loads the scoped, same-location duel lobby. Candidate IDs are only display
  hints; every command below re-finds the opponent from the caller's current
  stationary location before handing control to `MMGO.PVP`.
  """
  def duel_lobby_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)
      character = state.character

      cond do
        not is_nil(state.active_journey) ->
          {:error, :travelling}

        is_nil(state.current_location) ->
          {:error, :location_not_found}

        true ->
          {:ok, account} = Economy.ensure_character_account(character)

          pending_duels =
            character.id
            |> PVP.pending_duels_for_character()
            |> Enum.map(&preload_duel/1)

          {:ok,
           %{
             character: character,
             location: state.current_location,
             balance: account.current_balance,
             active_duel: state.duel.active_duel,
             opponents: nearby_stationary_characters(character, state.current_location),
             incoming: Enum.filter(pending_duels, &(&1.opponent_character_id == character.id)),
             outgoing: Enum.filter(pending_duels, &(&1.challenger_character_id == character.id))
           }}
      end
    end
  end

  @doc """
  Creates a pending wagered duel against a real nearby player. The target and
  stake are validated again by `MMGO.PVP`; no browser-provided actor, realm,
  or protected-location authority is used.
  """
  def challenge_duel(character_or_id, opponent_id, stake_amount)
      when is_binary(opponent_id) and is_integer(stake_amount) do
    with {:ok, character} <- normalize_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_duel_lobby_available(state),
         %Character{} = opponent <-
           find_nearby_character(state.character, state.current_location, opponent_id),
         {:ok, duel} <- PVP.challenge_duel(state.character, opponent, stake_amount) do
      {:ok, %{duel: preload_duel(duel)}}
    else
      nil -> {:error, :opponent_not_found}
      {:error, _reason} = error -> error
    end
  end

  def challenge_duel(_character_or_id, _opponent_id, _stake_amount),
    do: {:error, :invalid_duel_challenge}

  def accept_duel(character_or_id, duel_id) when is_binary(duel_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Duel{} = duel <- owned_pending_duel(character, duel_id),
         true <- duel.opponent_character_id == character.id || {:error, :not_challenged_player},
         {:ok, accepted_duel} <- PVP.accept_duel(duel, character) do
      {:ok, %{duel: accepted_duel}}
    else
      nil -> {:error, :duel_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_challenged_player}
    end
  end

  def accept_duel(_character_or_id, _duel_id), do: {:error, :duel_not_found}

  def reject_duel(character_or_id, duel_id) when is_binary(duel_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Duel{} = duel <- owned_pending_duel(character, duel_id),
         true <- duel.opponent_character_id == character.id || {:error, :not_challenged_player},
         {:ok, rejected_duel} <- PVP.reject_duel(duel, character) do
      {:ok, %{duel: rejected_duel}}
    else
      nil -> {:error, :duel_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_challenged_player}
    end
  end

  def reject_duel(_character_or_id, _duel_id), do: {:error, :duel_not_found}

  def cancel_pending_duel(character_or_id, duel_id) when is_binary(duel_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Duel{} = duel <- owned_pending_duel(character, duel_id),
         true <- duel.challenger_character_id == character.id || {:error, :not_challenger},
         {:ok, cancelled_duel} <- PVP.cancel_duel(duel, character) do
      {:ok, %{duel: cancelled_duel}}
    else
      nil -> {:error, :duel_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_challenger}
    end
  end

  def cancel_pending_duel(_character_or_id, _duel_id), do: {:error, :duel_not_found}

  @doc """
  Server-authoritative read model for the spellbook screen: the caster, their
  owned spells, and their grimoires (with inscribed entries preloaded).

  Reading the book is always available to an authenticated character. The
  returned composition capability describes whether mutating the book is
  currently allowed; every write is independently rechecked by `spellbook_actor/1`.
  """
  def spellbook_state(character_or_id) do
    with {:ok, character} <- reload_spellbook_character(character_or_id) do
      spells = Spells.list_spells_for_character(character.id)
      grimoires = Grimoires.list_grimoires_for_character(character.id)

      {composition_location, composition_lock_reason} =
        case spellbook_location(character) do
          {:ok, location} -> {location, nil}
          {:error, reason} -> {nil, reason}
        end

      {:ok,
       %{
         character: character,
         spells: spells,
         grimoires: grimoires,
         active_grimoire: Enum.find(grimoires, &(&1.status == :active)),
         writable_grimoires: Enum.filter(grimoires, &(&1.status == :draft)),
         permitted_schools: permitted_spellbook_schools(character, spells),
         composition_location: composition_location,
         composition_available?: not is_nil(composition_location),
         composition_lock_reason: composition_lock_reason
       }}
    end
  end

  # The browser submits only a bounded school and a 1–6 word intent. Compiler
  # validation owns the AI boundary and the engine owns all executable effects.
  @spellbook_schools ~w(fire water earth air life death chaos order)

  @doc """
  Compiles a composed incantation into a real, persisted spell owned by the
  caster. Composition is only available while stationary at the Tower or an
  active owned base, and every selection is rechecked against the caster's
  durable library before the compiler can create an AI request.
  """
  def compile_spell(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character, _location} <- spellbook_actor(character_or_id),
         spells <- Spells.list_spells_for_character(character.id),
         {:ok, school} <- permitted_spellbook_school(character, spells, attrs),
         attrs <- normalize_spellbook_attrs(attrs, school),
         {:ok, %{spell: spell}} <- Compiler.compile_and_store(character, attrs) do
      {:ok, spell}
    end
  end

  def compile_spell(_character_or_id, _attrs), do: {:error, :missing_formula}

  @doc "Activates one of the caster's own grimoires as their loadout."
  def activate_grimoire(character_or_id, grimoire_id) when is_binary(grimoire_id) do
    with {:ok, character, _location} <- spellbook_actor(character_or_id),
         {:ok, grimoire} <- owned_grimoire(character, grimoire_id) do
      Grimoires.activate_grimoire(character, grimoire)
    end
  end

  def activate_grimoire(_character_or_id, _grimoire_id), do: {:error, :grimoire_not_found}

  @doc """
  Inscribes the explicitly selected owned spell into an owned writable
  grimoire. The domain context retains capacity, duplicate, and write-once
  checks under its transaction lock.
  """
  def inscribe_spell(character_or_id, grimoire_id, spell_id)
      when is_binary(grimoire_id) and is_binary(spell_id) do
    with {:ok, character, _location} <- spellbook_actor(character_or_id),
         {:ok, grimoire} <- owned_grimoire(character, grimoire_id),
         {:ok, spell} <- owned_spell(character, spell_id) do
      Grimoires.inscribe_spell(grimoire, spell)
    end
  end

  def inscribe_spell(_character_or_id, _grimoire_id, _spell_id),
    do: {:error, :missing_inscription}

  # ------------------------------------------------------------------
  # Organizations (GDD §17)
  # ------------------------------------------------------------------

  @doc "Read model for the `/orgs` registry: the character, their organizations, and pending invitations."
  def organizations_index(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      organizations = Organizations.list_organizations_for_character(character.id)

      public_organizations =
        character.realm_id
        |> Organizations.list_active_organizations_for_realm()
        |> SecretCult.visible_organizations(character)

      {:ok,
       %{
         character: character,
         organizations: organizations,
         invitations: Organizations.pending_invitations_for_character(character.id),
         public_organizations: public_organizations,
         member_organization_ids: Enum.map(organizations, & &1.id),
         open_organization_ids:
           public_organizations
           |> Enum.filter(&Organizations.membership_state(&1).open?)
           |> Enum.map(& &1.id)
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
          permissions = organization_permissions(membership)
          treasury_account = Organizations.treasury_account(organization)
          leadership = organization_leadership_state(organization, character, permissions)
          membership_policy = Organizations.membership_state(organization)
          succession = Organizations.succession_state(organization)
          treasury_ownership = organization_treasury_ownership_state(organization)

          treasury_policy =
            organization_treasury_policy_state(organization, character, membership, permissions)

          diplomacy = organization_diplomacy_state(organization, character)
          fast_travel_tolls = organization_fast_travel_toll_state(organization, permissions)

          {:ok,
           %{
             character: character,
             organization: organization,
             membership: membership,
             can_invite?: "invite_members" in permissions,
             can_manage_roles?: "manage_roles" in permissions,
             can_manage_treasury?: "manage_treasury" in permissions,
             treasury_account: treasury_account,
             treasury_balance:
               if(treasury_account, do: treasury_account.current_balance, else: 0),
             treasury_recent_entry:
               if(treasury_account,
                 do: Economy.list_ledger_entries_for_account(treasury_account.id) |> List.first(),
                 else: nil
               ),
             treasury_ownership: treasury_ownership,
             treasury_policy: treasury_policy,
             leadership: leadership,
             membership_policy: membership_policy,
             succession: succession,
             diplomacy: diplomacy,
             fast_travel_tolls: fast_travel_tolls,
             fast_travel_destinations:
               organization_fast_travel_destinations(character, organization, membership)
           }}
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

  @doc "Creates a bounded organization role through the scoped member's real permission."
  def add_organization_role(character_or_id, organization_id, attrs)
      when is_binary(organization_id) and is_map(attrs) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, role_attrs} <- normalize_organization_role_attrs(attrs),
         {:ok, _role} <-
           Organizations.add_role(state.organization, state.character, role_attrs) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def add_organization_role(_character_or_id, _organization_id, _attrs),
    do: {:error, :invalid_organization_role}

  @doc "Changes the scoped manager's membership-admission block for one organization."
  def configure_organization_membership(character_or_id, organization_id, admission)
      when is_binary(organization_id) and admission in ["invitation_only", "open"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _organization} <-
           Organizations.configure_membership_admission(
             state.organization,
             state.character,
             admission
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_membership(_character_or_id, _organization_id, _admission),
    do: {:error, :organization_membership_unavailable}

  @doc "Changes the scoped manager's leader-exit succession block for one organization."
  def configure_organization_succession(character_or_id, organization_id, on_leader_exit)
      when is_binary(organization_id) and on_leader_exit in ["highest_rank_member", "vacant"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _organization} <-
           Organizations.configure_leader_exit_succession(
             state.organization,
             state.character,
             on_leader_exit
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_succession(_character_or_id, _organization_id, _on_leader_exit),
    do: {:error, :organization_membership_unavailable}

  @doc "Joins a public organization only when the realm-local admission rule allows it."
  def join_open_organization(character_or_id, organization_id) when is_binary(organization_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Organization{} = organization <- safe_get_organization(organization_id),
         {:ok, _membership} <- Organizations.join_open_organization(organization, character) do
      organizations_index(character)
    else
      nil -> {:error, :organization_not_found}
      {:error, _reason} = error -> error
    end
  end

  def join_open_organization(_character_or_id, _organization_id),
    do: {:error, :organization_membership_unavailable}

  @doc "Moves the scoped member's own balance into their organization's real treasury."
  def fund_organization_treasury(character_or_id, organization_id, amount)
      when is_binary(organization_id) and is_integer(amount) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _result} <-
           Organizations.deposit_to_treasury(state.organization, state.character, amount) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def fund_organization_treasury(_character_or_id, _organization_id, _amount),
    do: {:error, :organization_treasury_unavailable}

  @doc "Pays a same-realm character from an authorized organization treasury."
  def spend_organization_treasury(character_or_id, organization_id, recipient_handle, amount)
      when is_binary(organization_id) and is_binary(recipient_handle) and is_integer(amount) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Character{} = recipient <-
           Accounts.get_character_by_handle(
             state.character.realm_id,
             String.trim(recipient_handle)
           ),
         {:ok, _result} <-
           Organizations.withdraw_from_treasury(
             state.organization,
             state.character,
             recipient,
             amount
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_treasury_recipient_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def spend_organization_treasury(_character_or_id, _organization_id, _recipient_handle, _amount),
    do: {:error, :organization_treasury_unavailable}

  @doc "Assigns a scoped active member's treasury-share percentage through the organization's real permission."
  def assign_organization_treasury_share(
        character_or_id,
        organization_id,
        member_character_id,
        share_bps
      )
      when is_binary(organization_id) and is_binary(member_character_id) and is_integer(share_bps) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Character{} = member <-
           organization_member_character(state.organization, member_character_id),
         {:ok, _organization} <-
           Organizations.assign_treasury_share(
             state.organization,
             state.character,
             member,
             share_bps
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_share_member_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def assign_organization_treasury_share(
        _character_or_id,
        _organization_id,
        _member_character_id,
        _share_bps
      ),
      do: {:error, :organization_treasury_unavailable}

  @doc "Splits a declared treasury profit to the organization's durable member share holders."
  def distribute_organization_treasury_dividend(character_or_id, organization_id, gross_amount)
      when is_binary(organization_id) and is_integer(gross_amount) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _result} <-
           Organizations.distribute_treasury_dividend(
             state.organization,
             state.character,
             gross_amount
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def distribute_organization_treasury_dividend(
        _character_or_id,
        _organization_id,
        _gross_amount
      ),
      do: {:error, :organization_treasury_unavailable}

  @doc "Updates whether treasury payouts use role authority or a member referendum."
  def configure_organization_treasury_decision(character_or_id, organization_id, decision)
      when is_binary(organization_id) and decision in ["role_permission", "member_referendum"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _organization} <-
           Organizations.configure_treasury_decision(
             state.organization,
             state.character,
             decision
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_treasury_decision(_character_or_id, _organization_id, _decision),
    do: {:error, :organization_treasury_unavailable}

  @doc "Sets the direct-payout ceiling for one real organization role."
  def configure_organization_treasury_role_limit(
        character_or_id,
        organization_id,
        role_id,
        direct_payout_limit
      )
      when is_binary(organization_id) and is_binary(role_id) and
             (is_nil(direct_payout_limit) or
                (is_integer(direct_payout_limit) and direct_payout_limit >= 0)) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Role{} = role <- Enum.find(state.organization.roles, &(&1.id == role_id)),
         {:ok, _role} <-
           Organizations.configure_treasury_role_payout_limit(
             state.organization,
             state.character,
             role,
             direct_payout_limit
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_treasury_role_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_treasury_role_limit(
        _character_or_id,
        _organization_id,
        _role_id,
        _direct_payout_limit
      ),
      do: {:error, :organization_treasury_unavailable}

  @doc "Opens a scoped manager's durable member referendum for one same-realm payout."
  def propose_organization_treasury_withdrawal(
        character_or_id,
        organization_id,
        recipient_handle,
        amount
      )
      when is_binary(organization_id) and is_binary(recipient_handle) and is_integer(amount) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Character{} = recipient <-
           Accounts.get_character_by_handle(
             state.character.realm_id,
             String.trim(recipient_handle)
           ),
         {:ok, _result} <-
           Organizations.propose_treasury_withdrawal(
             state.organization,
             state.character,
             recipient,
             amount
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_treasury_recipient_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def propose_organization_treasury_withdrawal(
        _character_or_id,
        _organization_id,
        _recipient_handle,
        _amount
      ),
      do: {:error, :organization_treasury_unavailable}

  @doc "Records the scoped member's immutable vote on an open treasury referendum."
  def vote_for_organization_treasury(character_or_id, organization_id, proposal_id, vote)
      when is_binary(organization_id) and is_binary(proposal_id) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, vote} <- normalize_organization_vote(vote),
         {:ok, _result} <-
           Organizations.cast_treasury_vote(
             state.organization,
             state.character,
             proposal_id,
             vote
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def vote_for_organization_treasury(_character_or_id, _organization_id, _proposal_id, _vote),
    do: {:error, :organization_treasury_unavailable}

  @doc "Sends a scoped manager's alliance or rivalry request to another organization in the same realm."
  def propose_organization_diplomacy(
        character_or_id,
        organization_id,
        target_organization_id,
        kind
      )
      when is_binary(organization_id) and is_binary(target_organization_id) and
             kind in ["alliance", "rivalry", "war"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Organization{} = target_organization <-
           Enum.find(
             Organizations.list_active_organizations_for_realm(state.organization.realm_id),
             &(&1.id == target_organization_id)
           ),
         {:ok, _result} <-
           Organizations.propose_diplomacy(
             state.organization,
             state.character,
             target_organization,
             kind
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_diplomacy_target_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def propose_organization_diplomacy(
        _character_or_id,
        _organization_id,
        _target_organization_id,
        _kind
      ),
      do: {:error, :organization_diplomacy_unavailable}

  @doc "Lets a scoped target manager accept or reject one durable incoming diplomacy request."
  def respond_to_organization_diplomacy(character_or_id, organization_id, proposal_id, decision)
      when is_binary(organization_id) and is_binary(proposal_id) and
             decision in ["accept", "reject"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, decision} <- normalize_organization_diplomacy_decision(decision),
         {:ok, _result} <-
           Organizations.respond_to_diplomacy_request(
             state.organization,
             state.character,
             proposal_id,
             decision
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def respond_to_organization_diplomacy(
        _character_or_id,
        _organization_id,
        _proposal_id,
        _decision
      ),
      do: {:error, :organization_diplomacy_unavailable}

  @doc "Updates an organization constitution's real leadership-selection block."
  def configure_organization_leadership(character_or_id, organization_id, selection)
      when is_binary(organization_id) and
             selection in ["founder_appointment", "member_election", "share_weighted_election"] do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, _organization} <-
           Organizations.configure_leadership_selection(
             state.organization,
             state.character,
             selection
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_leadership(_character_or_id, _organization_id, _selection),
    do: {:error, :organization_leadership_unavailable}

  @doc "Lets the active organization founder appoint a member under a founder-appointment constitution."
  def appoint_organization_leader(character_or_id, organization_id, candidate_character_id)
      when is_binary(organization_id) and is_binary(candidate_character_id) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Character{} = candidate <-
           organization_member_character(state.organization, candidate_character_id),
         {:ok, _organization} <-
           Organizations.appoint_leader(state.organization, state.character, candidate) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_leadership_candidate_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def appoint_organization_leader(_character_or_id, _organization_id, _candidate_character_id),
    do: {:error, :organization_leadership_unavailable}

  @doc "Opens a member-election proposal for a real active organization member."
  def nominate_organization_leader(character_or_id, organization_id, candidate_character_id)
      when is_binary(organization_id) and is_binary(candidate_character_id) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Character{} = candidate <-
           organization_member_character(state.organization, candidate_character_id),
         {:ok, _election} <-
           Organizations.open_leadership_election(
             state.organization,
             state.character,
             candidate
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_leadership_candidate_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def nominate_organization_leader(_character_or_id, _organization_id, _candidate_character_id),
    do: {:error, :organization_leadership_unavailable}

  @doc "Records the scoped member's one immutable vote on an open leadership election."
  def vote_for_organization_leader(character_or_id, organization_id, proposal_id, vote)
      when is_binary(organization_id) and is_binary(proposal_id) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         {:ok, vote} <- normalize_organization_vote(vote),
         {:ok, _election} <-
           Organizations.cast_leadership_vote(
             state.organization,
             state.character,
             proposal_id,
             vote
           ) do
      organization_detail(state.character, state.organization.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def vote_for_organization_leader(_character_or_id, _organization_id, _proposal_id, _vote),
    do: {:error, :organization_leadership_unavailable}

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

  @doc "Leaves one organization only when the scoped character has an active membership."
  def leave_organization(character_or_id, organization_id) when is_binary(organization_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Organization{} = organization <- safe_get_organization(organization_id) do
      Organizations.leave_organization(organization, character)
    else
      nil -> {:error, :organization_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def leave_organization(_character_or_id, _organization_id),
    do: {:error, :organization_not_found}

  def use_organization_fast_travel(character_or_id, organization_id, destination_location_id)
      when is_binary(organization_id) and is_binary(destination_location_id) do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Location{} = destination <- safe_get_location(destination_location_id),
         true <-
           destination.realm_id == state.character.realm_id || {:error, :destination_not_found},
         {:ok, updated_character} <-
           Organizations.use_fast_travel(state.character, state.organization, destination) do
      {:ok, updated_character}
    else
      nil -> {:error, :destination_not_found}
      {:error, _reason} = error -> error
    end
  end

  def use_organization_fast_travel(_character_or_id, _organization_id, _destination_location_id),
    do: {:error, :destination_not_found}

  @doc "Configures one organization-linked fast-travel fee through the scoped treasury authority."
  def configure_organization_fast_travel_toll(
        character_or_id,
        organization_id,
        origin_location_id,
        destination_location_id,
        amount
      )
      when is_binary(organization_id) and is_binary(origin_location_id) and
             is_binary(destination_location_id) and is_integer(amount) and amount >= 0 do
    with {:ok, state} <- organization_detail(character_or_id, organization_id),
         %Location{} = origin <-
           organization_fast_travel_location(state.organization, origin_location_id),
         %Location{} = destination <-
           organization_fast_travel_location(state.organization, destination_location_id),
         {:ok, _organization} <-
           Organizations.configure_fast_travel_toll(
             state.organization,
             state.character,
             origin,
             destination,
             amount
           ) do
      organization_detail(state.character, state.organization.id)
    else
      nil -> {:error, :organization_fast_travel_toll_route_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def configure_organization_fast_travel_toll(
        _character_or_id,
        _organization_id,
        _origin_location_id,
        _destination_location_id,
        _amount
      ),
      do: {:error, :organization_fast_travel_toll_route_unavailable}

  defp safe_get_organization(organization_id) do
    Organizations.get_organization!(organization_id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  defp safe_get_invitation(invitation_id) do
    Repo.get(Invitation, invitation_id)
  end

  defp safe_get_location(location_id) when is_binary(location_id),
    do: Repo.get(Location, location_id)

  defp safe_get_location(_location_id), do: nil

  defp organization_fast_travel_destinations(character, organization, membership) do
    can_travel? =
      organization.fast_travel_enabled and
        "grant_fast_travel" in membership.role.permissions and
        character.current_location_id in organization.linked_location_ids

    if can_travel? do
      organization.linked_location_ids
      |> Enum.reject(&(&1 == character.current_location_id))
      |> Enum.map(&safe_get_location/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(&1.realm_id == character.realm_id))
      |> Enum.flat_map(fn destination ->
        case Organizations.fast_travel_toll_quote(
               organization,
               character.current_location,
               destination
             ) do
          {:ok, quote} ->
            [
              %{
                id: destination.id,
                name: destination.name,
                fee: quote.fee,
                organization_amount: quote.organization_amount,
                tax_amount: quote.tax_amount,
                tax_rate_bps: quote.tax_rate_bps
              }
            ]

          {:error, _reason} ->
            []
        end
      end)
    else
      []
    end
  end

  defp organization_fast_travel_toll_state(organization, permissions) do
    toll_state = Organizations.fast_travel_toll_state(organization)

    locations =
      organization.linked_location_ids
      |> Enum.map(&safe_get_location/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(&1.realm_id == organization.realm_id))
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&%{id: &1.id, name: &1.name})

    locations_by_id = Map.new(locations, &{&1.id, &1})

    configured_routes =
      toll_state.route_fees
      |> Enum.flat_map(fn {origin_location_id, destinations} ->
        Enum.flat_map(destinations, fn {destination_location_id, fee} ->
          case {Map.get(locations_by_id, origin_location_id),
                Map.get(locations_by_id, destination_location_id)} do
            {%{name: origin_name}, %{name: destination_name}}
            when is_integer(fee) and fee > 0 ->
              [
                %{
                  origin_location_id: origin_location_id,
                  destination_location_id: destination_location_id,
                  origin_name: origin_name,
                  destination_name: destination_name,
                  fee: fee,
                  tax_amount: div(fee * toll_state.tax_rate_bps, 10_000)
                }
              ]

            _other ->
              []
          end
        end)
      end)
      |> Enum.sort_by(&{&1.origin_name, &1.destination_name})

    %{
      can_configure?: "manage_treasury" in permissions,
      tax_rate_bps: toll_state.tax_rate_bps,
      locations: locations,
      configured_routes: configured_routes
    }
  end

  defp organization_fast_travel_location(%Organization{} = organization, location_id)
       when is_binary(location_id) do
    if location_id in organization.linked_location_ids do
      case safe_get_location(location_id) do
        %Location{realm_id: realm_id} = location when realm_id == organization.realm_id ->
          location

        _other ->
          nil
      end
    end
  end

  defp organization_fast_travel_location(_organization, _location_id), do: nil

  defp organization_permissions(%{role: %{permissions: permissions}}) when is_list(permissions),
    do: permissions

  defp organization_permissions(_membership), do: []

  defp organization_treasury_ownership_state(organization) do
    ownership = Organizations.treasury_ownership_state(organization)

    Map.put(
      ownership,
      :members,
      Enum.map(organization.memberships, fn membership ->
        %{
          character_id: membership.character_id,
          character: membership.character,
          share_bps: Map.get(ownership.member_share_bps, membership.character_id, 0)
        }
      end)
    )
  end

  defp organization_treasury_policy_state(organization, character, membership, permissions) do
    %{decision: decision, open_referendum: open_referendum} =
      Organizations.treasury_policy_state(organization)

    %{
      decision: decision,
      can_configure?: "manage_roles" in permissions,
      actor_direct_payout_limit: Organizations.treasury_role_payout_limit(membership.role),
      role_limits:
        Enum.map(organization.roles, fn role ->
          %{
            id: role.id,
            title: role.title,
            rank: role.rank,
            direct_payout_limit: Organizations.treasury_role_payout_limit(role)
          }
        end),
      open_referendum:
        treasury_referendum_presentation(open_referendum, organization.realm_id, character.id)
    }
  end

  defp treasury_referendum_presentation(nil, _realm_id, _character_id), do: nil

  defp treasury_referendum_presentation(proposal, realm_id, character_id) when is_map(proposal) do
    voter_character_ids =
      proposal
      |> Map.get("voter_character_ids", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    votes = leadership_proposal_votes(proposal)
    voter_count = length(voter_character_ids)

    %{
      id: Map.get(proposal, "id"),
      recipient_name: treasury_referendum_recipient_name(proposal, realm_id),
      amount: treasury_referendum_amount(proposal),
      votes_cast: map_size(votes),
      voter_count: voter_count,
      votes_needed: div(voter_count, 2) + 1,
      approve_votes: organization_vote_count(votes, "approve"),
      reject_votes: organization_vote_count(votes, "reject"),
      can_vote?: character_id in voter_character_ids and not Map.has_key?(votes, character_id)
    }
  end

  defp treasury_referendum_presentation(_proposal, _realm_id, _character_id), do: nil

  defp treasury_referendum_recipient_name(proposal, realm_id) do
    case Map.get(proposal, "recipient_character_id") do
      recipient_character_id when is_binary(recipient_character_id) ->
        case Repo.get(Character, recipient_character_id) do
          %Character{realm_id: ^realm_id, name: name} -> name
          _other -> "Неизвестный получатель"
        end

      _other ->
        "Неизвестный получатель"
    end
  end

  defp treasury_referendum_amount(proposal) do
    case Map.get(proposal, "amount") do
      amount when is_integer(amount) and amount > 0 -> amount
      _other -> 0
    end
  end

  defp organization_diplomacy_state(organization, character) do
    diplomacy = Organizations.diplomacy_state(organization)

    organizations_by_id =
      organization.realm_id
      |> Organizations.list_active_organizations_for_realm()
      |> SecretCult.visible_organizations(character)
      |> Map.new(&{&1.id, &1})

    relationship_ids = Enum.map(diplomacy.relationships, &Map.get(&1, "organization_id"))

    %{
      relationships:
        Enum.map(diplomacy.relationships, fn relationship ->
          organization_id = Map.get(relationship, "organization_id")

          %{
            organization_id: organization_id,
            organization_name:
              case Map.get(organizations_by_id, organization_id) do
                %Organization{name: name} -> name
                nil -> "Неизвестная организация"
              end,
            kind: Map.get(relationship, "kind")
          }
        end),
      incoming_requests:
        Enum.map(diplomacy.incoming_requests, fn request ->
          source_organization_id = Map.get(request, "source_organization_id")

          %{
            id: Map.get(request, "id"),
            relationship_kind: Map.get(request, "relationship_kind"),
            source_organization_id: source_organization_id,
            source_organization_name:
              case Map.get(organizations_by_id, source_organization_id) do
                %Organization{name: name} -> name
                nil -> "Неизвестная организация"
              end
          }
        end),
      available_targets:
        organizations_by_id
        |> Map.values()
        |> Enum.reject(&(&1.id == organization.id or &1.id in relationship_ids))
        |> Enum.sort_by(& &1.name)
    }
  end

  defp organization_leadership_state(organization, character, permissions) do
    %{
      selection: selection,
      leader_character_id: leader_character_id,
      open_election: open_election
    } =
      Organizations.leadership_state(organization)

    leader =
      Enum.find(organization.memberships, &(&1.character_id == leader_character_id))

    candidate_memberships =
      Enum.reject(organization.memberships, &(&1.character_id == leader_character_id))

    %{
      selection: selection,
      leader: leader,
      candidate_memberships: candidate_memberships,
      can_configure?: "manage_roles" in permissions,
      can_appoint?:
        selection == "founder_appointment" and organization.founder_character_id == character.id and
          candidate_memberships != [] and is_nil(open_election),
      can_nominate?:
        selection in ["member_election", "share_weighted_election"] and is_nil(open_election),
      open_election:
        leadership_election_presentation(open_election, organization.memberships, character.id)
    }
  end

  defp leadership_election_presentation(nil, _memberships, _character_id), do: nil

  defp leadership_election_presentation(proposal, memberships, character_id)
       when is_map(proposal) do
    voter_character_ids =
      proposal
      |> Map.get("voter_character_ids", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    votes = leadership_proposal_votes(proposal)
    voter_weights = leadership_proposal_voter_weights(proposal)
    weighted? = map_size(voter_weights) > 0

    {total_vote_weight, required_vote_weight, approve_weight, reject_weight} =
      if weighted? do
        total_vote_weight = voter_weights |> Map.values() |> Enum.sum()

        {
          total_vote_weight,
          div(total_vote_weight, 2) + 1,
          leadership_vote_weight(votes, voter_weights, "approve"),
          leadership_vote_weight(votes, voter_weights, "reject")
        }
      else
        {nil, nil, nil, nil}
      end

    %{
      id: Map.get(proposal, "id"),
      candidate:
        Enum.find(memberships, &(&1.character_id == Map.get(proposal, "candidate_character_id"))),
      votes_cast: map_size(votes),
      votes_needed: div(length(voter_character_ids), 2) + 1,
      voter_count: length(voter_character_ids),
      weighted?: weighted?,
      total_vote_weight: total_vote_weight,
      required_vote_weight: required_vote_weight,
      approve_weight: approve_weight,
      reject_weight: reject_weight,
      actor_vote_weight: Map.get(voter_weights, character_id, 1),
      can_vote?: character_id in voter_character_ids and not Map.has_key?(votes, character_id)
    }
  end

  defp leadership_election_presentation(_proposal, _memberships, _character_id), do: nil

  defp leadership_proposal_votes(%{"votes" => votes}) when is_map(votes), do: votes
  defp leadership_proposal_votes(_proposal), do: %{}

  defp organization_vote_count(votes, choice) when is_map(votes) and is_binary(choice) do
    votes
    |> Map.values()
    |> Enum.count(&(Map.get(&1, "choice") == choice))
  end

  defp organization_vote_count(_votes, _choice), do: 0

  defp leadership_proposal_voter_weights(%{"voter_weights_bps" => weights})
       when is_map(weights) do
    weights
    |> Enum.reduce(%{}, fn
      {character_id, weight}, normalized
      when is_binary(character_id) and is_integer(weight) and weight > 0 ->
        Map.put(normalized, character_id, weight)

      _entry, normalized ->
        normalized
    end)
  end

  defp leadership_proposal_voter_weights(_proposal), do: %{}

  defp leadership_vote_weight(votes, voter_weights, choice) do
    Enum.reduce(votes, 0, fn {character_id, vote}, total ->
      if Map.get(vote, "choice") == choice do
        total + Map.get(voter_weights, character_id, 0)
      else
        total
      end
    end)
  end

  defp organization_member_character(organization, character_id) do
    case Enum.find(organization.memberships, &(&1.character_id == character_id)) do
      %{character: %Character{} = character} -> character
      _other -> nil
    end
  end

  defp club_member_character(%Club{} = club, character_id) when is_binary(character_id) do
    case Enum.find(club.memberships, &(&1.character_id == character_id)) do
      %{character: %Character{} = character} -> character
      _other -> nil
    end
  end

  defp club_member_character(_club, _character_id), do: nil

  defp normalize_organization_vote("approve"), do: {:ok, :approve}
  defp normalize_organization_vote("reject"), do: {:ok, :reject}
  defp normalize_organization_vote(:approve), do: {:ok, :approve}
  defp normalize_organization_vote(:reject), do: {:ok, :reject}
  defp normalize_organization_vote(_vote), do: {:error, :invalid_organization_vote}

  defp normalize_club_vote("approve"), do: {:ok, :approve}
  defp normalize_club_vote("reject"), do: {:ok, :reject}
  defp normalize_club_vote(:approve), do: {:ok, :approve}
  defp normalize_club_vote(:reject), do: {:ok, :reject}
  defp normalize_club_vote(_vote), do: {:error, :invalid_club_vote}

  defp normalize_organization_diplomacy_decision("accept"), do: {:ok, :accept}
  defp normalize_organization_diplomacy_decision("reject"), do: {:ok, :reject}

  defp normalize_organization_diplomacy_decision(_decision),
    do: {:error, :invalid_diplomacy_decision}

  defp normalize_organization_role_attrs(attrs) do
    with {:ok, title} <- normalize_organization_role_title(Map.get(attrs, "title")),
         {:ok, rank} <- normalize_organization_role_rank(Map.get(attrs, "rank")) do
      {:ok,
       %{
         code: "member-" <> String.replace(Ecto.UUID.generate(), "-", ""),
         title: title,
         rank: rank,
         permissions: normalize_organization_role_permissions(Map.get(attrs, "permissions"))
       }}
    end
  end

  defp normalize_organization_role_title(title) when is_binary(title) do
    title = String.trim(title)

    if String.length(title) in 2..120 do
      {:ok, title}
    else
      {:error, :invalid_organization_role}
    end
  end

  defp normalize_organization_role_title(_title), do: {:error, :invalid_organization_role}

  defp normalize_organization_role_rank(rank) when is_integer(rank) and rank in 0..99,
    do: {:ok, rank}

  defp normalize_organization_role_rank(rank) when is_binary(rank) do
    case Integer.parse(rank) do
      {parsed_rank, ""} when parsed_rank in 0..99 -> {:ok, parsed_rank}
      _other -> {:error, :invalid_organization_role}
    end
  end

  defp normalize_organization_role_rank(_rank), do: {:error, :invalid_organization_role}

  defp normalize_organization_role_permissions(permissions) when is_list(permissions) do
    permissions
    |> Enum.filter(&(&1 in @organization_permissions))
    |> Enum.uniq()
  end

  defp normalize_organization_role_permissions(_permissions), do: []

  defp spellbook_actor(character_or_id) do
    with {:ok, character} <- reload_spellbook_character(character_or_id),
         {:ok, composition_location} <- spellbook_location(character) do
      {:ok, character, composition_location}
    end
  end

  # A LiveView may hold an older struct while the player has begun a journey in
  # another tab. Reload before every spellbook action so location and journey
  # eligibility are never inherited from socket state.
  defp reload_spellbook_character(%Character{id: character_id}) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_spellbook_character(character_id) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_spellbook_character(_character_or_id), do: {:error, :not_found}

  defp spellbook_location(%Character{} = character) do
    current_location = character.current_location

    cond do
      not is_nil(Travel.active_journey(character.id)) ->
        {:error, :travelling}

      is_nil(current_location) ->
        {:error, :spellbook_location}

      current_location.kind == :tower ->
        {:ok, spellbook_location_summary(current_location)}

      not is_nil(Bases.active_base_at_location(character.id, current_location.id)) ->
        {:ok, spellbook_location_summary(current_location)}

      true ->
        {:error, :spellbook_location}
    end
  end

  defp spellbook_location_summary(location) do
    %{id: location.id, name: location.name, kind: location.kind}
  end

  defp permitted_spellbook_schools(%Character{} = character, spells) do
    specialization_schools =
      case Academy.active_specialization(character.id) do
        %{track: :wizardry, primary_school: primary_school, secondary_school: secondary_school} ->
          [primary_school, secondary_school]
          |> Enum.filter(&is_atom/1)
          |> Enum.map(&Atom.to_string/1)

        _other ->
          spells
          |> Enum.map(& &1.school)
          |> Enum.filter(&is_atom/1)
          |> Enum.map(&Atom.to_string/1)
      end

    (specialization_schools ++ Academy.valedictorian_bonus_schools(character))
    |> Enum.uniq()
  end

  defp permitted_spellbook_school(%Character{} = character, spells, attrs) do
    with {:ok, school} <- normalize_spellbook_school(attrs["school"] || attrs[:school]),
         true <- school in permitted_spellbook_schools(character, spells) do
      {:ok, school}
    else
      false -> {:error, :school_not_permitted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_spellbook_school(school) when is_binary(school) do
    if school in @spellbook_schools, do: {:ok, school}, else: {:error, :invalid_school}
  end

  defp normalize_spellbook_school(school) when is_atom(school) do
    school
    |> Atom.to_string()
    |> normalize_spellbook_school()
  end

  defp normalize_spellbook_school(_school), do: {:error, :invalid_school}

  defp normalize_spellbook_attrs(attrs, school) do
    attrs = Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    attrs
    |> Map.put("school", school)
    |> Map.put("base_spell_id", attrs["base_spell_id"] || attrs["base_id"])
  end

  defp owned_grimoire(%Character{} = character, grimoire_id) do
    grimoire =
      Repo.one(
        from grimoire in Grimoire,
          where:
            grimoire.id == ^grimoire_id and grimoire.owner_character_id == ^character.id and
              grimoire.realm_id == ^character.realm_id,
          preload: [entries: :spell]
      )

    case grimoire do
      %Grimoire{} -> {:ok, grimoire}
      nil -> {:error, :grimoire_not_found}
    end
  end

  defp owned_spell(%Character{} = character, spell_id) do
    case Spells.get_owned_spell(character, spell_id) do
      %Spell{} = spell -> {:ok, spell}
      nil -> {:error, :spell_not_found}
    end
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
  Composes the server-authoritative world state for one already-authorized
  player. Browser callers receive no actor, realm, or location authority from
  parameters; each value is derived from this character.
  """
  def world_hub_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)
      character = state.character
      realm = Worlds.get_realm!(character.realm_id)
      current_location = state.current_location

      organizations =
        realm.id
        |> Organizations.list_active_organizations_for_realm()
        |> SecretCult.visible_organizations(character)

      visible_organization_ids = MapSet.new(Enum.map(organizations, & &1.id))

      nearby_characters =
        if is_nil(state.active_journey) and current_location do
          Accounts.list_active_characters_at_location(realm.id, current_location.id,
            exclude_character_id: character.id
          )
        else
          []
        end

      survival = Survival.summary(character)

      {:ok,
       %{
         realm: realm,
         locations: list_locations_with_routes(realm.id),
         organizations: organizations,
         organization_economic_activity:
           realm.id
           |> Economy.public_organization_activity_for_realm()
           |> Map.take(MapSet.to_list(visible_organization_ids)),
         world_time: Clock.world_time(),
         character: character,
         current_location: current_location,
         routes: state.routes,
         active_journey: state.active_journey,
         food_units: state.food_units,
         survival: survival,
         atmosphere:
           Atmosphere.cue_for(current_location,
             major_event: if(state.active_journey, do: :journey)
           ),
         notifications: Notifications.list_notifications(character.id),
         nearby_characters: nearby_characters,
         open_encounters: Overworld.list_open_encounters_for_character(character.id)
       }}
    end
  end

  @doc """
  Returns the scoped character's own durable notification history. Notification
  IDs from the browser are never accepted here, so one player cannot inspect
  another player's delivery state or payload.
  """
  def notifications_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      {:ok,
       %{
         character: character,
         notifications: Notifications.list_notifications(character.id)
       }}
    end
  end

  @doc "Returns the scoped federation directory and this character's migration state."
  def realm_directory_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      current_realm = Worlds.get_realm!(character.realm_id)
      migrations = Federation.list_migrations_for_account(character.account_id)
      remote_realms = Federation.list_discoverable_realms(current_realm.id)

      active_migration =
        Enum.find(migrations, fn migration ->
          migration.origin_character_id == character.id and migration.status == :active
        end)

      currency_balance =
        case Repo.get_by(EconomyAccount, character_id: character.id, owner_type: :character) do
          %EconomyAccount{current_balance: balance} -> balance
          nil -> 0
        end

      {:ok,
       %{
         character: character,
         current_realm: current_realm,
         remote_realms: remote_realms,
         remote_migration_ready_ids:
           remote_realms
           |> Enum.filter(&Federation.remote_migration_ready?/1)
           |> Enum.map(& &1.id),
         migrations: migrations,
         active_migration: active_migration,
         currency_balance: currency_balance,
         can_start_remote_migration?: character.status == :active and is_nil(active_migration)
       }}
    end
  end

  @doc "Starts a server-authoritative remote migration selected from the directory."
  def start_scoped_remote_migration(character_or_id, remote_realm_id, currency_amount)
      when is_binary(remote_realm_id) and is_integer(currency_amount) do
    with {:ok, character} <- normalize_character(character_or_id),
         current_realm <- Worlds.get_realm!(character.realm_id),
         remote_realm when not is_nil(remote_realm) <-
           Enum.find(
             Federation.list_discoverable_realms(current_realm.id),
             &(&1.id == remote_realm_id)
           ),
         {:ok, quote} <-
           Federation.quote_remote_exchange(current_realm, remote_realm, currency_amount),
         {:ok, result} <- Federation.start_migration(character, remote_realm, currency_amount) do
      {:ok,
       %{
         migration: result.migration,
         quote: quote,
         remote_response: Map.get(result, :remote_response),
         remote_import_pending?: Federation.remote_import_status(result.migration) != :accepted
       }}
    else
      nil -> {:error, :remote_realm_not_found}
      {:error, _reason} = error -> error
    end
  end

  def start_scoped_remote_migration(_character_or_id, _remote_realm_id, _currency_amount),
    do: {:error, :remote_realm_not_found}

  @doc "Retries only the current scoped character's pending remote handoff."
  def retry_scoped_remote_migration(character_or_id, migration_id) when is_binary(migration_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         migration when not is_nil(migration) <-
           Enum.find(Federation.list_migrations_for_account(character.account_id), fn migration ->
             migration.id == migration_id and migration.origin_character_id == character.id and
               migration.mode == :remote and migration.status == :active
           end),
         {:ok, result} <- Federation.retry_remote_migration_import(migration.id) do
      {:ok, result}
    else
      nil -> {:error, :realm_migration_not_found}
      {:error, _reason} = error -> error
    end
  end

  def retry_scoped_remote_migration(_character_or_id, _migration_id),
    do: {:error, :realm_migration_not_found}

  @doc """
  Returns the scoped player's current text-adventure hub. Arrival events and
  their options are owned by the existing Events context; this facade keeps
  event/location authorization out of the LiveView.
  """
  def activity_hub_state(character_or_id) do
    with {:ok, character} <- reload_activity_character(character_or_id) do
      state = state_for_character(character)

      cond do
        not is_nil(state.active_journey) ->
          {:error, :travelling}

        is_nil(state.current_location) ->
          {:error, :location_not_found}

        true ->
          realm = Worlds.get_realm!(state.character.realm_id)
          event = WorldEvents.current_event(state.character)

          nearby_characters =
            nearby_stationary_characters(state.character, state.current_location)

          open_encounters = open_location_encounters(state.character, state.current_location)

          {:ok,
           %{
             realm: realm,
             character: state.character,
             location: state.current_location,
             world_time: Clock.world_time(),
             event: event,
             options: sort_event_options(event.template.options || []),
             nearby_characters: nearby_characters,
             open_encounters: open_encounters,
             scavenging: scavenging_hub_state(state.character, state.current_location),
             secret_cult: SecretCult.discovery_state(state.character),
             survival: Survival.summary(state.character),
             atmosphere: Atmosphere.cue_for(state.current_location),
             overworld: %{
               attack_available?: overworld_attack_available?(realm, state.current_location)
             }
           }}
      end
    end
  end

  @doc """
  Resolves one trusted current-location option and returns only a server-owned
  navigation or notice action.
  """
  def resolve_activity_option(character_or_id, event_id, option_code)
      when is_binary(event_id) and is_binary(option_code) do
    with {:ok, character} <- normalize_character(character_or_id),
         %EventInstance{} = event <- WorldEvents.get_instance(event_id),
         :ok <- authorize_activity_event(event, character),
         {:ok, %{instance: resolved_event, option: option}} <-
           WorldEvents.resolve_option(event, option_code) do
      {:ok,
       %{
         event: resolved_event,
         option: option,
         action: activity_action(option.action_key)
       }}
    else
      nil -> {:error, :event_not_found}
      {:error, _reason} = error -> error
    end
  end

  def resolve_activity_option(_character, _event_id, _option_code), do: {:error, :invalid_option}

  @doc "Records the hidden Secret Cult rumor only for the scoped character at the real discovery city."
  def hear_secret_cult_rumor(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, %{character: updated_character}} <- SecretCult.hear_rumor(character) do
      activity_hub_state(updated_character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Completes the tower-side Secret Cult step and returns the refreshed scoped location state."
  def reveal_secret_cult_passage(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, %{character: updated_character}} <- SecretCult.reveal_passage(character) do
      activity_hub_state(updated_character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Uses the discovered Secret Cult route without bypassing organization travel authorization."
  def use_secret_cult_passage(character_or_id, destination_location_id)
      when is_binary(destination_location_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, updated_character} <- SecretCult.use_pass(character, destination_location_id) do
      activity_hub_state(updated_character)
    else
      {:error, _reason} = error -> error
    end
  end

  def use_secret_cult_passage(_character_or_id, _destination_location_id),
    do: {:error, :secret_cult_passage_unavailable}

  @doc """
  Starts a player encounter with a nearby active character.

  The target ID is only a selection hint from the browser; availability and
  ownership are reconstructed from the scoped actor's current state.
  """
  def start_overworld_encounter(character_or_id, target_character_id)
      when is_binary(target_character_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_overworld_available(state),
         %Character{} = target <-
           find_nearby_character(state.character, state.current_location, target_character_id),
         {:ok, %OverworldEncounter{} = encounter} <-
           Overworld.create_encounter(state.character, target) do
      {:ok, %{encounter: overworld_encounter_summary(encounter, state.character)}}
    else
      nil -> {:error, :target_not_found}
      {:error, _reason} = error -> error
    end
  end

  def start_overworld_encounter(_character_or_id, _target_character_id),
    do: {:error, :target_not_found}

  @doc """
  Records one scoped actor's legal response to an open local encounter.

  Encounter IDs and actions come from the page, but the actor, realm, and
  location are never accepted from it.
  """
  def respond_to_overworld_encounter(character_or_id, encounter_id, action)
      when is_binary(encounter_id) and action in @overworld_actions do
    with {:ok, character} <- normalize_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_overworld_available(state),
         %OverworldEncounter{} = encounter <-
           current_open_encounter(state.character, state.current_location, encounter_id),
         {:ok, result} <- Overworld.respond(encounter, state.character, action) do
      {:ok,
       %{
         encounter: overworld_encounter_summary(result.encounter, state.character),
         combat: Map.get(result, :combat)
       }}
    else
      nil -> {:error, :encounter_not_found}
      {:error, _reason} = error -> error
    end
  end

  def respond_to_overworld_encounter(_character_or_id, _encounter_id, _action),
    do: {:error, :invalid_encounter_action}

  @doc """
  Starts a scoped character's persisted scavenging attempt from a cache at
  their current location. Cache, quantity, realm, and journey state are all
  revalidated on the server before the domain command runs.
  """
  def start_scavenging(character_or_id, resource_cache_id, quantity)
      when is_binary(resource_cache_id) and is_integer(quantity) and quantity > 0 do
    with {:ok, character} <- normalize_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_overworld_available(state),
         %ResourceCache{} = resource_cache <-
           available_resource_cache(state.current_location, resource_cache_id),
         true <- quantity <= resource_cache.quantity_remaining,
         {:ok, result} <- Scavenging.start_attempt(state.character, resource_cache, quantity) do
      {:ok,
       %{
         attempt: scavenging_attempt_summary(result.attempt),
         resource_cache: scavenging_cache_summary(result.resource_cache)
       }}
    else
      nil -> {:error, :resource_cache_not_found}
      false -> {:error, :invalid_scavenge_quantity}
      {:error, _reason} = error -> error
    end
  end

  def start_scavenging(_character_or_id, _resource_cache_id, _quantity),
    do: {:error, :invalid_scavenge_quantity}

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
         carry_capacity: Survival.carry_capacity(state.character),
         survival: Survival.summary(state.character),
         atmosphere:
           Atmosphere.cue_for(state.current_location,
             major_event: if(state.active_journey, do: :journey)
           )
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
         carry_capacity: Survival.carry_capacity(character),
         survival: Survival.summary(character)
       }}
    end
  end

  @doc """
  Loads the explicitly selected active base at the scoped player's current
  location along with carried and stored inventory. Direct ownership is the
  safe default; when several organization-custodied bases are present, the
  player must choose one by ID and every later action revalidates that choice.
  """
  def base_state(character_or_id, selected_base_id \\ nil)

  def base_state(character_or_id, selected_base_id)
      when is_nil(selected_base_id) or is_binary(selected_base_id) do
    with {:ok, character} <- reload_base_character(character_or_id) do
      state = state_for_character(character)
      character = state.character

      cond do
        not is_nil(state.active_journey) ->
          {:error, :travelling}

        is_nil(state.current_location) ->
          {:error, :location_not_found}

        true ->
          bases = Bases.list_accessible_bases_for_character(character)

          active_bases =
            Bases.accessible_active_bases_at_location(character, state.current_location.id)

          with {:ok, active_base} <-
                 selected_base(active_bases, character, selected_base_id) do
            building_base =
              Enum.find(Bases.list_bases_for_character(character.id), fn base ->
                base.location_id == state.current_location.id and base.status == :building
              end)

            storage_items =
              if(active_base, do: Bases.list_storage_items(active_base.id), else: [])

            survival = Survival.summary(character)
            carried_items = Inventory.list_inventory_for_character(character.id)
            {:ok, economy_account} = Economy.ensure_character_account(character)
            {:ok, acquisition_quote} = Bases.acquisition_quote(character, state.current_location)

            acquisition_quote =
              Map.put(
                acquisition_quote,
                :materials,
                material_availability(acquisition_quote.materials, carried_items)
              )

            {:ok,
             %{
               character: character,
               location: state.current_location,
               bases: bases,
               active_base: active_base,
               active_base_choices: active_base_choices(active_bases, character),
               requires_base_selection?: is_nil(active_base) and active_bases != [],
               building_base: building_base,
               storage_items: storage_items,
               carried_items: carried_items,
               acquisition_quote: acquisition_quote,
               balance: economy_account.current_balance,
               can_afford_acquisition?:
                 economy_account.current_balance >= acquisition_quote.total_coin_cost and
                   Enum.all?(acquisition_quote.materials, &(&1.available >= &1.quantity)),
               storage_weight: if(active_base, do: Bases.storage_weight(active_base), else: 0),
               storage_capacity:
                 if(active_base, do: active_base.storage_weight_capacity, else: 0),
               can_establish?:
                 is_nil(Bases.active_base_at_location(character.id, state.current_location.id)) and
                   is_nil(building_base),
               ownership:
                 if(active_base, do: base_ownership_state(active_base, character), else: nil),
               survival: survival,
               can_rest?:
                 not is_nil(active_base) and base_rest_available?(survival, storage_items)
             }}
          end
      end
    end
  end

  def base_state(_character_or_id, _selected_base_id), do: {:error, :base_not_accessible}

  @doc """
  Buys a city base or begins a custom non-city build at the scoped character's
  current location. The browser supplies only an optional display name.
  """
  def establish_current_base(character_or_id, attrs \\ %{})

  def establish_current_base(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character} <- normalize_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_base_available(state),
         true <-
           not base_exists_at_location(character, state.current_location.id) ||
             {:error, :base_exists} do
      case state.current_location.kind do
        :city -> Bases.purchase_city_base(character, state.current_location, attrs)
        _other -> Bases.start_custom_base_build(character, state.current_location, attrs)
      end
    else
      {:error, _reason} = error -> error
    end
  end

  def establish_current_base(_character_or_id, _attrs), do: {:error, :invalid_base}

  def deposit_to_current_base(character_or_id, inventory_item_id, quantity),
    do: deposit_to_current_base(character_or_id, inventory_item_id, quantity, nil)

  def deposit_to_current_base(character_or_id, inventory_item_id, quantity, selected_base_id)
      when is_binary(inventory_item_id) and is_integer(quantity) do
    with {:ok, character, base} <- current_selected_base(character_or_id, selected_base_id),
         %InventoryItem{} = item <- owned_carried_item(character, inventory_item_id),
         {:ok, _result} <- Bases.deposit_item(character, base, item, quantity) do
      base_state(character.id, base.id)
    else
      nil -> {:error, :inventory_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  def deposit_to_current_base(_character_or_id, _inventory_item_id, _quantity, _selected_base_id),
    do: {:error, :invalid_quantity}

  def withdraw_from_current_base(character_or_id, storage_item_id, quantity),
    do: withdraw_from_current_base(character_or_id, storage_item_id, quantity, nil)

  def withdraw_from_current_base(character_or_id, storage_item_id, quantity, selected_base_id)
      when is_binary(storage_item_id) and is_integer(quantity) do
    with {:ok, character, base} <- current_selected_base(character_or_id, selected_base_id),
         %StorageItem{} = item <- owned_storage_item(base, storage_item_id),
         {:ok, _result} <- Bases.withdraw_item(character, base, item, quantity) do
      base_state(character.id, base.id)
    else
      nil -> {:error, :storage_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  def withdraw_from_current_base(
        _character_or_id,
        _storage_item_id,
        _quantity,
        _selected_base_id
      ),
      do: {:error, :invalid_quantity}

  @doc "Consumes a stored ration and clears this scoped character's hunger consequences at home."
  def rest_at_current_base(character_or_id), do: rest_at_current_base(character_or_id, nil)

  def rest_at_current_base(character_or_id, selected_base_id) do
    with {:ok, character, base} <- current_selected_base(character_or_id, selected_base_id),
         {:ok, _result} <- Bases.rest_at_base(character, base) do
      base_state(character.id, base.id)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Changes the selected base's real organization custody share through the scoped owner."
  def configure_current_base_organization_share(
        character_or_id,
        base_id,
        organization_id,
        share_bps
      )
      when is_binary(base_id) and is_binary(organization_id) and is_integer(share_bps) and
             share_bps in 0..9_999 do
    with {:ok, character, base} <- current_selected_base(character_or_id, base_id),
         %Organization{} = organization <- safe_get_organization(organization_id),
         {:ok, _base} <-
           Bases.configure_organization_share(base, character, organization, share_bps) do
      base_state(character.id, base.id)
    else
      nil -> {:error, :base_ownership_organization_not_found}
      {:error, _reason} = error -> error
    end
  end

  def configure_current_base_organization_share(
        _character_or_id,
        _base_id,
        _organization_id,
        _share_bps
      ),
      do: {:error, :base_ownership_unavailable}

  @doc """
  Composes only the scoped player's real shop, legal-market, and black-market
  state. Listings and offers remain realm-local; account balances and carried
  inventory are read from durable contexts rather than UI assigns.
  """
  def trade_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)
      character = state.character

      with :ok <- ensure_trade_available(state) do
        realm = Worlds.get_realm!(character.realm_id)
        ruleset = Worlds.realm_ruleset(realm)
        {:ok, account} = Economy.ensure_character_account(character)

        shops =
          state.current_location.id
          |> NPCShops.list_shops_for_location()
          |> Enum.map(&NPCShops.get_shop!(&1.id))

        market_listings = Market.list_active_listings(realm.id)
        black_market_offers = BlackMarket.list_active_offers(realm.id)

        {:ok,
         %{
           character: character,
           location: state.current_location,
           realm: realm,
           balance: account.current_balance,
           shops: shops,
           inventory: Inventory.list_inventory_for_character(character.id),
           legal_market_enabled?: ruleset["legal_market_enabled"] == true,
           black_market_enabled?: ruleset["black_market_enabled"] == true,
           market_listings: market_listings,
           own_market_listings:
             Enum.filter(market_listings, &(&1.seller_character_id == character.id)),
           black_market_offers: black_market_offers,
           own_black_market_offers:
             Enum.filter(black_market_offers, &(&1.seller_character_id == character.id)),
           black_market_deals: BlackMarket.list_deals_for_character(character.id),
           black_market_risks:
             Map.new(black_market_offers, fn offer ->
               {offer.id,
                BlackMarket.detection_terms(
                  offer.total_price,
                  ruleset["legal_market_tax_rate_bps"]
                )}
             end),
           grimoire_tiers: Grimoires.purchase_tiers(),
           legal_market_tax_rate_bps: ruleset["legal_market_tax_rate_bps"]
         }}
      end
    end
  end

  def buy_shop_item(character_or_id, offer_id, quantity)
      when is_binary(offer_id) and is_integer(quantity) do
    with {:ok, state} <- trade_state(character_or_id),
         offer when not is_nil(offer) <- find_current_shop_offer(state.shops, offer_id),
         {:ok, _result} <- NPCShops.buy(state.character, offer, quantity) do
      trade_state(state.character)
    else
      nil -> {:error, :shop_offer_not_found}
      {:error, _reason} = error -> error
    end
  end

  def buy_shop_item(_character_or_id, _offer_id, _quantity), do: {:error, :invalid_quantity}

  @doc "Buys one fixed-capacity grimoire from the current city's trade catalog."
  def purchase_trade_grimoire(character_or_id, tier_key) when is_binary(tier_key) do
    with {:ok, state} <- trade_state(character_or_id),
         {:ok, _result} <- Grimoires.purchase_grimoire(state.character, tier_key) do
      trade_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def purchase_trade_grimoire(_character_or_id, _tier_key),
    do: {:error, :invalid_grimoire_tier}

  def sell_shop_item(character_or_id, offer_id, inventory_item_id, quantity)
      when is_binary(offer_id) and is_binary(inventory_item_id) and is_integer(quantity) do
    with {:ok, state} <- trade_state(character_or_id),
         offer when not is_nil(offer) <- find_current_shop_offer(state.shops, offer_id),
         %InventoryItem{} = item <- owned_carried_item(state.character, inventory_item_id),
         {:ok, _result} <- NPCShops.sell(state.character, offer, item, quantity) do
      trade_state(state.character)
    else
      nil -> {:error, :shop_inventory_not_found}
      {:error, _reason} = error -> error
    end
  end

  def sell_shop_item(_character_or_id, _offer_id, _inventory_item_id, _quantity),
    do: {:error, :invalid_quantity}

  def create_market_listing(character_or_id, inventory_item_id, quantity, unit_price)
      when is_binary(inventory_item_id) and is_integer(quantity) and is_integer(unit_price) do
    with {:ok, state} <- trade_state(character_or_id),
         true <- state.legal_market_enabled? || {:error, :legal_market_disabled},
         %InventoryItem{} = item <- owned_carried_item(state.character, inventory_item_id),
         {:ok, _result} <-
           Market.create_listing(state.character, item, %{
             quantity: quantity,
             unit_price: unit_price,
             tax_rate_bps: state.legal_market_tax_rate_bps
           }) do
      trade_state(state.character)
    else
      nil -> {:error, :inventory_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  def create_market_listing(_character_or_id, _inventory_item_id, _quantity, _unit_price),
    do: {:error, :invalid_listing}

  def purchase_market_listing(character_or_id, listing_id) when is_binary(listing_id) do
    with {:ok, state} <- trade_state(character_or_id),
         true <- state.legal_market_enabled? || {:error, :legal_market_disabled},
         listing when not is_nil(listing) <-
           find_market_listing(state.market_listings, listing_id),
         {:ok, _result} <- Market.purchase_listing(listing, state.character) do
      trade_state(state.character)
    else
      nil -> {:error, :market_listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  def purchase_market_listing(_character_or_id, _listing_id),
    do: {:error, :market_listing_not_found}

  def cancel_market_listing(character_or_id, listing_id) when is_binary(listing_id) do
    with {:ok, state} <- trade_state(character_or_id),
         listing when not is_nil(listing) <-
           find_owned_market_listing(state.own_market_listings, listing_id),
         {:ok, _result} <- Market.cancel_listing(listing, state.character) do
      trade_state(state.character)
    else
      nil -> {:error, :market_listing_not_found}
      {:error, _reason} = error -> error
    end
  end

  def cancel_market_listing(_character_or_id, _listing_id),
    do: {:error, :market_listing_not_found}

  def create_black_market_offer(character_or_id, inventory_item_id, quantity, unit_price)
      when is_binary(inventory_item_id) and is_integer(quantity) and is_integer(unit_price) do
    with {:ok, state} <- trade_state(character_or_id),
         true <- state.black_market_enabled? || {:error, :black_market_disabled},
         %InventoryItem{} = item <- owned_carried_item(state.character, inventory_item_id),
         {:ok, _result} <-
           BlackMarket.create_offer(state.character, item, %{
             quantity: quantity,
             unit_price: unit_price
           }) do
      trade_state(state.character)
    else
      nil -> {:error, :inventory_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  def create_black_market_offer(_character_or_id, _inventory_item_id, _quantity, _unit_price),
    do: {:error, :invalid_listing}

  def accept_black_market_offer(character_or_id, offer_id) when is_binary(offer_id) do
    with {:ok, state} <- trade_state(character_or_id),
         true <- state.black_market_enabled? || {:error, :black_market_disabled},
         offer when not is_nil(offer) <-
           find_black_market_offer(state.black_market_offers, offer_id),
         {:ok, _result} <- BlackMarket.accept_offer(offer, state.character) do
      trade_state(state.character)
    else
      nil -> {:error, :black_market_offer_not_found}
      {:error, _reason} = error -> error
    end
  end

  def accept_black_market_offer(_character_or_id, _offer_id),
    do: {:error, :black_market_offer_not_found}

  def fulfill_black_market_deal(character_or_id, deal_id) when is_binary(deal_id) do
    with {:ok, state} <- trade_state(character_or_id),
         deal when not is_nil(deal) <-
           find_owned_black_market_deal(state.black_market_deals, deal_id),
         {:ok, _result} <- BlackMarket.fulfill_deal(deal, state.character) do
      trade_state(state.character)
    else
      nil -> {:error, :black_market_deal_not_found}
      {:error, _reason} = error -> error
    end
  end

  def fulfill_black_market_deal(_character_or_id, _deal_id),
    do: {:error, :black_market_deal_not_found}

  def default_black_market_deal(character_or_id, deal_id) when is_binary(deal_id) do
    with {:ok, state} <- trade_state(character_or_id),
         deal when not is_nil(deal) <-
           find_owned_black_market_deal(state.black_market_deals, deal_id),
         {:ok, _result} <-
           BlackMarket.default_deal(deal, state.character, "delivery deadline claimed by buyer") do
      trade_state(state.character)
    else
      nil -> {:error, :black_market_deal_not_found}
      {:error, _reason} = error -> error
    end
  end

  def default_black_market_deal(_character_or_id, _deal_id),
    do: {:error, :black_market_deal_not_found}

  @doc """
  Returns the scoped player's balance, relevant append-only ledger entries,
  and public realm accounts needed to explain taxes, tuition, and charity.
  """
  def finance_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      with :ok <- ensure_trade_available(state) do
        realm = Worlds.get_realm!(state.character.realm_id)
        {:ok, account} = Economy.ensure_character_account(state.character)
        {:ok, charity_account} = NPCShops.ensure_charity_fund_account(realm)
        treasury = Economy.treasury_account_for_realm(realm.id)

        {:ok,
         %{
           character: state.character,
           location: state.current_location,
           balance: account.current_balance,
           ledger_entries: Economy.list_ledger_entries_for_account(account.id),
           treasury_balance: if(treasury, do: treasury.current_balance, else: 0),
           charity_balance: charity_account.current_balance
         }}
      end
    end
  end

  def donate_to_charity(character_or_id, amount) when is_integer(amount) do
    with {:ok, state} <- finance_state(character_or_id),
         {:ok, _result} <- NPCShops.donate_to_charity(state.character, amount) do
      finance_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def donate_to_charity(_character_or_id, _amount), do: {:error, :invalid_amount}

  def pay_academy_tuition(character_or_id, amount) when is_integer(amount) do
    with {:ok, state} <- finance_state(character_or_id),
         {:ok, _result} <- NPCShops.pay_tuition(state.character, amount) do
      finance_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def pay_academy_tuition(_character_or_id, _amount), do: {:error, :invalid_amount}

  @doc """
  Loads real alchemy recipes, the scoped character's workshop at their active
  base, and durable brew jobs. Recipes and materials remain domain-owned.
  """
  def alchemy_state(character_or_id) do
    with {:ok, character, base} <- current_active_base(character_or_id) do
      alchemy_workshop = Alchemy.get_workshop_for_character(character.id)

      {:ok,
       %{
         character: character,
         base: base,
         workspace: alchemy_workshop,
         workspace_here?:
           not is_nil(alchemy_workshop) and alchemy_workshop.location_id == base.location_id,
         recipes: Alchemy.list_recipes_for_character(character),
         ingredients: Alchemy.interpretable_ingredients(character),
         jobs: Alchemy.list_brew_jobs_for_character(character.id),
         inventory: Inventory.list_inventory_for_character(character.id),
         installed_tool_codes: installed_tool_codes(character)
       }}
    end
  end

  def create_alchemy_workshop(character_or_id, attrs \\ %{})

  def create_alchemy_workshop(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character, base} <- current_active_base(character_or_id),
         nil <- Alchemy.get_workshop_for_character(character.id),
         {:ok, _workshop} <-
           Alchemy.create_workshop(character, %{
             name: Map.get(attrs, "name") || "Алхимический стол",
             location_id: base.location_id,
             installed_tool_codes: installed_tool_codes(character)
           }) do
      alchemy_state(character)
    else
      %{} -> {:error, :alchemy_workshop_exists}
      {:error, _reason} = error -> error
    end
  end

  def create_alchemy_workshop(_character_or_id, _attrs), do: {:error, :invalid_workshop}

  def start_brew(character_or_id, recipe_id, quantity)
      when is_binary(recipe_id) and is_integer(quantity) do
    with {:ok, state} <- alchemy_state(character_or_id),
         true <- state.workspace_here? || {:error, :alchemy_workshop_not_here},
         recipe when not is_nil(recipe) <- Enum.find(state.recipes, &(&1.id == recipe_id)),
         {:ok, _result} <- Alchemy.brew(state.character, state.workspace, recipe, quantity) do
      alchemy_state(state.character)
    else
      nil -> {:error, :alchemy_recipe_not_found}
      {:error, _reason} = error -> error
    end
  end

  def start_brew(_character_or_id, _recipe_id, _quantity), do: {:error, :invalid_quantity}

  def start_interpreted_brew(character_or_id, selections) when is_map(selections) do
    with {:ok, state} <- alchemy_state(character_or_id),
         true <- state.workspace_here? || {:error, :alchemy_workshop_not_here},
         {:ok, _result} <-
           Alchemy.brew_from_ingredients(state.character, state.workspace, selections) do
      alchemy_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def start_interpreted_brew(_character_or_id, _selections),
    do: {:error, :invalid_ingredients}

  def collect_brew(character_or_id, brew_job_id) when is_binary(brew_job_id) do
    with {:ok, state} <- alchemy_state(character_or_id),
         job when not is_nil(job) <- Enum.find(state.jobs, &(&1.id == brew_job_id)),
         {:ok, _result} <- Alchemy.complete_brew_job_by_id(job.id) do
      alchemy_state(state.character)
    else
      nil -> {:error, :brew_job_not_found}
      {:error, _reason} = error -> error
    end
  end

  def collect_brew(_character_or_id, _brew_job_id), do: {:error, :brew_job_not_found}

  @doc """
  Loads real crafting recipes, the scoped character's workshop at their active
  base, and durable craft jobs.
  """
  def craft_state(character_or_id) do
    with {:ok, character, base} <- current_active_base(character_or_id) do
      crafting_workshop = Crafting.get_workshop_for_character(character.id)

      {:ok,
       %{
         character: character,
         base: base,
         workspace: crafting_workshop,
         workspace_here?:
           not is_nil(crafting_workshop) and crafting_workshop.location_id == base.location_id,
         recipes: Crafting.list_recipes(),
         jobs: Crafting.list_craft_jobs_for_character(character.id),
         inventory: Inventory.list_inventory_for_character(character.id),
         installed_tool_codes: installed_tool_codes(character)
       }}
    end
  end

  def create_crafting_workshop(character_or_id, attrs \\ %{})

  def create_crafting_workshop(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character, base} <- current_active_base(character_or_id),
         nil <- Crafting.get_workshop_for_character(character.id),
         {:ok, _workshop} <-
           Crafting.create_workshop(character, %{
             name: Map.get(attrs, "name") || "Верстак",
             location_id: base.location_id,
             installed_tool_codes: installed_tool_codes(character)
           }) do
      craft_state(character)
    else
      %{} -> {:error, :crafting_workshop_exists}
      {:error, _reason} = error -> error
    end
  end

  def create_crafting_workshop(_character_or_id, _attrs), do: {:error, :invalid_workshop}

  def start_craft(character_or_id, recipe_id, quantity)
      when is_binary(recipe_id) and is_integer(quantity) do
    with {:ok, state} <- craft_state(character_or_id),
         true <- state.workspace_here? || {:error, :crafting_workshop_not_here},
         recipe when not is_nil(recipe) <- Enum.find(state.recipes, &(&1.id == recipe_id)),
         {:ok, _result} <- Crafting.craft(state.character, state.workspace, recipe, quantity) do
      craft_state(state.character)
    else
      nil -> {:error, :craft_recipe_not_found}
      {:error, _reason} = error -> error
    end
  end

  def start_craft(_character_or_id, _recipe_id, _quantity), do: {:error, :invalid_quantity}

  def collect_craft(character_or_id, craft_job_id) when is_binary(craft_job_id) do
    with {:ok, state} <- craft_state(character_or_id),
         job when not is_nil(job) <- Enum.find(state.jobs, &(&1.id == craft_job_id)),
         {:ok, _result} <- Crafting.complete_craft_job_by_id(job.id) do
      craft_state(state.character)
    else
      nil -> {:error, :craft_job_not_found}
      {:error, _reason} = error -> error
    end
  end

  def collect_craft(_character_or_id, _craft_job_id), do: {:error, :craft_job_not_found}

  @doc """
  Loads the scoped party, members, same-location invite candidates, pending
  invitations, and active expedition summary. Party membership authority stays
  in `MMGO.Parties`.
  """
  def party_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)
      character = state.character
      party = Parties.active_party_for_character(character.id)
      expedition = Parties.active_expedition_for_character(character.id)

      nearby_characters =
        if is_nil(state.active_journey) and state.current_location do
          nearby_stationary_characters(character, state.current_location)
        else
          []
        end

      {:ok,
       %{
         character: character,
         location: state.current_location,
         travelling?: not is_nil(state.active_journey),
         party: party,
         members: if(party, do: party.memberships, else: []),
         nearby_characters: nearby_characters,
         pending_invitations: Parties.pending_invitations_for_character(character.id),
         active_expedition: expedition,
         loot_policy:
           if(party, do: Map.get(party.metadata || %{}, "loot_policy", "round_robin"), else: nil),
         survival: Survival.summary(character)
       }}
    end
  end

  def create_party(character_or_id, attrs \\ %{})

  def create_party(character_or_id, attrs) when is_map(attrs) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, _result} <- Parties.create_party(character, attrs) do
      party_state(character)
    else
      {:error, _reason} = error -> error
    end
  end

  def create_party(_character_or_id, _attrs), do: {:error, :invalid_party}

  def invite_to_party(character_or_id, target_character_id) when is_binary(target_character_id) do
    with {:ok, state} <- party_state(character_or_id),
         true <- not state.travelling? || {:error, :travelling},
         %Party{} = party <- state.party,
         %Character{} = target <-
           find_nearby_character(state.character, state.location, target_character_id),
         {:ok, _result} <- Parties.invite_member(party, state.character, target) do
      party_state(state.character)
    else
      nil -> {:error, :party_or_target_not_found}
      {:error, _reason} = error -> error
    end
  end

  def invite_to_party(_character_or_id, _target_character_id),
    do: {:error, :party_or_target_not_found}

  def accept_party_invitation(character_or_id, invitation_id) when is_binary(invitation_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, _result} <- Parties.accept_invitation(invitation_id, character) do
      party_state(character)
    else
      {:error, _reason} = error -> error
    end
  end

  def accept_party_invitation(_character_or_id, _invitation_id),
    do: {:error, :party_invitation_not_found}

  def reject_party_invitation(character_or_id, invitation_id) when is_binary(invitation_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         {:ok, _result} <- Parties.reject_invitation(invitation_id, character) do
      party_state(character)
    else
      {:error, _reason} = error -> error
    end
  end

  def reject_party_invitation(_character_or_id, _invitation_id),
    do: {:error, :party_invitation_not_found}

  def leave_party(character_or_id) do
    with {:ok, state} <- party_state(character_or_id),
         %Party{} = party <- state.party,
         {:ok, _result} <- Parties.remove_member(party, state.character) do
      party_state(state.character)
    else
      nil -> {:error, :party_not_found}
      {:error, _reason} = error -> error
    end
  end

  def set_party_ready(character_or_id, ready?) when is_boolean(ready?) do
    with {:ok, state} <- party_state(character_or_id),
         %Party{} = party <- state.party,
         {:ok, _result} <- Parties.set_member_ready(party, state.character, ready?) do
      party_state(state.character)
    else
      nil -> {:error, :party_not_found}
      {:error, _reason} = error -> error
    end
  end

  def set_party_ready(_character_or_id, _ready?), do: {:error, :party_not_found}

  def set_party_loot_policy(character_or_id, policy) do
    with {:ok, state} <- party_state(character_or_id),
         %Party{} = party <- state.party,
         {:ok, _party} <- Parties.set_loot_policy(party, state.character, policy) do
      party_state(state.character)
    else
      nil -> {:error, :party_not_found}
      {:error, _reason} = error -> error
    end
  end

  def start_party_expedition(character_or_id) do
    with {:ok, state} <- party_state(character_or_id),
         %Party{} = party <- state.party,
         true <- party.leader_character_id == state.character.id || {:error, :not_party_leader},
         {:ok, %{expedition: expedition}} <- Parties.start_expedition(party) do
      {:ok, %{expedition: expedition}}
    else
      nil -> {:error, :party_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_party_leader}
    end
  end

  @doc """
  Composes the scoped party expedition and its current dungeon run. Route and
  content IDs are treated as display data only; every command below resolves
  them again from this authoritative state.
  """
  def dungeon_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)
      character = state.character
      expedition = Parties.active_expedition_for_character(character.id)
      party = if(expedition, do: Parties.get_party!(expedition.party_id), else: nil)
      run = if(expedition, do: Dungeons.active_run_for_expedition(expedition.id), else: nil)

      entry_dungeon =
        if expedition && is_nil(run) do
          Dungeons.active_dungeon_at_location(character.realm_id, expedition.location_id)
        end

      base_state = %{
        character: character,
        current_location: state.current_location,
        travelling?: not is_nil(state.active_journey),
        party: party,
        expedition: expedition,
        members:
          if(expedition, do: Parties.active_members_for_expedition(expedition.id), else: []),
        supply:
          if(expedition,
            do: Survival.expedition_supply_summary(expedition.id),
            else: empty_supply()
          ),
        survival: if(expedition, do: Parties.expedition_survival_state(expedition), else: nil),
        route_plan:
          if(expedition, do: Map.get(expedition.metadata || %{}, "club_route_plan"), else: nil),
        loot_policy:
          if(party, do: Map.get(party.metadata || %{}, "loot_policy", "round_robin"), else: nil),
        entry_dungeon: entry_dungeon,
        leader?: not is_nil(party) and party.leader_character_id == character.id
      }

      dungeon_state =
        Map.merge(base_state, dungeon_run_state(character, run, entry_dungeon, party))

      {:ok,
       Map.put(
         dungeon_state,
         :atmosphere,
         Atmosphere.cue_for(
           if(dungeon_state.run, do: :dungeon_entrance, else: state.current_location),
           major_event: dungeon_atmosphere_event(dungeon_state)
         )
       )}
    end
  end

  def enter_current_dungeon(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Expedition{} = expedition <- state.expedition,
         true <- state.leader? || {:error, :not_party_leader},
         true <- is_nil(state.run) || {:error, :dungeon_run_already_active},
         %Dungeon{} = dungeon <- state.entry_dungeon,
         true <-
           state.character.current_location_id == expedition.location_id ||
             {:error, :expedition_not_at_entrance},
         {:ok, _result} <- Dungeons.enter_dungeon(expedition, dungeon) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_entry_unavailable}
      {:error, _reason} = error -> error
      false -> {:error, :dungeon_entry_unavailable}
    end
  end

  def move_in_dungeon(character_or_id, target_node_id) when is_binary(target_node_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Run{} = run <- state.run,
         %{node: node} <- Enum.find(state.reachable_nodes, &(&1.node.id == target_node_id)),
         {:ok, _result} <- Dungeons.move_run(run, node.id) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_node_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def move_in_dungeon(_character_or_id, _target_node_id), do: {:error, :dungeon_node_unavailable}

  def avoid_current_dungeon_encounter(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Encounter{status: :pending} = encounter <- state.current_encounter,
         {:ok, _result} <- Dungeons.resolve_encounter(encounter, :avoided) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_encounter_unavailable}
      {:error, _reason} = error -> error
      _other -> {:error, :dungeon_encounter_unavailable}
    end
  end

  def start_current_dungeon_combat(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Encounter{status: :pending} = encounter <- state.current_encounter,
         {:ok, %{combat: combat}} <- Dungeons.start_encounter_combat(encounter) do
      {:ok, %{combat: combat}}
    else
      nil -> {:error, :dungeon_encounter_unavailable}
      {:error, _reason} = error -> error
      _other -> {:error, :dungeon_encounter_unavailable}
    end
  end

  def sync_current_dungeon_combat(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Combat{status: :finished} = combat <- state.active_combat,
         {:ok, %{encounter: encounter}} <- Dungeons.sync_encounter_combat(combat) do
      run = Dungeons.get_run!(state.run.id)

      {:ok,
       %{
         state: dungeon_state_after_combat(state.character),
         encounter: encounter,
         failed?: run.status == :failed
       }}
    else
      nil -> {:error, :dungeon_combat_not_finished}
      {:error, _reason} = error -> error
      _other -> {:error, :dungeon_combat_not_finished}
    end
  end

  def claim_current_dungeon_loot(character_or_id, loot_drop_id) when is_binary(loot_drop_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %LootDrop{} = loot_drop <- Enum.find(state.available_loot, &(&1.id == loot_drop_id)),
         {:ok, _result} <- Dungeons.claim_loot(loot_drop, state.character) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_loot_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def claim_current_dungeon_loot(_character_or_id, _loot_drop_id),
    do: {:error, :dungeon_loot_unavailable}

  def harvest_current_dungeon_resource(character_or_id, resource_cache_id, quantity)
      when is_binary(resource_cache_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         {:ok, quantity} <- positive_dungeon_quantity(quantity),
         %DungeonResourceCache{} = resource_cache <-
           Enum.find(state.available_resources, &(&1.id == resource_cache_id)),
         {:ok, _result} <- Dungeons.harvest_resource(resource_cache, state.character, quantity) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_resource_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def harvest_current_dungeon_resource(_character_or_id, _resource_cache_id, _quantity),
    do: {:error, :dungeon_resource_unavailable}

  def extract_current_dungeon(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Run{} = run <- state.run,
         true <- state.can_extract? || {:error, :dungeon_extraction_unavailable},
         {:ok, _result} <- Dungeons.extract_via_ascent(run) do
      dungeon_state(state.character)
    else
      nil -> {:error, :dungeon_extraction_unavailable}
      {:error, _reason} = error -> error
      false -> {:error, :dungeon_extraction_unavailable}
    end
  end

  def begin_current_return_ritual(character_or_id) do
    with {:ok, state} <- dungeon_state(character_or_id),
         %Run{} = run <- state.run,
         true <- state.can_return_ritual? || {:error, :return_ritual_unavailable},
         {:ok, _result} <- Dungeons.start_return_ritual(run, state.character) do
      dungeon_state(state.character)
    else
      nil -> {:error, :return_ritual_unavailable}
      {:error, _reason} = error -> error
      false -> {:error, :return_ritual_unavailable}
    end
  end

  @doc "Loads the scoped character's most recent real Roguelike's Sacrifice ledger."
  def defeat_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Run{} = run <- Dungeons.latest_failed_run_for_character(character.id) do
      dungeon = Dungeons.get_dungeon!(run.dungeon_id)

      lost_drops =
        run.id
        |> Dungeons.list_drops_for_run()
        |> Enum.filter(&(&1.owner_character_id == character.id))

      kept_xp =
        run.expedition_id
        |> Parties.list_rewards_for_expedition()
        |> Enum.filter(&(&1.character_id == character.id and &1.run_id == run.id))
        |> Enum.reduce(0, &(&1.amount + &2))

      {:ok,
       %{
         character: character,
         run: run,
         dungeon: dungeon,
         return_location: dungeon.entrance_location,
         lost_drops: lost_drops,
         kept_xp: kept_xp
       }}
    else
      nil -> {:error, :defeat_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Returns the scoped, city-only academic state used by the Academy hall. The
  browser receives current enrollment and realm courses, never a term or grade
  authority that it can forge.
  """
  def academy_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      with :ok <- ensure_academy_available(state) do
        character = state.character
        enrollment = Academy.current_enrollment(character.id)
        enrollment_history = Academy.enrollment_history(character.id)
        latest_enrollment = List.last(enrollment_history)
        record_enrollment = enrollment || latest_enrollment

        academic_titles =
          character.id
          |> Academy.list_academic_titles()
          |> Enum.map(&academy_academic_title/1)

        valedictorian_honors =
          character.id
          |> Academy.list_valedictorian_honors()
          |> Enum.map(&academy_valedictorian_honor/1)

        valedictorian_bonus =
          case Academy.pending_valedictorian_bonus(character.id) do
            nil -> nil
            bonus_enrollment -> academy_valedictorian_honor(bonus_enrollment)
          end

        terms = if(enrollment, do: Academy.list_terms_for_enrollment(enrollment.id), else: [])
        current_term = if(enrollment, do: Academy.current_term(enrollment.id), else: nil)

        required_terms =
          if(enrollment, do: Academy.required_term_count(enrollment.program_type), else: 0)

        current_term_schedule =
          if current_term do
            Academy.term_schedule(enrollment, current_term.term_number)
          end

        next_term_schedule =
          if enrollment && is_nil(current_term) do
            Academy.term_schedule(enrollment, length(terms) + 1)
          end

        course_enrollments =
          if(current_term,
            do: Academy.list_course_enrollments_for_term(current_term.id),
            else: []
          )

        courses =
          if enrollment && current_term do
            Academy.list_courses_for_term(enrollment, current_term.term_number)
          else
            Academy.list_courses_for_realm(character.realm_id)
          end

        {:ok,
         %{
           character: character,
           location: state.current_location,
           enrollment: enrollment,
           latest_enrollment: latest_enrollment,
           enrollment_history: enrollment_history,
           specialization: Academy.active_specialization(character.id),
           terms: terms,
           current_term: current_term,
           required_terms: required_terms,
           current_term_schedule: current_term_schedule,
           next_term_schedule: next_term_schedule,
           term_progress:
             if(current_term,
               do: Academy.term_progress(current_term, character_id: character.id),
               else: nil
             ),
           course_enrollments: course_enrollments,
           courses: courses,
           gpa: if(enrollment, do: Academy.gpa_for_enrollment(enrollment.id), else: nil),
           failed_terms: if(enrollment, do: Academy.failed_terms_count(enrollment.id), else: 0),
           charity_stipend: if(enrollment, do: Academy.charity_stipend(enrollment), else: nil),
           academic_record:
             if(record_enrollment, do: Academy.academic_record(record_enrollment), else: nil),
           starter_outcomes:
             if(record_enrollment, do: Academy.starter_outcomes(record_enrollment), else: nil),
           academic_titles: academic_titles,
           valedictorian_honors: valedictorian_honors,
           valedictorian_bonus: valedictorian_bonus,
           cohort_leaderboard:
             if(record_enrollment, do: Academy.cohort_leaderboard(record_enrollment), else: []),
           program_options: academy_program_options(character, enrollment)
         }}
      end
    end
  end

  def start_academy_program(character_or_id, attrs) when is_map(attrs) do
    with {:ok, state} <- academy_state(character_or_id),
         {:ok, _result} <- start_scoped_academy_program(state.character, attrs) do
      academy_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def start_academy_program(_character_or_id, _attrs), do: {:error, :academy_program_unavailable}

  @doc "Claims the current scoped player's single valedictorian spell choice."
  def claim_scoped_valedictorian_spell(character_or_id, school) when is_binary(school) do
    with {:ok, state} <- academy_state(character_or_id),
         {:ok, _result} <- Academy.claim_valedictorian_bonus_spell(state.character, school) do
      academy_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def claim_scoped_valedictorian_spell(_character_or_id, _school),
    do: {:error, :valedictorian_bonus_unavailable}

  def begin_current_academy_term(character_or_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %MMGO.Academy.Enrollment{} = enrollment <- state.enrollment,
         true <- is_nil(state.current_term) || {:error, :academy_term_already_active},
         {:ok, _term} <- Academy.begin_term(enrollment.id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_enrollment_unavailable}
      {:error, _reason} = error -> error
      false -> {:error, :academy_term_already_active}
    end
  end

  def enroll_current_academy_course(character_or_id, course_id) when is_binary(course_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %MMGO.Academy.Term{} = term <- state.current_term,
         course when not is_nil(course) <- Enum.find(state.courses, &(&1.id == course_id)),
         {:ok, _course_enrollment} <-
           Academy.enroll_in_course(state.character.id, term.id, course.id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_course_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def enroll_current_academy_course(_character_or_id, _course_id),
    do: {:error, :academy_course_unavailable}

  def attend_current_course_office_hours(character_or_id, course_id) when is_binary(course_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %MMGO.Academy.Term{} = term <- state.current_term,
         {:ok, _result} <- Academy.attend_office_hours(state.character.id, term.id, course_id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_office_hours_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def attend_current_course_office_hours(_character_or_id, _course_id),
    do: {:error, :academy_office_hours_unavailable}

  def open_current_academy_lecture_phase(character_or_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: term_id} <- state.current_term,
         {:ok, _term} <- Academy.open_lecture_phase(state.character.id, term_id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_term_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def close_current_academy_lecture_phase(character_or_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: term_id} <- state.current_term,
         {:ok, _term} <- Academy.close_lecture_phase(state.character.id, term_id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_term_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def close_current_academy_club_window(character_or_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: term_id} <- state.current_term,
         {:ok, _term} <- Academy.close_club_window(state.character.id, term_id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_term_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def attend_current_academy_lecture(character_or_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: term_id} <- state.current_term,
         {:ok, _term} <- Academy.attend_lecture(state.character.id, term_id) do
      academy_state(state.character)
    else
      nil -> {:error, :academy_term_unavailable}
      {:error, _reason} = error -> error
    end
  end

  @doc "Loads the next real lecture prompt for the scoped student's active Academy term."
  def academy_lecture_state(character_or_id, term_id) when is_binary(term_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: ^term_id} = term <- state.current_term,
         %{phase: :lectures} = progress <- state.term_progress,
         {:ok, lecture} <- Academy.lecture_prompt(state.character.id, term.id) do
      {:ok,
       %{
         character: state.character,
         term: term,
         lecture: lecture,
         lectures_attended: progress.lectures_attended,
         lectures_required: progress.lectures_required,
         current_final_ceiling: progress.lecture_final_ceiling
       }}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :academy_lecture_unavailable}
    end
  end

  def academy_lecture_state(_character_or_id, _term_id),
    do: {:error, :academy_lecture_unavailable}

  @doc "Scores one scoped student's lecture answers and refreshes the Academy state."
  def submit_scoped_academy_lecture(character_or_id, term_id, answers)
      when is_binary(term_id) and is_map(answers) do
    with {:ok, lecture_state} <- academy_lecture_state(character_or_id, term_id),
         {:ok, result} <-
           Academy.submit_lecture(lecture_state.character.id, lecture_state.term.id, answers),
         {:ok, state} <- academy_state(lecture_state.character) do
      {:ok, Map.put(result, :state, state)}
    else
      {:error, _reason} = error -> error
    end
  end

  def submit_scoped_academy_lecture(_character_or_id, _term_id, _answers),
    do: {:error, :academy_lecture_unavailable}

  def academy_exam_state(character_or_id, term_id) when is_binary(term_id) do
    with {:ok, state} <- academy_state(character_or_id),
         %{id: ^term_id} = term <- state.current_term,
         %{phase: phase} = progress <- state.term_progress,
         true <- phase in [:midterm, :final] || {:error, :academy_exam_unavailable} do
      {:ok,
       %{
         character: state.character,
         enrollment: state.enrollment,
         term: term,
         progress: progress,
         phase: phase,
         questions: Academy.exam_questions(state.enrollment),
         midterm_skippable?:
           phase == :midterm and state.enrollment.program_type == :basic_education
       }}
    else
      nil -> {:error, :academy_exam_unavailable}
      false -> {:error, :academy_exam_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def academy_exam_state(_character_or_id, _term_id), do: {:error, :academy_exam_unavailable}

  @doc "Opens or resumes the scoped student's persisted timed Academy exam."
  def start_current_academy_exam(character_or_id, term_id) when is_binary(term_id) do
    with {:ok, state} <- academy_exam_state(character_or_id, term_id),
         {:ok, attempt} <- Academy.start_exam_attempt(state.character.id, state.term.id),
         {:ok, refreshed_state} <- academy_exam_state(state.character, term_id) do
      {:ok,
       refreshed_state
       |> Map.put(:exam_attempt_id, attempt.attempt_id)
       |> Map.put(:deadline_at, attempt.deadline_at)}
    else
      {:error, _reason} = error -> error
    end
  end

  def start_current_academy_exam(_character_or_id, _term_id),
    do: {:error, :academy_exam_unavailable}

  def submit_current_academy_exam(character_or_id, term_id, answers)
      when is_binary(term_id) and is_map(answers) do
    with {:ok, state} <- academy_exam_state(character_or_id, term_id),
         score = Academy.score_exam(state.enrollment, answers),
         {:ok, _term} <-
           Academy.submit_exam_attempt(
             state.character.id,
             state.term.id,
             state.phase,
             score
           ),
         {:ok, academy_state} <- academy_state(state.character) do
      {:ok, %{state: academy_state, score: score, phase: state.phase}}
    else
      {:error, _reason} = error -> error
    end
  end

  def submit_current_academy_exam(_character_or_id, _term_id, _answers),
    do: {:error, :academy_exam_unavailable}

  @doc "Applies an elapsed timed exam's persisted timeout outcome for its owner."
  def expire_current_academy_exam(character_or_id, term_id, attempt_id)
      when is_binary(term_id) and is_binary(attempt_id) do
    with {:ok, state} <- academy_exam_state(character_or_id, term_id),
         {:ok, _term} <-
           Academy.expire_exam_attempt(state.term.id, state.phase, attempt_id),
         {:ok, academy_state} <- academy_state(state.character) do
      {:ok, academy_state}
    else
      {:error, _reason} = error -> error
    end
  end

  def expire_current_academy_exam(_character_or_id, _term_id, _attempt_id),
    do: {:error, :academy_exam_unavailable}

  def skip_current_academy_midterm(character_or_id, term_id) when is_binary(term_id) do
    with {:ok, state} <- academy_exam_state(character_or_id, term_id),
         true <- state.midterm_skippable? || {:error, :academy_exam_unavailable},
         {:ok, _term} <- Academy.skip_midterm(state.character.id, state.term.id) do
      academy_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def skip_current_academy_midterm(_character_or_id, _term_id),
    do: {:error, :academy_exam_unavailable}

  @doc """
  Loads the scoped character's research and professor-career records for the
  Academy of Sciences. Starting research, appointment, and course publication
  remain domain-owned commands below.
  """
  def academia_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      with :ok <- ensure_academy_available(state) do
        character = state.character
        professor = Academia.active_professor(character.id)
        emeritus_professor = Academia.emeritus_professor(character.id)
        professors = Academia.list_active_professors_for_realm(character.realm_id)
        recommendation_authority? = not is_nil(professor) or not is_nil(emeritus_professor)

        headship =
          case Academia.academy_head_state(character.realm_id, actor_id: character.id) do
            {:ok, headship} -> headship
            {:error, _reason} -> academy_headship_unavailable_state()
          end

        current_academy_head? =
          headship.term_active? && not is_nil(headship.head) &&
            headship.head.character_id == character.id

        headship_admission_candidates =
          if current_academy_head? do
            Academia.list_probation_graduates_for_realm(character.realm_id)
          else
            []
          end

        headship_charity_stipend_candidates =
          if current_academy_head? do
            Academia.list_charity_stipend_candidates_for_realm(character.realm_id)
          else
            []
          end

        headship_curriculum_courses =
          if current_academy_head? do
            Academy.list_seeded_courses_for_realm(character.realm_id)
          else
            []
          end

        charity_fund_balance =
          case Economy.charity_fund_account_for_realm(character.realm_id) do
            %EconomyAccount{current_balance: balance} -> balance
            nil -> 0
          end

        {:ok,
         %{
           character: character,
           location: state.current_location,
           active_project: Academia.active_project(character.id),
           projects: Academia.list_projects_for_character(character.id),
           professor: professor,
           emeritus_professor: emeritus_professor,
           recommendation_authority?: recommendation_authority?,
           advisor: Academia.active_advisor_for_student(character.id),
           professors: professors,
           headship: headship,
           headship_admission_candidates: headship_admission_candidates,
           headship_charity_stipend_candidates: headship_charity_stipend_candidates,
           headship_curriculum_courses: headship_curriculum_courses,
           charity_fund_balance: charity_fund_balance,
           academia_admitted?: Academia.academia_admitted?(character.id),
           advisor_pick_eligible?: Academia.advisor_pick_eligible?(character.id),
           advisor_match_available?: Enum.any?(professors, &(&1.character_id != character.id)),
           recommendation_candidates:
             if(recommendation_authority?,
               do: Academia.list_probation_graduates_for_realm(character.realm_id),
               else: []
             ),
           publications: Academia.list_publications(character.realm_id)
         }}
      end
    end
  end

  defp academy_headship_unavailable_state do
    %{
      realm: nil,
      head: nil,
      term_ends_at: nil,
      term_active?: false,
      eligible_professors: [],
      actor_is_professor?: false,
      can_open_election?: false,
      can_settle_election?: false,
      open_election: nil,
      last_result: nil
    }
  end

  def start_scoped_research(character_or_id, attrs) when is_map(attrs) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, project_kind} <- normalize_research_kind(Map.get(attrs, "project_kind")),
         {:ok, title} <- required_title(Map.get(attrs, "title")),
         {:ok, _result} <- Academia.start_project(state.character, project_kind, title) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def start_scoped_research(_character_or_id, _attrs), do: {:error, :research_unavailable}

  def appoint_scoped_professor(character_or_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _professor} <- Academia.appoint_professor(state.character) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Lets the scoped active professor retire while retaining emeritus letter authority."
  def retire_scoped_professor(character_or_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _retirement} <- Academia.retire_professor(state.character) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Opens the next due Academy Head election through the scoped professor."
  def open_scoped_academy_head_election(character_or_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _election} <- Academia.open_academy_head_election(state.character) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Records the scoped professor's one vote for a snapshotted Academy Head candidate."
  def vote_scoped_academy_head(character_or_id, candidate_character_id)
      when is_binary(candidate_character_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _vote} <- Academia.cast_academy_head_vote(state.character, candidate_character_id) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def vote_scoped_academy_head(_character_or_id, _candidate_character_id),
    do: {:error, :academy_head_election_unavailable}

  @doc "Settles a deadline-expired Academy Head election through the scoped professor."
  def settle_scoped_academy_head_election(character_or_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _resolution} <- Academia.settle_academy_head_election(state.character) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc "Lets the scoped current Academy Head admit a visible probation graduate."
  def admit_scoped_probation_as_academy_head(character_or_id, candidate_character_id)
      when is_binary(candidate_character_id) do
    with {:ok, state} <- academia_state(character_or_id),
         %{character: %Character{} = candidate} <-
           Enum.find(
             state.headship_admission_candidates,
             &(&1.character.id == candidate_character_id)
           ),
         {:ok, _admission} <- Academia.issue_academy_head_admission(state.character, candidate) do
      academia_state(state.character)
    else
      nil -> {:error, :academy_head_admission_candidate_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def admit_scoped_probation_as_academy_head(_character_or_id, _candidate_character_id),
    do: {:error, :academy_head_admission_candidate_unavailable}

  @doc "Lets the scoped current Academy Head pay one charity stipend to a visible grant student."
  def award_scoped_academy_head_charity_stipend(character_or_id, candidate_character_id, amount)
      when is_binary(candidate_character_id) and is_integer(amount) do
    with {:ok, state} <- academia_state(character_or_id),
         %{character: %Character{} = candidate} <-
           Enum.find(
             state.headship_charity_stipend_candidates,
             &(&1.character.id == candidate_character_id)
           ),
         {:ok, _stipend} <-
           Academia.award_academy_head_charity_stipend(state.character, candidate, amount) do
      academia_state(state.character)
    else
      nil -> {:error, :academy_head_charity_stipend_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def award_scoped_academy_head_charity_stipend(
        _character_or_id,
        _candidate_character_id,
        _amount
      ),
      do: {:error, :academy_head_charity_stipend_unavailable}

  @doc "Lets the scoped Academy Head move one visible seeded course to a legal term."
  def set_scoped_academy_head_curriculum_override(character_or_id, course_id, target_term)
      when is_binary(course_id) and is_integer(target_term) do
    with {:ok, state} <- academia_state(character_or_id),
         %{course: course} <-
           Enum.find(state.headship_curriculum_courses, &(&1.course.id == course_id)),
         {:ok, _override} <-
           Academia.set_academy_head_curriculum_override(state.character, course, target_term) do
      academia_state(state.character)
    else
      nil -> {:error, :academy_head_curriculum_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def set_scoped_academy_head_curriculum_override(_character_or_id, _course_id, _target_term),
    do: {:error, :academy_head_curriculum_unavailable}

  @doc "Lets the scoped Academy Head restore one visible seeded course's base schedule."
  def clear_scoped_academy_head_curriculum_override(character_or_id, course_id)
      when is_binary(course_id) do
    with {:ok, state} <- academia_state(character_or_id),
         %{course: course} <-
           Enum.find(state.headship_curriculum_courses, &(&1.course.id == course_id)),
         {:ok, _restored} <-
           Academia.clear_academy_head_curriculum_override(state.character, course) do
      academia_state(state.character)
    else
      nil -> {:error, :academy_head_curriculum_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def clear_scoped_academy_head_curriculum_override(_character_or_id, _course_id),
    do: {:error, :academy_head_curriculum_unavailable}

  def choose_scoped_advisor(character_or_id, professor_character_id)
      when is_binary(professor_character_id) do
    with {:ok, state} <- academia_state(character_or_id),
         %MMGO.Academia.Professor{} = professor <-
           Enum.find(state.professors, &(&1.character_id == professor_character_id)),
         {:ok, _advisor} <- Academia.set_advisor(state.character, professor.character) do
      academia_state(state.character)
    else
      nil -> {:error, :advisor_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def choose_scoped_advisor(_character_or_id, _professor_character_id),
    do: {:error, :advisor_unavailable}

  def match_scoped_advisor(character_or_id) do
    with {:ok, state} <- academia_state(character_or_id),
         {:ok, _advisor} <- Academia.match_advisor(state.character) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def write_scoped_admission_recommendation(character_or_id, candidate_character_id)
      when is_binary(candidate_character_id) do
    with {:ok, state} <- academia_state(character_or_id),
         true <- not is_nil(state.professor) || {:error, :professor_required},
         %{character: %Character{} = candidate} <-
           Enum.find(
             state.recommendation_candidates,
             &(&1.character.id == candidate_character_id)
           ),
         {:ok, _result} <- Academia.issue_admission_recommendation(state.character, candidate) do
      academia_state(state.character)
    else
      nil -> {:error, :recommendation_candidate_unavailable}
      false -> {:error, :professor_required}
      {:error, _reason} = error -> error
    end
  end

  def write_scoped_admission_recommendation(_character_or_id, _candidate_character_id),
    do: {:error, :recommendation_candidate_unavailable}

  def publish_scoped_course(character_or_id, attrs) when is_map(attrs) do
    with {:ok, state} <- academia_state(character_or_id),
         true <- not is_nil(state.professor) || {:error, :professor_required},
         {:ok, title} <- required_title(Map.get(attrs, "title")),
         {:ok, track} <- normalize_course_track(Map.get(attrs, "track")),
         {:ok, school} <- normalize_course_school(Map.get(attrs, "school")),
         {:ok, summary} <- optional_summary(Map.get(attrs, "summary")),
         {:ok, _publication} <-
           Academia.publish_course(state.character, title,
             track: track,
             school: school,
             syllabus: %{"summary" => summary},
             metadata: %{"summary" => summary}
           ) do
      academia_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def publish_scoped_course(_character_or_id, _attrs), do: {:error, :professor_required}

  @doc """
  Loads one public thesis defense for the scoped character. The ceremony is
  visible only inside the actor's own realm and while they are physically in a
  city; vote authority remains derived from the actor's persisted professor
  record and frozen commission membership.
  """
  def thesis_defense_state(character_or_id, project_id) when is_binary(project_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      with :ok <- ensure_academy_available(state),
           {:ok, defense} <- Academia.thesis_defense(project_id),
           true <-
             defense.project.realm_id == state.character.realm_id ||
               {:error, :thesis_defense_not_found} do
        advisor = Academia.active_advisor_for_student(defense.candidate.id)
        panel_ids = Enum.map(defense.panel, & &1.id)
        actor_vote = Map.get(defense.votes, state.character.id)

        {:ok,
         %{
           character: state.character,
           location: state.current_location,
           project: defense.project,
           candidate: defense.candidate,
           opens_at: defense.opens_at,
           closes_at: defense.closes_at,
           panel:
             Enum.map(defense.panel, fn panelist ->
               %{
                 character: panelist,
                 role:
                   if(advisor && advisor.professor_character_id == panelist.id,
                     do: :advisor,
                     else: :panelist
                   ),
                 vote: Map.get(defense.votes, panelist.id)
               }
             end),
           commission_ready?: length(panel_ids) == 3,
           votes_cast: map_size(defense.votes),
           actor_vote: actor_vote,
           can_vote?:
             state.character.id in panel_ids and is_nil(actor_vote) and
               thesis_vote_window_open?(defense.opens_at, defense.closes_at),
           outcome: Map.get(defense.project.metadata || %{}, "defense_outcome"),
           attempt_history: defense_attempt_history(defense.project)
         }}
      end
    end
  end

  def thesis_defense_state(_character_or_id, _project_id), do: {:error, :thesis_defense_not_found}

  def submit_scoped_thesis_vote(character_or_id, project_id, vote)
      when is_binary(project_id) and is_binary(vote) do
    with {:ok, state} <- thesis_defense_state(character_or_id, project_id),
         {:ok, vote} <- normalize_thesis_vote(vote),
         true <- state.can_vote? || {:error, :thesis_vote_unavailable},
         {:ok, _project} <-
           Academia.submit_defense_vote(state.project.id, state.character.id, vote) do
      thesis_defense_state(state.character, state.project.id)
    else
      {:error, _reason} = error -> error
    end
  end

  def submit_scoped_thesis_vote(_character_or_id, _project_id, _vote),
    do: {:error, :thesis_vote_unavailable}

  @doc "Returns public realm clubs plus the scoped character's own membership state."
  def clubs_state(character_or_id, selected_club_id \\ nil) do
    with {:ok, character} <- normalize_character(character_or_id) do
      state = state_for_character(character)

      with :ok <- ensure_academy_available(state) do
        character = state.character
        realm_clubs = Clubs.list_active_clubs(character.realm_id)
        member_clubs = Clubs.list_clubs_for_character(character.id)

        selected_club =
          case selected_club_id do
            nil -> nil
            club_id -> Enum.find(realm_clubs, &(&1.id == club_id))
          end

        if is_binary(selected_club_id) and is_nil(selected_club) do
          {:error, :club_not_found}
        else
          selected_club = if(selected_club, do: Clubs.get_club!(selected_club.id), else: nil)

          selected_membership =
            if selected_club do
              Enum.find(selected_club.memberships, &(&1.character_id == character.id))
            end

          club_permissions =
            if selected_club && selected_membership do
              Clubs.membership_permissions(selected_club, selected_membership)
            else
              []
            end

          club_governance =
            if selected_club do
              Clubs.governance_state(selected_club, character.id)
            else
              nil
            end

          president? = not is_nil(selected_membership) and Clubs.president?(selected_membership)

          {:ok,
           %{
             character: character,
             location: state.current_location,
             realm_clubs: realm_clubs,
             member_clubs: member_clubs,
             pending_invitations: Clubs.pending_invitations_for_character(character.id),
             selected_club: selected_club,
             selected_membership: selected_membership,
             selected_events:
               if(selected_club, do: Clubs.list_events_for_club(selected_club.id), else: []),
             duel_ladder:
               if(selected_club && selected_club.club_type == :dueling,
                 do: Clubs.list_duel_ladder(selected_club),
                 else: []
               ),
             research_contribution:
               if(
                 selected_club && selected_club.club_type == :research && selected_membership,
                 do: Clubs.research_contribution(selected_membership),
                 else: nil
               ),
             expedition_plan:
               if(
                 selected_club && selected_club.club_type == :expedition_planning &&
                   selected_membership,
                 do: Clubs.expedition_plan_contribution(selected_membership),
                 else: nil
               ),
             social_connections:
               if(
                 selected_club && selected_club.club_type == :general_interest &&
                   selected_membership,
                 do: Clubs.friendship_summary(selected_membership),
                 else: nil
               ),
             # `leader?` remains as a compatibility alias for existing club
             # callers; product-facing state calls the office a president.
             leader?: president?,
             president?: president?,
             can_invite?: "invite_members" in club_permissions,
             can_schedule_events?: "schedule_events" in club_permissions,
             can_manage_officers?: "manage_officers" in club_permissions,
             can_manage?:
               "invite_members" in club_permissions or "schedule_events" in club_permissions or
                 "manage_officers" in club_permissions,
             club_governance: club_governance
           }}
        end
      end
    end
  end

  @doc "Loads one realm-local club event and the scoped actor's attendance authority."
  def club_event_state(character_or_id, event_id) when is_binary(event_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %ClubEvent{} = requested_event <- Repo.get(ClubEvent, event_id),
         true <- requested_event.realm_id == character.realm_id || {:error, :club_event_not_found},
         {:ok, state} <- clubs_state(character, requested_event.club_id),
         %ClubEvent{} = event <- Enum.find(state.selected_events, &(&1.id == requested_event.id)) do
      attendance = Enum.find(event.attendances || [], &(&1.character_id == state.character.id))

      duel_challenges =
        if event.kind == :duel_tournament do
          Clubs.list_duel_challenges(event)
        else
          []
        end

      duel_opponents =
        if event.kind == :duel_tournament and not is_nil(attendance) and
             not is_nil(state.selected_membership) do
          Clubs.list_duel_opponents(event, state.character.id)
        else
          []
        end

      {:ok,
       %{
         character: state.character,
         location: state.location,
         club: state.selected_club,
         membership: state.selected_membership,
         event: event,
         attendance: attendance,
         duel_opponents: duel_opponents,
         incoming_duel_challenges:
           Enum.filter(
             duel_challenges,
             &(&1["status"] == "pending" and &1["opponent_character_id"] == state.character.id)
           ),
         outgoing_duel_challenges:
           Enum.filter(
             duel_challenges,
             &(&1["status"] == "pending" and &1["challenger_character_id"] == state.character.id)
           ),
         accepted_duel_challenges:
           Enum.filter(
             duel_challenges,
             &(&1["status"] == "accepted" and
                 state.character.id in [
                   &1["challenger_character_id"],
                   &1["opponent_character_id"]
                 ])
           ),
         can_attend?:
           not is_nil(state.selected_membership) and is_nil(attendance) and
             event.status in [:scheduled, :active]
       }}
    else
      nil -> {:error, :club_event_not_found}
      false -> {:error, :club_event_not_found}
      {:error, _reason} = error -> error
    end
  end

  def club_event_state(_character_or_id, _event_id), do: {:error, :club_event_not_found}

  def challenge_scoped_club_duel(character_or_id, event_id, opponent_character_id)
      when is_binary(event_id) and is_binary(opponent_character_id) do
    with {:ok, state} <- club_event_state(character_or_id, event_id),
         %Character{} = opponent <-
           Enum.find(state.duel_opponents, &(&1.id == opponent_character_id)),
         {:ok, _result} <- Clubs.challenge_duel(state.event, state.character, opponent) do
      club_event_state(state.character, event_id)
    else
      nil -> {:error, :club_duel_opponent_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def challenge_scoped_club_duel(_character_or_id, _event_id, _opponent_character_id),
    do: {:error, :club_duel_opponent_unavailable}

  def accept_scoped_club_duel(character_or_id, event_id, challenge_id)
      when is_binary(event_id) and is_binary(challenge_id) do
    with {:ok, state} <- club_event_state(character_or_id, event_id),
         challenge when not is_nil(challenge) <-
           Enum.find(state.incoming_duel_challenges, &(&1["id"] == challenge_id)),
         {:ok, %{combat: combat}} <-
           Clubs.accept_duel_challenge(state.event, challenge["id"], state.character) do
      {:ok, %{combat: combat}}
    else
      nil -> {:error, :club_duel_challenge_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def accept_scoped_club_duel(_character_or_id, _event_id, _challenge_id),
    do: {:error, :club_duel_challenge_unavailable}

  def reject_scoped_club_duel(character_or_id, event_id, challenge_id)
      when is_binary(event_id) and is_binary(challenge_id) do
    with {:ok, state} <- club_event_state(character_or_id, event_id),
         challenge when not is_nil(challenge) <-
           Enum.find(state.incoming_duel_challenges, &(&1["id"] == challenge_id)),
         {:ok, _event} <-
           Clubs.reject_duel_challenge(state.event, challenge["id"], state.character) do
      club_event_state(state.character, event_id)
    else
      nil -> {:error, :club_duel_challenge_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def reject_scoped_club_duel(_character_or_id, _event_id, _challenge_id),
    do: {:error, :club_duel_challenge_unavailable}

  def create_scoped_club(character_or_id, attrs) when is_map(attrs) do
    with {:ok, state} <- clubs_state(character_or_id),
         {:ok, _result} <- Clubs.create_club(state.character, attrs) do
      clubs_state(state.character)
    else
      {:error, _reason} = error -> error
    end
  end

  def create_scoped_club(_character_or_id, _attrs), do: {:error, :club_unavailable}

  def invite_to_scoped_club(character_or_id, club_id, handle)
      when is_binary(club_id) and is_binary(handle) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         true <- state.can_invite? || {:error, :not_club_manager},
         %Character{} = invitee <-
           Accounts.get_character_by_handle(state.character.realm_id, String.trim(handle)),
         {:ok, _result} <- Clubs.invite_member(club, state.character, invitee) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_invitee_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_club_manager}
    end
  end

  def invite_to_scoped_club(_character_or_id, _club_id, _handle),
    do: {:error, :club_invitee_not_found}

  def accept_scoped_club_invitation(character_or_id, invitation_id)
      when is_binary(invitation_id) do
    with {:ok, state} <- clubs_state(character_or_id),
         %ClubInvitation{} = invitation <-
           Enum.find(state.pending_invitations, &(&1.id == invitation_id)),
         {:ok, %{club: club}} <- Clubs.accept_invitation(invitation, state.character) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_invitation_not_found}
      {:error, _reason} = error -> error
    end
  end

  def accept_scoped_club_invitation(_character_or_id, _invitation_id),
    do: {:error, :club_invitation_not_found}

  def reject_scoped_club_invitation(character_or_id, invitation_id)
      when is_binary(invitation_id) do
    with {:ok, state} <- clubs_state(character_or_id),
         %ClubInvitation{} = invitation <-
           Enum.find(state.pending_invitations, &(&1.id == invitation_id)),
         {:ok, _invitation} <- Clubs.reject_invitation(invitation, state.character) do
      clubs_state(state.character)
    else
      nil -> {:error, :club_invitation_not_found}
      {:error, _reason} = error -> error
    end
  end

  def reject_scoped_club_invitation(_character_or_id, _invitation_id),
    do: {:error, :club_invitation_not_found}

  def leave_scoped_club(character_or_id, club_id) when is_binary(club_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         %ClubMembership{} <- state.selected_membership,
         {:ok, _club} <- Clubs.leave_club(club, state.character) do
      clubs_state(state.character)
    else
      nil -> {:error, :club_membership_not_found}
      {:error, _reason} = error -> error
    end
  end

  def leave_scoped_club(_character_or_id, _club_id), do: {:error, :club_membership_not_found}

  def schedule_scoped_club_event(character_or_id, club_id, attrs)
      when is_binary(club_id) and is_map(attrs) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         true <- state.can_schedule_events? || {:error, :not_club_manager},
         {:ok, _event} <- Clubs.create_event(club, state.character, attrs) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_not_found}
      {:error, _reason} = error -> error
      false -> {:error, :not_club_manager}
    end
  end

  def schedule_scoped_club_event(_character_or_id, _club_id, _attrs),
    do: {:error, :club_not_found}

  @doc "Appoints a selected active club member as an officer through the scoped president."
  def appoint_scoped_club_officer(character_or_id, club_id, target_character_id)
      when is_binary(club_id) and is_binary(target_character_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         true <- state.can_manage_officers? || {:error, :not_club_president},
         %Character{} = target <- club_member_character(club, target_character_id),
         {:ok, _result} <- Clubs.appoint_officer(club, state.character, target) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_officer_candidate_unavailable}
      false -> {:error, :not_club_president}
      {:error, _reason} = error -> error
    end
  end

  def appoint_scoped_club_officer(_character_or_id, _club_id, _target_character_id),
    do: {:error, :club_officer_candidate_unavailable}

  @doc "Returns a selected officer to the ordinary club-member role through the scoped president."
  def revoke_scoped_club_officer(character_or_id, club_id, target_character_id)
      when is_binary(club_id) and is_binary(target_character_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         true <- state.can_manage_officers? || {:error, :not_club_president},
         %Character{} = target <- club_member_character(club, target_character_id),
         {:ok, _result} <- Clubs.revoke_officer(club, state.character, target) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_officer_candidate_unavailable}
      false -> {:error, :not_club_president}
      {:error, _reason} = error -> error
    end
  end

  def revoke_scoped_club_officer(_character_or_id, _club_id, _target_character_id),
    do: {:error, :club_officer_candidate_unavailable}

  @doc "Opens one member-snapshot election for a club president."
  def nominate_scoped_club_president(character_or_id, club_id, candidate_character_id)
      when is_binary(club_id) and is_binary(candidate_character_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         %ClubMembership{} <- state.selected_membership,
         %Character{} = candidate <- club_member_character(club, candidate_character_id),
         {:ok, _result} <- Clubs.open_president_election(club, state.character, candidate) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_president_candidate_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def nominate_scoped_club_president(_character_or_id, _club_id, _candidate_character_id),
    do: {:error, :club_president_candidate_unavailable}

  @doc "Records the scoped member's immutable vote in a club presidency election."
  def vote_for_scoped_club_president(character_or_id, club_id, proposal_id, vote)
      when is_binary(club_id) and is_binary(proposal_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %Club{} = club <- state.selected_club,
         %ClubMembership{} <- state.selected_membership,
         {:ok, vote} <- normalize_club_vote(vote),
         {:ok, _result} <- Clubs.cast_president_vote(club, state.character, proposal_id, vote) do
      clubs_state(state.character, club.id)
    else
      nil -> {:error, :club_president_election_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def vote_for_scoped_club_president(_character_or_id, _club_id, _proposal_id, _vote),
    do: {:error, :club_president_election_unavailable}

  def attend_scoped_club_event(character_or_id, club_id, event_id)
      when is_binary(club_id) and is_binary(event_id) do
    with {:ok, state} <- clubs_state(character_or_id, club_id),
         %ClubMembership{} <- state.selected_membership,
         %ClubEvent{} = event <- Enum.find(state.selected_events, &(&1.id == event_id)),
         {:ok, _attendance} <- Clubs.attend_event(event, state.character) do
      clubs_state(state.character, club_id)
    else
      nil -> {:error, :club_event_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def attend_scoped_club_event(_character_or_id, _club_id, _event_id),
    do: {:error, :club_event_unavailable}

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
         {:ok, duel} <- PVP.accept_duel(duel, opponent),
         {:ok, state} <- duel_combat_state_for(challenger, duel),
         %Participant{} = opponent_participant <-
           Enum.find(state.combat.participants, &(&1.character_id == opponent.id)),
         {:ok, _action} <-
           CombatContext.submit_action(state.combat, opponent_participant.id, %{
             action_type: :wait
           }) do
      duel_combat_state_for(challenger, duel)
    else
      nil -> {:error, :opponent_not_found}
      {:error, reason} -> {:error, reason}
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
  Loads the browser-facing read model for one combat visible to the scoped
  character. A combat ID is only a routing hint: participants receive command
  state, while same-location duel/overworld observers receive a read-only view.
  """
  def combat_state(character_or_id, combat_id) when is_binary(combat_id) do
    with {:ok, character} <- normalize_character(character_or_id) do
      case CombatContext.get_combat_for_character(combat_id, character.id) do
        %Combat{} = combat ->
          combat_state_for(character, combat)

        nil ->
          case CombatContext.get_combat(combat_id) do
            %Combat{} = combat ->
              if spectator_allowed?(character, combat) do
                {:ok, spectator_combat_state_for(character, combat)}
              else
                {:error, :combat_not_found}
              end

            nil ->
              {:error, :combat_not_found}
          end
      end
    end
  end

  def combat_state(_character_or_id, _combat_id), do: {:error, :combat_not_found}

  @doc """
  Loads the scoped character's active combat, if they have one.
  """
  def active_combat_state(character_or_id) do
    with {:ok, character} <- normalize_character(character_or_id),
         %Combat{} = combat <- CombatContext.active_combat_for_character(character.id) do
      combat_state_for(character, combat)
    else
      nil -> {:error, :no_active_combat}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Seals an action for the scoped character in their own combat and returns a
  fresh read model. Participant IDs, targets, spell effects, and item costs are
  deliberately resolved inside `MMGO.Combat`, never accepted from the browser.
  """
  def submit_combat_action(character_or_id, combat_id, attrs)
      when is_binary(combat_id) and is_map(attrs) do
    with {:ok, state} <- combat_state(character_or_id, combat_id),
         true <- not state.spectator? || {:error, :spectator},
         true <- state.action_open? || {:error, :turn_not_open},
         {:ok, _action} <- CombatContext.submit_action(state.combat, state.participant.id, attrs) do
      combat_state(character_or_id, combat_id)
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :turn_not_open}
    end
  end

  def submit_combat_action(_character_or_id, _combat_id, _attrs), do: {:error, :invalid_action}

  @doc """
  Seals a scope-derived flee action. Flee legality is rechecked by the combat
  snapshot boundary from live carried weight; it never acts as client-side
  navigation or a duel cancellation/refund.
  """
  def flee_combat(character_or_id, combat_id) when is_binary(combat_id) do
    submit_combat_action(character_or_id, combat_id, %{"action_type" => "flee"})
  end

  def flee_combat(_character_or_id, _combat_id), do: {:error, :invalid_action}

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
  Active duels cannot be cancelled or refunded. The scoped character must use
  the real combat flee action, which settles the wager to the opponent.
  """
  def cancel_active_duel(character_or_id) do
    with {:ok, _state} <- active_duel_combat_state(character_or_id) do
      {:error, :active_duel_requires_flee}
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

  defp reload_base_character(%Character{id: character_id}) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_base_character(character_id) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_base_character(_character), do: {:error, :not_found}

  defp reload_activity_character(%Character{id: character_id}) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_activity_character(character_id) when is_binary(character_id),
    do: load_character(character_id)

  defp reload_activity_character(_character), do: {:error, :not_found}

  defp authorize_activity_event(%EventInstance{} = event, %Character{} = character) do
    cond do
      event.character_id != character.id ->
        {:error, :event_not_found}

      event.realm_id != character.realm_id ->
        {:error, :event_not_found}

      event.location_id != character.current_location_id ->
        {:error, :event_not_current}

      event.status != :active ->
        {:error, :event_not_active}

      not is_nil(Travel.active_journey(character.id)) ->
        {:error, :travelling}

      true ->
        :ok
    end
  end

  defp activity_action(action_key) when is_binary(action_key) do
    Map.get(
      @activity_actions,
      action_key,
      %{type: :notice, message: "Это действие пока не может быть выполнено здесь."}
    )
  end

  defp activity_action(_action_key),
    do: %{type: :notice, message: "Это действие пока не может быть выполнено здесь."}

  defp sort_event_options(options) do
    Enum.sort_by(options, fn option -> {option.position, option.inserted_at} end)
  end

  defp nearby_stationary_characters(%Character{} = character, %Location{} = location) do
    Accounts.list_active_characters_at_location(character.realm_id, location.id,
      exclude_character_id: character.id
    )
  end

  defp find_nearby_character(character, location, target_character_id) do
    character
    |> nearby_stationary_characters(location)
    |> Enum.find(&(&1.id == target_character_id))
  end

  defp empty_supply do
    %{
      member_count: 0,
      daily_food_demand: 0,
      total_food_units: 0,
      projected_days: 0,
      total_carried_weight: 0,
      total_carry_capacity: 0,
      encumbered?: false,
      members: []
    }
  end

  defp dungeon_run_state(%Character{} = character, nil, entry_dungeon, party) do
    %{
      run: nil,
      dungeon: entry_dungeon,
      current_node: nil,
      current_encounter: nil,
      active_combat: nil,
      active_extraction: nil,
      nodes: [],
      reachable_nodes: [],
      available_resources: [],
      available_loot: [],
      can_enter?:
        not is_nil(entry_dungeon) and not is_nil(party) and
          party.leader_character_id == character.id,
      can_start_combat?: false,
      can_avoid_encounter?: false,
      can_extract?: false,
      can_return_ritual?: false,
      return_ritual: Dungeons.return_ritual_loadout(character)
    }
  end

  defp dungeon_run_state(%Character{} = character, %Run{} = run, _entry_dungeon, _party) do
    dungeon = Dungeons.get_dungeon!(run.dungeon_id)
    nodes = dungeon |> dungeon_nodes() |> Enum.sort_by(&{&1.floor_id, &1.y, &1.x, &1.name})
    nodes_by_id = Map.new(nodes, &{&1.id, &1})
    current_node = Map.get(nodes_by_id, run.current_node_id, run.current_node)

    link_states =
      dungeon.id
      |> Dungeons.list_link_states()
      |> Map.new(&{&1.link_id, &1.status})

    reachable_nodes =
      dungeon.id
      |> Dungeons.list_links_for_dungeon()
      |> reachable_dungeon_nodes(link_states, run.current_node_id, nodes_by_id)

    current_encounter = Dungeons.current_encounter_for_run(run.id)

    active_combat =
      case current_encounter do
        %Encounter{combat_id: combat_id} when is_binary(combat_id) ->
          CombatContext.get_combat(combat_id)

        _other ->
          nil
      end

    active_extraction = Dungeons.active_extraction(run.id)
    return_ritual = Dungeons.return_ritual_loadout(character)

    available_resources =
      run.id
      |> Dungeons.list_resource_caches_for_run()
      |> Enum.filter(&(&1.node_id == run.current_node_id and &1.status == :available))

    available_loot =
      run.id
      |> Dungeons.list_loot_drops_for_run()
      |> Enum.filter(&(&1.node_id == run.current_node_id and &1.status == :available))

    node_states = Map.new(run.node_states, &{&1.node_id, &1})

    known_node_ids =
      node_states
      |> Map.keys()
      |> Kernel.++(Enum.map(reachable_nodes, & &1.node.id))
      |> MapSet.new()

    node_rows =
      nodes
      |> Enum.filter(&MapSet.member?(known_node_ids, &1.id))
      |> Enum.map(fn node ->
        %{
          node: node,
          node_state: Map.get(node_states, node.id),
          current?: node.id == run.current_node_id,
          reachable?: Enum.any?(reachable_nodes, &(&1.node.id == node.id))
        }
      end)

    encounter_resolved? =
      is_nil(current_encounter) or current_encounter.status in [:cleared, :avoided]

    can_extract? =
      is_nil(active_extraction) and encounter_resolved? and
        current_node.kind in [:entrance, :stairs_up, :exit]

    %{
      run: run,
      dungeon: dungeon,
      current_node: current_node,
      current_encounter: current_encounter,
      active_combat: active_combat,
      active_extraction: active_extraction,
      return_ritual: return_ritual,
      nodes: node_rows,
      reachable_nodes:
        if(encounter_resolved? and is_nil(active_extraction), do: reachable_nodes, else: []),
      available_resources: available_resources,
      available_loot: available_loot,
      can_enter?: false,
      can_start_combat?:
        match?(%Encounter{status: :pending, combat_id: nil}, current_encounter) and
          is_nil(active_extraction),
      can_avoid_encounter?:
        match?(%Encounter{status: :pending}, current_encounter) and is_nil(active_extraction),
      can_extract?: can_extract?,
      can_return_ritual?:
        is_nil(active_extraction) and encounter_resolved? and
          return_ritual.wizardry_specialist? and return_ritual.prepared?
    }
  end

  defp dungeon_nodes(%Dungeon{floors: floors}) do
    floors
    |> Enum.flat_map(& &1.nodes)
  end

  defp dungeon_atmosphere_event(%{current_encounter: %Encounter{status: status}})
       when status in [:pending, :active],
       do: :dungeon_encounter

  defp dungeon_atmosphere_event(_state), do: nil

  defp reachable_dungeon_nodes(links, link_states, current_node_id, nodes_by_id) do
    links
    |> Enum.filter(fn link -> Map.get(link_states, link.id, :active) == :active end)
    |> Enum.flat_map(fn link ->
      cond do
        link.from_node_id == current_node_id ->
          [%{node_id: link.to_node_id, link: link}]

        link.bidirectional and link.to_node_id == current_node_id ->
          [%{node_id: link.from_node_id, link: link}]

        true ->
          []
      end
    end)
    |> Enum.map(fn %{node_id: node_id, link: link} ->
      %{node: Map.fetch!(nodes_by_id, node_id), travel_cost: link.travel_cost}
    end)
    |> Enum.sort_by(&{&1.node.y, &1.node.x, &1.node.name})
  end

  defp positive_dungeon_quantity(quantity) when is_integer(quantity) and quantity > 0,
    do: {:ok, quantity}

  defp positive_dungeon_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(quantity) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> {:error, :dungeon_resource_unavailable}
    end
  end

  defp positive_dungeon_quantity(_quantity), do: {:error, :dungeon_resource_unavailable}

  defp dungeon_state_after_combat(character) do
    case dungeon_state(character) do
      {:ok, state} -> state
      {:error, _reason} -> nil
    end
  end

  defp academy_valedictorian_honor(enrollment) do
    %{
      enrollment_id: enrollment.id,
      program_type: enrollment.program_type,
      title: Academy.valedictorian_title(enrollment),
      hall_of_fame_until: Academy.hall_of_fame_until(enrollment)
    }
  end

  defp academy_academic_title(enrollment) do
    %{
      enrollment_id: enrollment.id,
      program_type: enrollment.program_type,
      title: Academy.academic_title(enrollment)
    }
  end

  defp academy_program_options(character, enrollment) do
    cond do
      not is_nil(enrollment) ->
        []

      not Academy.basic_education_completed?(character.id) ->
        [%{code: "basic_education", label: "Начать базовое образование"}]

      not Academy.program_completed?(character.id, :academy_core) ->
        [%{code: "academy_core", label: "Поступить на основной путь"}]

      true ->
        [
          if(Academy.active_specialization(character.id),
            do: %{code: "academy_core", label: "Пройти Academy Core заново (переподготовка)"}
          ),
          if(not Academy.program_completed?(character.id, :extended_study),
            do: %{code: "extended_study", label: "Продолжить углублённое обучение"}
          ),
          if(not Academy.program_completed?(character.id, :academia),
            do: %{code: "academia", label: "Поступить в Академию наук"}
          )
        ]
        |> Enum.reject(&is_nil/1)
    end
  end

  defp start_scoped_academy_program(%Character{} = character, attrs) do
    program_type = Map.get(attrs, "program_type") || Map.get(attrs, :program_type)

    case program_type do
      "basic_education" ->
        Academy.begin_basic_education(character)

      "academy_core" ->
        start_scoped_academy_track(character, attrs)

      "extended_study" ->
        Academy.start_extended_study(character)

      "academia" ->
        Academy.start_academia(character)

      _other ->
        {:error, :academy_program_unavailable}
    end
  end

  defp start_scoped_academy_track(%Character{} = character, attrs) do
    track = Map.get(attrs, "track") || Map.get(attrs, :track)

    case track do
      "wizardry" ->
        Academy.start_academy_track(character, :wizardry, %{
          primary_school: Map.get(attrs, "primary_school") || Map.get(attrs, :primary_school),
          secondary_school:
            Map.get(attrs, "secondary_school") || Map.get(attrs, :secondary_school)
        })

      "alchemy" ->
        Academy.start_academy_track(character, :alchemy, %{})

      "mastery" ->
        Academy.start_academy_track(character, :mastery, %{})

      _other ->
        {:error, :academy_program_unavailable}
    end
  end

  defp ensure_overworld_available(%{active_journey: %Journey{}}), do: {:error, :travelling}
  defp ensure_overworld_available(%{current_location: nil}), do: {:error, :location_not_found}
  defp ensure_overworld_available(_state), do: :ok

  defp ensure_duel_lobby_available(%{active_journey: %Journey{}}), do: {:error, :travelling}
  defp ensure_duel_lobby_available(%{current_location: nil}), do: {:error, :location_not_found}
  defp ensure_duel_lobby_available(_state), do: :ok

  defp ensure_base_available(%{active_journey: %Journey{}}), do: {:error, :travelling}
  defp ensure_base_available(%{current_location: nil}), do: {:error, :location_not_found}
  defp ensure_base_available(_state), do: :ok

  defp ensure_academy_available(%{active_journey: %Journey{}}),
    do: {:error, :academy_location_unavailable}

  defp ensure_academy_available(%{current_location: nil}),
    do: {:error, :academy_location_unavailable}

  defp ensure_academy_available(%{current_location: %Location{kind: :city}}), do: :ok

  defp ensure_academy_available(_state), do: {:error, :academy_location_unavailable}

  defp thesis_vote_window_open?(%DateTime{} = opens_at, %DateTime{} = closes_at) do
    now = DateTime.utc_now()
    DateTime.compare(now, opens_at) != :lt and DateTime.compare(now, closes_at) != :gt
  end

  defp thesis_vote_window_open?(_opens_at, _closes_at), do: false

  defp normalize_thesis_vote("accept"), do: {:ok, :accept}
  defp normalize_thesis_vote("accept_with_revisions"), do: {:ok, :accept_with_revisions}
  defp normalize_thesis_vote("reject"), do: {:ok, :reject}
  defp normalize_thesis_vote(_vote), do: {:error, :thesis_vote_unavailable}

  defp normalize_research_kind("spell"), do: {:ok, :spell}
  defp normalize_research_kind("potion"), do: {:ok, :potion}
  defp normalize_research_kind("tool"), do: {:ok, :tool}
  defp normalize_research_kind("thesis"), do: {:ok, :thesis}
  defp normalize_research_kind(_kind), do: {:error, :research_unavailable}

  defp normalize_course_track(nil), do: {:ok, nil}
  defp normalize_course_track(""), do: {:ok, nil}
  defp normalize_course_track("wizardry"), do: {:ok, :wizardry}
  defp normalize_course_track("alchemy"), do: {:ok, :alchemy}
  defp normalize_course_track("mastery"), do: {:ok, :mastery}
  defp normalize_course_track(_track), do: {:error, :course_publication_unavailable}

  defp normalize_course_school(nil), do: {:ok, nil}
  defp normalize_course_school(""), do: {:ok, nil}
  defp normalize_course_school("fire"), do: {:ok, :fire}
  defp normalize_course_school("water"), do: {:ok, :water}
  defp normalize_course_school("earth"), do: {:ok, :earth}
  defp normalize_course_school("air"), do: {:ok, :air}
  defp normalize_course_school("life"), do: {:ok, :life}
  defp normalize_course_school("death"), do: {:ok, :death}
  defp normalize_course_school("chaos"), do: {:ok, :chaos}
  defp normalize_course_school("order"), do: {:ok, :order}
  defp normalize_course_school(_school), do: {:error, :course_publication_unavailable}

  defp required_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> {:error, :research_title_required}
      normalized -> {:ok, normalized}
    end
  end

  defp required_title(_title), do: {:error, :research_title_required}

  defp optional_summary(nil), do: {:ok, ""}

  defp optional_summary(summary) when is_binary(summary), do: {:ok, String.trim(summary)}
  defp optional_summary(_summary), do: {:error, :course_publication_unavailable}

  defp defense_attempt_history(%{metadata: metadata}) do
    case Map.get(metadata || %{}, "defense_attempt_history", []) do
      history when is_list(history) -> history
      _other -> []
    end
  end

  defp ensure_trade_available(%{active_journey: %Journey{}}), do: {:error, :travelling}
  defp ensure_trade_available(%{current_location: nil}), do: {:error, :location_not_found}
  defp ensure_trade_available(_state), do: :ok

  defp base_rest_available?(%{starving?: starving?, health_drain: health_drain}, storage_items) do
    (starving? or health_drain > 0) and Enum.any?(storage_items, &stored_food?/1)
  end

  defp stored_food?(%StorageItem{item_template: %{item_type: :food, nutrition_units: nutrition}})
       when nutrition > 0,
       do: true

  defp stored_food?(_storage_item), do: false

  defp material_availability(requirements, carried_items) do
    Enum.map(requirements, fn requirement ->
      available =
        carried_items
        |> Enum.filter(&(&1.item_template.code == requirement.code))
        |> Enum.reduce(0, fn item, total -> total + Inventory.available_quantity(item) end)

      Map.put(requirement, :available, available)
    end)
  end

  defp selected_base(active_bases, %Character{} = character, nil) do
    case Enum.find(active_bases, &(&1.owner_character_id == character.id)) do
      %Base{} = owned_base ->
        {:ok, owned_base}

      nil ->
        case active_bases do
          [%Base{} = only_base] -> {:ok, only_base}
          _other -> {:ok, nil}
        end
    end
  end

  defp selected_base(active_bases, _character, selected_base_id)
       when is_binary(selected_base_id) do
    case Enum.find(active_bases, &(&1.id == selected_base_id)) do
      %Base{} = base -> {:ok, base}
      nil -> {:error, :base_not_accessible}
    end
  end

  defp active_base_choices(active_bases, %Character{} = character) do
    Enum.map(active_bases, fn base ->
      %{
        id: base.id,
        name: base.name,
        direct_owner?: base.owner_character_id == character.id,
        storage_capacity: base.storage_weight_capacity
      }
    end)
  end

  defp base_ownership_state(%Base{} = base, %Character{} = character) do
    ownership = Bases.ownership_state(base)
    member_organizations = Organizations.list_organizations_for_character(character.id)

    organizations_by_id =
      ownership.organization_share_bps
      |> Map.keys()
      |> Enum.map(&safe_get_organization/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{&1.id, &1})

    organization_shares =
      ownership.organization_share_bps
      |> Enum.map(fn {organization_id, share_bps} ->
        organization = Map.get(organizations_by_id, organization_id)

        %{
          organization_id: organization_id,
          organization_name:
            if(organization, do: organization.name, else: "Архивная организация"),
          share_bps: share_bps,
          active?: not is_nil(organization) and organization.status == :active
        }
      end)
      |> Enum.sort_by(& &1.organization_name)

    manageable_organizations =
      member_organizations
      |> Enum.filter(&organization_member_has_permission?(&1, character.id, "manage_treasury"))
      |> Enum.map(&%{id: &1.id, name: &1.name})

    %{
      is_owner?: base.owner_character_id == character.id,
      via_organization?: base.owner_character_id != character.id,
      owner_share_bps: ownership.owner_share_bps,
      organization_shares: organization_shares,
      manageable_organizations: manageable_organizations
    }
  end

  defp organization_member_has_permission?(organization, character_id, permission) do
    case Enum.find(organization.memberships, &(&1.character_id == character_id)) do
      %{role: %{permissions: role_permissions}} when is_list(role_permissions) ->
        permission in role_permissions

      _other ->
        false
    end
  end

  defp current_active_base(character_or_id) do
    with {:ok, character} <- reload_base_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_base_available(state),
         %Base{} = base <- Bases.active_base_at_location(character.id, state.current_location.id) do
      {:ok, state.character, Bases.get_base!(base.id)}
    else
      nil -> {:error, :active_base_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp current_selected_base(character_or_id, selected_base_id)
       when is_binary(selected_base_id) do
    with {:ok, character} <- reload_base_character(character_or_id),
         state = state_for_character(character),
         :ok <- ensure_base_available(state),
         %Base{} = base <-
           Bases.accessible_active_base_at_location(
             state.character,
             state.current_location.id,
             selected_base_id
           ) do
      {:ok, state.character, Bases.get_base!(base.id)}
    else
      nil -> {:error, :active_base_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp current_selected_base(character_or_id, nil) do
    with {:ok, state} <- base_state(character_or_id) do
      case state.active_base do
        %Base{} = base -> {:ok, state.character, Bases.get_base!(base.id)}
        nil -> {:error, :active_base_not_found}
      end
    end
  end

  defp current_selected_base(_character_or_id, _selected_base_id),
    do: {:error, :active_base_not_found}

  defp base_exists_at_location(%Character{} = character, location_id) do
    Bases.list_bases_for_character(character.id)
    |> Enum.any?(&(&1.location_id == location_id and &1.status in [:active, :building]))
  end

  defp owned_carried_item(%Character{} = character, inventory_item_id) do
    character.id
    |> Inventory.list_inventory_for_character()
    |> Enum.find(&(&1.id == inventory_item_id))
  end

  defp owned_storage_item(%Base{} = base, storage_item_id) do
    base.id
    |> Bases.list_storage_items()
    |> Enum.find(&(&1.id == storage_item_id))
  end

  defp installed_tool_codes(%Character{} = character) do
    character.id
    |> Inventory.list_inventory_for_character()
    |> Enum.filter(&(&1.quantity > &1.reserved_quantity))
    |> Enum.map(& &1.item_template.code)
    |> Enum.uniq()
  end

  defp find_current_shop_offer(shops, offer_id) do
    shops
    |> Enum.flat_map(&(&1.offers || []))
    |> Enum.find(&(&1.id == offer_id))
  end

  defp find_market_listing(listings, listing_id), do: Enum.find(listings, &(&1.id == listing_id))

  defp find_owned_market_listing(listings, listing_id),
    do: Enum.find(listings, &(&1.id == listing_id))

  defp find_black_market_offer(offers, offer_id), do: Enum.find(offers, &(&1.id == offer_id))

  defp find_owned_black_market_deal(deals, deal_id), do: Enum.find(deals, &(&1.id == deal_id))

  defp owned_pending_duel(%Character{} = character, duel_id) do
    character.id
    |> PVP.pending_duels_for_character()
    |> Enum.find(&(&1.id == duel_id))
    |> preload_duel()
  end

  defp current_open_encounter(%Character{} = character, %Location{} = location, encounter_id) do
    Repo.one(
      from encounter in OverworldEncounter,
        where:
          encounter.id == ^encounter_id and encounter.realm_id == ^character.realm_id and
            encounter.location_id == ^location.id and
            (encounter.initiator_character_id == ^character.id or
               encounter.target_character_id == ^character.id) and
            encounter.status in [:pending, :active]
    )
  end

  defp open_location_encounters(%Character{} = character, %Location{} = location) do
    character.id
    |> Overworld.list_open_encounters_for_character()
    |> Enum.filter(&(&1.realm_id == character.realm_id and &1.location_id == location.id))
    |> Enum.map(&overworld_encounter_summary(&1, character))
  end

  defp overworld_encounter_summary(%OverworldEncounter{} = encounter, %Character{} = character) do
    encounter =
      Repo.preload(encounter, [
        :location,
        :initiator_character,
        :target_character,
        responses: :actor_character
      ])

    counterpart =
      if encounter.initiator_character_id == character.id do
        encounter.target_character
      else
        encounter.initiator_character
      end

    responded? = Enum.any?(encounter.responses, &(&1.actor_character_id == character.id))

    %{
      id: encounter.id,
      status: encounter.status,
      counterpart: %{id: counterpart.id, name: counterpart.name, level: counterpart.level},
      initiated_by_me?: encounter.initiator_character_id == character.id,
      can_respond?: encounter.status in [:pending, :active] and not responded?
    }
  end

  defp overworld_attack_available?(realm, %Location{} = location) do
    not location.safe_zone and Worlds.realm_ruleset(realm)["overworld_pvp_enabled"]
  end

  defp scavenging_hub_state(%Character{} = character, %Location{} = location) do
    attempts = Scavenging.list_attempts_for_character(character.id)
    active_attempt = Enum.find(attempts, &(&1.status == :active))
    latest_completed_attempt = Enum.find(attempts, &(&1.status == :completed))

    %{
      available_caches:
        location.id
        |> Scavenging.available_resource_caches()
        |> Enum.map(&scavenging_cache_summary/1),
      active_attempt: active_attempt && scavenging_attempt_summary(active_attempt),
      latest_completed_attempt:
        latest_completed_attempt && scavenging_attempt_summary(latest_completed_attempt)
    }
  end

  defp available_resource_cache(%Location{} = location, resource_cache_id) do
    location.id
    |> Scavenging.available_resource_caches()
    |> Enum.find(&(&1.id == resource_cache_id))
  end

  defp scavenging_cache_summary(%ResourceCache{} = resource_cache) do
    resource_cache = Repo.preload(resource_cache, :item_template)

    %{
      id: resource_cache.id,
      resource_code: resource_cache.resource_code,
      name:
        case resource_cache.item_template do
          nil -> resource_cache.resource_code
          item_template -> item_template.name
        end,
      quantity_remaining: resource_cache.quantity_remaining,
      quantity_total: resource_cache.quantity_total,
      status: resource_cache.status
    }
  end

  defp scavenging_attempt_summary(%Attempt{} = attempt) do
    attempt = Repo.preload(attempt, resource_cache: :item_template)

    %{
      id: attempt.id,
      status: attempt.status,
      resource_code: attempt.resource_cache.resource_code,
      resource_name:
        case attempt.resource_cache.item_template do
          nil -> attempt.resource_cache.resource_code
          item_template -> item_template.name
        end,
      quantity_requested: attempt.quantity_requested,
      quantity_yielded: attempt.quantity_yielded,
      completes_at: attempt.completes_at,
      xp_awarded: Map.get(attempt.metadata || %{}, "xp_awarded", 0)
    }
  end

  defp reload_character(character_id) do
    character_id
    |> Accounts.get_character!()
    |> Repo.preload(:current_location)
  end

  defp get_or_create_demo_character(realm, handle, name) do
    account =
      case Repo.get_by(Account, handle: handle) do
        %Account{} = existing ->
          if existing.display_name == name do
            existing
          else
            existing |> Ecto.Changeset.change(display_name: name) |> Repo.update!()
          end

        nil ->
          create_demo_account!(handle, name)
      end

    character =
      case Repo.get_by(Character, account_id: account.id, realm_id: realm.id) do
        %Character{} = existing ->
          if existing.name == name do
            existing
          else
            existing |> Character.changeset(%{name: name}) |> Repo.update!()
          end

        nil ->
          create_demo_character!(account, realm, name)
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
          PVP.cancel_duel_for_local_reset(duel, character)
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

  defp fund_character(%Character{} = character, target_balance, reason) do
    {:ok, account} = Economy.ensure_character_account(character)

    shortfall = target_balance - account.current_balance

    if shortfall > 0 do
      realm = Worlds.get_realm!(character.realm_id)

      case Economy.grant_from_treasury(realm, character, shortfall, %{
             "reason" => reason
           }) do
        {:ok, _result} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      :ok
    end
  end

  defp ensure_starter_food(character, target_food_units) do
    ration_template = get_or_create_starter_ration!()
    available_food_units = Survival.food_units_available(character)

    if available_food_units >= target_food_units do
      {:ok, :already_stocked}
    else
      missing_units = target_food_units - available_food_units
      quantity = ceil_div(missing_units, ration_template.nutrition_units)

      Inventory.grant_item(character, ration_template, %{quantity: quantity})
    end
  end

  defp get_or_create_starter_ration! do
    get_or_create_item_template!(%{
      code: @starter_ration_code,
      name: "Дорожный паёк",
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
      name: "Световая пыль",
      item_type: :ingredient,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 0,
      tags: ["starter", "spell_ingredient"],
      actions: [],
      metadata: %{
        "source" => "local_play_session",
        "alchemical_primitives" => %{"clarity" => 2, "volatility" => 1}
      }
    })
  end

  defp ensure_starter_build_materials(character) do
    template = get_or_create_starter_build_material!()

    current_quantity =
      character.id
      |> Inventory.list_inventory_for_character()
      |> Enum.filter(&(&1.item_template_id == template.id))
      |> Enum.reduce(0, fn item, total -> total + Inventory.available_quantity(item) end)

    if current_quantity >= @starter_build_material_quantity do
      {:ok, :already_stocked}
    else
      Inventory.grant_item(character, template, %{
        quantity: @starter_build_material_quantity - current_quantity,
        metadata: %{"source" => "starter_kit"}
      })
    end
  end

  defp get_or_create_starter_build_material! do
    get_or_create_item_template!(%{
      code: @starter_build_material_code,
      name: "Строевой камень",
      item_type: :ingredient,
      stackable: true,
      weight: 2,
      max_durability: 0,
      nutrition_units: 0,
      tags: ["starter", "construction"],
      actions: [],
      metadata: %{
        "source" => "starter_kit",
        "alchemical_primitives" => %{"earth" => 3, "binding" => 2}
      }
    })
  end

  defp get_or_create_item_template!(attrs) do
    case Repo.get_by(ItemTemplate, code: attrs.code) do
      %ItemTemplate{} = template ->
        case template |> ItemTemplate.changeset(attrs) |> Repo.update() do
          {:ok, updated_template} -> updated_template
          {:error, _changeset} -> template
        end

      nil ->
        case Inventory.create_item_template(attrs) do
          {:ok, template} -> template
          {:error, _changeset} -> Repo.get_by!(ItemTemplate, code: attrs.code)
        end
    end
  end

  defp ensure_starter_spell(character) do
    spell =
      case Repo.one(
             from spell in Spell,
               where:
                 spell.creator_character_id == ^character.id and
                   spell.name in [^@starter_spell_name, "Ember Spark"],
               order_by: [desc: spell.name == ^@starter_spell_name],
               limit: 1
           ) do
        %Spell{} = spell ->
          if spell.name == @starter_spell_name do
            spell
          else
            spell
            |> Spell.changeset(%{
              name: @starter_spell_name,
              description: "Небольшое учебное пламя для первого боя."
            })
            |> Repo.update!()
          end

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
        description: "Небольшое учебное пламя для первого боя.",
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
        if grimoire.name == "Starter Grimoire" do
          grimoire
          |> Grimoire.changeset(%{name: "Ученический гримуар"})
          |> Repo.update!()
        else
          grimoire
        end

      nil ->
        {:ok, grimoire} =
          Grimoires.create_grimoire(character, %{
            name: "Ученический гримуар",
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

  defp combat_atmosphere(%Combat{metadata: metadata}) do
    location_kind =
      Map.get(metadata || %{}, "location_kind") || Map.get(metadata || %{}, :location_kind)

    Atmosphere.cue_for(location_kind, major_event: :combat)
  end

  defp combat_state_for(%Character{} = character, %Combat{} = combat) do
    case Enum.find(combat.participants, &(&1.character_id == character.id)) do
      %Participant{} = participant ->
        turn = combat_turn(combat)
        actions = turn_actions(turn)
        lifecycle = if turn, do: CombatContext.turn_lifecycle(turn), else: %{}
        deadline_at = lifecycle_deadline(lifecycle)
        own_action = Enum.find(actions, &(&1.participant_id == participant.id))
        survival = Survival.summary(character)
        action_open? = action_open?(combat, turn, participant, deadline_at)

        {:ok,
         %{
           character: character,
           combat: combat,
           participant: participant,
           spectator?: false,
           turn: turn,
           lifecycle: lifecycle,
           deadline_at: deadline_at,
           prepared_spells: prepared_spells_for(character, participant),
           items: combat_item_summaries(character),
           sides: combat_side_summaries(combat),
           atmosphere: combat_atmosphere(combat),
           events: combat_events(combat.id),
           own_action: own_action,
           submitted_action_count: length(actions),
           ready_participant_count: Enum.count(combat.participants, &(&1.status == :ready)),
           action_open?: action_open?,
           flee_available?: survival.flee_available?,
           can_flee?: action_open? and survival.flee_available?,
           awaiting?: not is_nil(own_action) and not is_nil(turn) and turn.status == :open,
           resolving?:
             combat.status in [:locked, :resolving] or
               (not is_nil(turn) and turn.status in [:locked, :resolving])
         }}

      nil ->
        {:error, :combat_not_found}
    end
  end

  defp spectator_combat_state_for(%Character{} = character, %Combat{} = combat) do
    turn = combat_turn(combat)
    actions = turn_actions(turn)
    lifecycle = if turn, do: CombatContext.turn_lifecycle(turn), else: %{}

    %{
      character: character,
      combat: combat,
      participant: nil,
      spectator?: true,
      turn: turn,
      lifecycle: lifecycle,
      deadline_at: lifecycle_deadline(lifecycle),
      prepared_spells: [],
      items: [],
      sides: combat_side_summaries(combat),
      atmosphere: combat_atmosphere(combat),
      events: combat_events(combat.id),
      own_action: nil,
      submitted_action_count: length(actions),
      ready_participant_count: Enum.count(combat.participants, &(&1.status == :ready)),
      action_open?: false,
      flee_available?: false,
      can_flee?: false,
      awaiting?: false,
      resolving?:
        combat.status in [:locked, :resolving] or
          (not is_nil(turn) and turn.status in [:locked, :resolving])
    }
  end

  defp spectator_allowed?(%Character{} = character, %Combat{} = combat) do
    location_id =
      Map.get(combat.metadata || %{}, "location_id") ||
        Map.get(combat.metadata || %{}, :location_id)

    club_event_id =
      Map.get(combat.metadata || %{}, "club_event_id") ||
        Map.get(combat.metadata || %{}, :club_event_id)

    expedition_id =
      Map.get(combat.metadata || %{}, "expedition_id") ||
        Map.get(combat.metadata || %{}, :expedition_id)

    cond do
      combat.kind in [:duel, :overworld_encounter] ->
        character.realm_id == combat.realm_id and is_binary(location_id) and
          character.current_location_id == location_id and
          is_nil(Travel.active_journey(character.id))

      combat.kind == :club_match ->
        character.realm_id == combat.realm_id and
          Clubs.character_attending_event?(club_event_id, character.id)

      combat.kind == :dungeon_encounter ->
        character.realm_id == combat.realm_id and is_binary(expedition_id) and
          Parties.eligible_member_for_expedition?(expedition_id, character.id)

      true ->
        false
    end
  end

  defp combat_turn(%Combat{} = combat) do
    Repo.one(
      from turn in Turn,
        where: turn.combat_id == ^combat.id and turn.number == ^combat.turn_number
    )
  end

  defp turn_actions(nil), do: []

  defp turn_actions(%Turn{} = turn) do
    Repo.all(
      from action in Action,
        where: action.combat_turn_id == ^turn.id,
        order_by: [asc: action.submitted_at]
    )
  end

  defp lifecycle_deadline(%{"deadline_at" => deadline_at}) when is_binary(deadline_at) do
    case DateTime.from_iso8601(deadline_at) do
      {:ok, parsed, _offset} -> parsed
      _other -> nil
    end
  end

  defp lifecycle_deadline(_lifecycle), do: nil

  defp action_open?(%Combat{} = combat, %Turn{} = turn, %Participant{} = participant, deadline_at) do
    combat.status == :active_turn and turn.status == :open and participant.status == :ready and
      (is_nil(deadline_at) or DateTime.compare(DateTime.utc_now(), deadline_at) == :lt)
  end

  defp action_open?(_combat, _turn, _participant, _deadline_at), do: false

  defp prepared_spells_for(%Character{} = character, %Participant{} = participant) do
    prepared_spell_ids = prepared_spell_ids(participant)

    character.id
    |> Spells.list_spells_for_character()
    |> Enum.filter(&MapSet.member?(prepared_spell_ids, &1.id))
  end

  defp combat_item_summaries(%Character{} = character) do
    character.id
    |> Inventory.list_inventory_for_character()
    |> Enum.map(fn item ->
      %{
        id: item.id,
        name: item.item_template.name,
        quantity: item.quantity,
        available_quantity: Inventory.available_quantity(item),
        durability: item.durability,
        actions:
          Enum.map(item.item_template.actions || [], fn action ->
            %{
              key: action.key,
              kind: action.action_kind,
              targeting: action.targeting,
              quantity_cost: action.quantity_cost,
              durability_cost: action.durability_cost
            }
          end)
      }
    end)
    |> Enum.filter(&(&1.actions != []))
  end

  defp duel_combat_state_for(%Character{} = _character, %Duel{combat_id: nil}),
    do: {:error, :duel_has_no_combat}

  defp duel_combat_state_for(%Character{} = character, %Duel{} = duel) do
    duel = PVP.get_duel!(duel.id)
    combat = CombatContext.get_combat!(duel.combat_id)

    with {:ok, state} <- combat_state_for(character, combat) do
      {:ok, Map.put(state, :duel, duel)}
    end
  end

  defp resolve_duel_turn(state) do
    with %Turn{id: turn_id} <- combat_turn(state.combat),
         {:ok, resolved_combat} <- CombatContext.resolve_turn(state.combat),
         :ok <- TurnArtifacts.persist(state.combat.id, turn_id),
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
