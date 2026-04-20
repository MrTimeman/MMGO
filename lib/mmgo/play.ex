defmodule MMGO.Play do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Inventory
  alias MMGO.Inventory.ItemTemplate
  alias MMGO.Grimoires
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Spells.Spell
  alias MMGO.Survival
  alias MMGO.Travel
  alias MMGO.Travel.{Clock, Journey}
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Realm, Route}

  @browser_account_handle "wayfarer-local"
  @browser_character_name "Альтаир Вейн"
  @starter_ration_code "play_map_ration"
  @starter_ration_quantity 24
  @map_image_url "/images/demo-map.png"
  @default_map_width 2_000
  @default_map_height 2_000
  @poll_interval_ms 10_000

  def get_character(id) when is_binary(id) do
    Character
    |> Repo.get(id)
    |> maybe_preload_character()
  end

  def get_character(_id), do: nil

  def ensure_browser_character do
    Repo.transaction(fn ->
      realm = Worlds.get_default_realm() || Repo.rollback(:default_realm_not_found)
      entry_location = entry_location_for_realm(realm) || Repo.rollback(:entry_location_not_found)

      account =
        Repo.get_by(Account, handle: @browser_account_handle) ||
          create_browser_account!()

      character =
        Repo.get_by(Character, account_id: account.id, realm_id: realm.id) ||
          create_browser_character!(account, realm, entry_location)

      character = ensure_character_location!(character, entry_location)
      _ = ensure_starter_supplies!(character)

      character.id
      |> get_character()
      |> then(&{:ok, &1})
    end)
    |> normalize_transaction_result()
  end

  def map_state(%Character{} = character, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, %{character: current_character, active_journey: active_journey}} <-
           sync_character_state(character, now) do
      realm = Worlds.get_realm!(current_character.realm_id)
      entry_location = entry_location_for_realm(realm)
      locations = Worlds.list_locations_for_realm(realm.id)
      routes = Worlds.list_routes_for_realm(realm.id)
      utility_context = utility_context(current_character)
      location_index = Map.new(locations, &{&1.id, &1})
      current_location = Map.get(location_index, current_character.current_location_id)

      available_routes =
        if active_journey do
          []
        else
          available_routes(current_character, routes, location_index)
        end

      {:ok,
       %{
         realm: realm_payload(realm),
         character: character_payload(current_character),
         current_location: location_payload(current_location),
         player: player_payload(current_character, active_journey, location_index, now),
         supplies: supply_payload(current_character),
         magic: %{
           utility_spells: utility_context.utility_spells
         },
         dungeon: utility_context.dungeon,
         active_journey: journey_payload(active_journey, now),
         available_routes:
           Enum.map(available_routes, &available_route_payload(&1, current_character)),
         map: %{
           width: map_width(locations),
           height: map_height(locations),
           image_url: @map_image_url,
           locations:
             Enum.map(locations, &map_location_payload(&1, current_character, active_journey)),
           routes: Enum.map(routes, &route_payload/1)
         },
         client: %{
           poll_interval_ms: @poll_interval_ms,
           can_enter_location: is_nil(active_journey),
           can_cast_utility_spell:
             is_nil(active_journey) and utility_context.dungeon != nil and
               utility_context.utility_spells != []
         },
         demo: %{
           local_mode: browser_fallback_character?(current_character),
           reset_available: browser_fallback_character?(current_character),
           route_hint: demo_route_hint(realm),
           start_location_name: entry_location && entry_location.name
         }
       }}
    end
  end

  def start_journey(character, route_id, opts \\ [])

  def start_journey(%Character{} = character, route_id, opts)
      when is_binary(route_id) and byte_size(route_id) > 0 do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())

    case Repo.get(Route, route_id) do
      %Route{} = route -> Travel.start_journey(character, route, started_at: started_at)
      nil -> {:error, route_changeset("route could not be found")}
    end
  end

  def start_journey(%Character{}, _route_id, _opts) do
    {:error, route_changeset("route_id is required")}
  end

  def cast_utility_spell(character, spell_id, opts \\ [])

  def cast_utility_spell(%Character{} = character, spell_id, opts)
      when is_binary(spell_id) and byte_size(spell_id) > 0 do
    character = get_character(character.id) || character

    with %Spell{} = spell <- Repo.get(Spell, spell_id),
         :ok <- validate_utility_spell_owner(character, spell),
         :ok <- validate_utility_spell_mode(spell),
         :ok <- validate_utility_spell_prepared(character.id, spell.id),
         {:ok, run} <- active_dungeon_run_for_character(character.id),
         {:ok, _result} <- Dungeons.cast_utility_spell(run, character, spell, opts) do
      {:ok, spell}
    else
      nil -> {:error, utility_changeset(:spell_id, "spell could not be found")}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  def cast_utility_spell(%Character{}, _spell_id, _opts) do
    {:error, utility_changeset(:spell_id, "spell_id is required")}
  end

  def reset_demo(%Character{} = character, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      realm = Worlds.get_realm!(character.realm_id)
      entry_location = entry_location_for_realm(realm) || Repo.rollback(:entry_location_not_found)

      active_journey =
        character.id
        |> Travel.active_journey()
        |> case do
          nil -> nil
          %Journey{} = journey -> Repo.preload(journey, [:from_location, :to_location, :route])
        end

      if active_journey do
        active_journey
        |> Journey.changeset(%{status: :cancelled, completed_at: now})
        |> Repo.update!()
      end

      updated_character =
        character
        |> Character.travel_changeset(%{current_location_id: entry_location.id})
        |> Repo.update!()

      _ = ensure_starter_supplies!(updated_character)

      updated_character.id
      |> get_character()
      |> then(&{:ok, &1})
    end)
    |> normalize_transaction_result()
  end

  defp normalize_transaction_result({:ok, {:ok, character}}), do: {:ok, character}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp maybe_preload_character(nil), do: nil

  defp maybe_preload_character(%Character{} = character),
    do: Repo.preload(character, :current_location)

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp create_browser_account! do
    %Account{}
    |> Account.registration_changeset(%{
      display_name: @browser_character_name,
      handle: @browser_account_handle,
      settings: %{"mode" => "browser_fallback"}
    })
    |> Repo.insert!()
  end

  defp create_browser_character!(
         %Account{} = account,
         %Realm{} = realm,
         %Location{} = entry_location
       ) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{
      name: @browser_character_name,
      level: 7,
      metadata: %{"origin" => "browser_fallback"}
    })
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: entry_location.id})
    |> Repo.update!()
  end

  defp ensure_character_location!(
         %Character{current_location_id: nil} = character,
         %Location{} = entry_location
       ) do
    character
    |> Character.travel_changeset(%{current_location_id: entry_location.id})
    |> Repo.update!()
  end

  defp ensure_character_location!(%Character{} = character, _entry_location), do: character

  defp ensure_starter_supplies!(%Character{} = character) do
    minimum_food_units = @starter_ration_quantity
    available_food_units = Survival.food_units_available(character)

    if available_food_units < minimum_food_units do
      template = starter_ration_template!()

      Inventory.grant_item(character, template, %{
        quantity: minimum_food_units - available_food_units
      })
    else
      {:ok, :already_stocked}
    end
  end

  defp starter_ration_template! do
    Repo.get_by(ItemTemplate, code: @starter_ration_code) ||
      create_starter_ration_template!()
  end

  defp create_starter_ration_template! do
    {:ok, template} =
      Inventory.create_item_template(%{
        code: @starter_ration_code,
        name: "Дорожный паёк",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        tags: ["travel", "starter"],
        metadata: %{"source" => "play_map"},
        actions: []
      })

    template
  end

  defp entry_location_for_realm(%Realm{} = realm) do
    cond do
      is_binary(realm.entry_location_id) ->
        Repo.get(Location, realm.entry_location_id)

      location = Worlds.get_location_by_slug(realm.id, "capital-city") ->
        location

      true ->
        Location
        |> where([location], location.realm_id == ^realm.id)
        |> order_by([location], asc: location.inserted_at)
        |> limit(1)
        |> Repo.one()
    end
  end

  defp sync_character_state(%Character{} = character, %DateTime{} = now) do
    character = get_character(character.id) || character

    case Travel.active_journey(character.id) do
      nil ->
        {:ok, %{character: character, active_journey: nil}}

      %Journey{} = journey ->
        journey = Repo.preload(journey, [:from_location, :to_location, :route])

        if DateTime.compare(now, journey.arrival_at) == :lt do
          {:ok, %{character: character, active_journey: journey}}
        else
          case Travel.complete_journey_by_id(journey.id, now: now, force: true) do
            {:ok, %{character: updated_character}} ->
              {:ok, %{character: get_character(updated_character.id), active_journey: nil}}

            {:error, _changeset} ->
              {:ok, %{character: character, active_journey: journey}}
          end
        end
    end
  end

  defp utility_context(%Character{} = character) do
    active_grimoire =
      character.id
      |> Grimoires.active_grimoire_for_character()
      |> case do
        nil -> nil
        grimoire -> Repo.preload(grimoire, entries: :spell)
      end

    utility_spells =
      active_grimoire
      |> case do
        nil ->
          []

        grimoire ->
          grimoire.entries
          |> Enum.map(& &1.spell)
          |> Enum.filter(&(&1.spell_type == :utility))
          |> Enum.map(&utility_spell_payload/1)
      end

    dungeon =
      case active_dungeon_run_for_character(character.id) do
        {:ok, run} -> dungeon_payload(run)
        {:error, _reason} -> nil
      end

    %{utility_spells: utility_spells, dungeon: dungeon}
  end

  defp realm_payload(%Realm{} = realm) do
    %{
      id: realm.id,
      slug: realm.slug,
      name: realm.name,
      description: realm.public_description || realm.metadata["description"]
    }
  end

  defp character_payload(%Character{} = character) do
    %{
      id: character.id,
      name: character.name,
      level: character.level,
      status: to_string(character.status)
    }
  end

  defp supply_payload(%Character{} = character) do
    %{
      food_units_available: Survival.food_units_available(character),
      carried_weight: Survival.carried_weight(character),
      carry_capacity: Survival.carry_capacity(character)
    }
  end

  defp player_payload(%Character{} = character, active_journey, location_index, now) do
    {x, y} =
      case active_journey do
        %Journey{} = journey ->
          interpolate_position(
            Map.get(location_index, journey.from_location_id),
            Map.get(location_index, journey.to_location_id),
            journey_progress(journey, now)
          )

        nil ->
          case Map.get(location_index, character.current_location_id) do
            %Location{x: x, y: y} -> {x, y}
            nil -> {0, 0}
          end
      end

    %{
      x: x,
      y: y,
      location_id: character.current_location_id,
      traveling: not is_nil(active_journey)
    }
  end

  defp journey_payload(nil, _now), do: nil

  defp journey_payload(%Journey{} = journey, %DateTime{} = now) do
    progress = journey_progress(journey, now)
    remaining_seconds = max(DateTime.diff(journey.arrival_at, now, :second), 0)

    %{
      id: journey.id,
      route_id: journey.route_id,
      from_location_id: journey.from_location_id,
      from_name: journey.from_location.name,
      to_location_id: journey.to_location_id,
      to_name: journey.to_location.name,
      travel_days: journey.travel_days,
      food_units_consumed: journey.food_units_consumed,
      encumbrance_penalty_days: journey.encumbrance_penalty_days,
      carried_weight: journey.carried_weight,
      carry_capacity: journey.carry_capacity,
      started_at: DateTime.to_iso8601(journey.started_at),
      arrival_at: DateTime.to_iso8601(journey.arrival_at),
      remaining_seconds: remaining_seconds,
      remaining_game_days: remaining_game_days(remaining_seconds),
      percent_complete: round(progress * 100)
    }
  end

  defp map_location_payload(%Location{} = location, %Character{} = character, active_journey) do
    %{
      id: location.id,
      slug: location.slug,
      name: location.name,
      kind: to_string(location.kind),
      x: location.x,
      y: location.y,
      safe_zone: location.safe_zone,
      current: location.id == character.current_location_id,
      destination: destination_location?(active_journey, location.id)
    }
  end

  defp route_payload(%Route{} = route) do
    %{
      id: route.id,
      name: route.name,
      origin_location_id: route.origin_location_id,
      destination_location_id: route.destination_location_id,
      travel_days: route.travel_days,
      risk_level: route.risk_level,
      bidirectional: route.bidirectional
    }
  end

  defp available_routes(%Character{current_location_id: nil}, _routes, _location_index), do: []

  defp available_routes(%Character{} = character, routes, location_index) do
    routes
    |> Enum.reduce([], fn route, acc ->
      case route_destination(route, character.current_location_id, location_index) do
        nil -> acc
        destination -> [{route, destination} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp available_route_payload(
         {%Route{} = route, %Location{} = destination},
         %Character{} = character
       ) do
    plan = Survival.travel_plan(character, route.travel_days)

    %{
      id: route.id,
      name: route.name,
      destination_location_id: destination.id,
      destination_name: destination.name,
      destination_kind: to_string(destination.kind),
      travel_days: route.travel_days,
      total_game_days: plan.total_game_days,
      required_food_units: plan.required_food_units,
      encumbrance_penalty_days: plan.encumbrance_penalty_days,
      risk_level: route.risk_level
    }
  end

  defp route_destination(%Route{} = route, current_location_id, location_index)
       when route.origin_location_id == current_location_id do
    Map.get(location_index, route.destination_location_id)
  end

  defp route_destination(%Route{bidirectional: true} = route, current_location_id, location_index)
       when route.destination_location_id == current_location_id do
    Map.get(location_index, route.origin_location_id)
  end

  defp route_destination(_route, _current_location_id, _location_index), do: nil

  defp location_payload(nil), do: nil

  defp location_payload(%Location{} = location) do
    %{
      id: location.id,
      slug: location.slug,
      name: location.name,
      kind: to_string(location.kind),
      x: location.x,
      y: location.y,
      safe_zone: location.safe_zone
    }
  end

  defp utility_spell_payload(%Spell{} = spell) do
    %{
      id: spell.id,
      name: spell.name,
      targeting: to_string(spell.targeting),
      delivery_form: to_string(spell.delivery_form),
      effects:
        Enum.map(spell.effects, fn effect ->
          %{
            state: effect.state,
            intensity: effect.intensity,
            applies_to: to_string(effect.applies_to)
          }
        end)
    }
  end

  defp dungeon_payload(run) do
    %{
      run_id: run.id,
      dungeon_id: run.dungeon_id,
      dungeon_name: run.dungeon && run.dungeon.name,
      current_node_id: run.current_node_id,
      current_node_name: run.current_node && run.current_node.name
    }
  end

  defp map_width(locations) do
    case Enum.map(locations, &(&1.x + 160)) do
      [] -> @default_map_width
      widths -> max(Enum.max(widths), @default_map_width)
    end
  end

  defp map_height(locations) do
    case Enum.map(locations, &(&1.y + 200)) do
      [] -> @default_map_height
      heights -> max(Enum.max(heights), @default_map_height)
    end
  end

  defp journey_progress(%Journey{} = journey, %DateTime{} = now) do
    total_seconds = max(DateTime.diff(journey.arrival_at, journey.started_at, :second), 1)
    elapsed_seconds = DateTime.diff(now, journey.started_at, :second)

    elapsed_seconds
    |> Kernel./(total_seconds)
    |> max(0.0)
    |> min(1.0)
  end

  defp remaining_game_days(remaining_seconds) do
    remaining_seconds
    |> Clock.real_seconds_to_game_days()
    |> Float.ceil()
    |> trunc()
  end

  defp interpolate_position(%Location{} = from, %Location{} = to, progress) do
    x = round(from.x + (to.x - from.x) * progress)
    y = round(from.y + (to.y - from.y) * progress)
    {x, y}
  end

  defp interpolate_position(_from, _to, _progress), do: {0, 0}

  defp destination_location?(%Journey{to_location_id: to_location_id}, location_id),
    do: to_location_id == location_id

  defp destination_location?(_journey, _location_id), do: false

  defp browser_fallback_character?(%Character{} = character) do
    character.metadata["origin"] == "browser_fallback"
  end

  defp demo_route_hint(%Realm{} = realm) do
    ash_crossing = Worlds.get_location_by_slug(realm.id, "ash-crossing")
    tower = Worlds.get_location_by_slug(realm.id, "the-tower")

    cond do
      ash_crossing && tower -> "Capital City → Ash Crossing → The Tower"
      tower -> "Capital City → The Tower"
      true -> "Start from the entry city and follow any reachable road."
    end
  end

  defp active_dungeon_run_for_character(character_id) when is_binary(character_id) do
    case Parties.active_expedition_for_character(character_id) do
      nil ->
        {:error, utility_changeset(:run_id, "utility spells require an active dungeon run")}

      expedition ->
        case Dungeons.active_run_for_expedition(expedition.id) do
          nil ->
            {:error, utility_changeset(:run_id, "utility spells require an active dungeon run")}

          run ->
            {:ok, run}
        end
    end
  end

  defp validate_utility_spell_owner(%Character{} = character, %Spell{} = spell) do
    if spell.creator_character_id == character.id do
      :ok
    else
      {:error, utility_changeset(:spell_id, "spell must belong to the current character")}
    end
  end

  defp validate_utility_spell_mode(%Spell{} = spell) do
    cond do
      spell.spell_type != :utility ->
        {:error, utility_changeset(:spell_id, "spell is not a utility spell")}

      spell.targeting not in [:self, :zone] ->
        {:error, utility_changeset(:targeting, "utility spells must target self or zone")}

      true ->
        :ok
    end
  end

  defp validate_utility_spell_prepared(character_id, spell_id) do
    case Grimoires.active_grimoire_for_character(character_id) do
      nil ->
        {:error, utility_changeset(:spell_id, "an active grimoire is required")}

      grimoire ->
        grimoire = Repo.preload(grimoire, entries: :spell)

        if Enum.any?(grimoire.entries, &(&1.spell_id == spell_id)) do
          :ok
        else
          {:error, utility_changeset(:spell_id, "spell is not inscribed in the active grimoire")}
        end
    end
  end

  defp route_changeset(message) do
    %Journey{}
    |> Changeset.change()
    |> Changeset.add_error(:route_id, message)
  end

  defp utility_changeset(field, message) do
    %Spell{}
    |> Changeset.change()
    |> Changeset.add_error(field, message)
  end
end
