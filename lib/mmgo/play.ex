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
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Grimoires
  alias MMGO.Grimoires.Grimoire
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.PVP
  alias MMGO.PVP.Duel
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.Spell
  alias MMGO.Survival
  alias MMGO.Travel
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

  defp preload_duel(nil), do: nil
  defp preload_duel(duel), do: PVP.get_duel!(duel.id)

  defp ceil_div(value, divisor) when divisor > 0 do
    div(value + divisor - 1, divisor)
  end
end
