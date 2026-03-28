defmodule MMGO.Telegram.Commands do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Alchemy
  alias MMGO.Bases
  alias MMGO.Clubs
  alias MMGO.Clubs.Invitation, as: ClubInvitation
  alias MMGO.Combat
  alias MMGO.Crafting
  alias MMGO.Dungeons
  alias MMGO.Federation
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Operator
  alias MMGO.Parties
  alias MMGO.PVP
  alias MMGO.Reputation
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Survival
  alias MMGO.Telegram.Formatter
  alias MMGO.Travel
  alias MMGO.Worlds

  def process_message(character, %{"text" => text}) when is_binary(text) do
    character = load_character(character.id)

    case parse_command(text) do
      :ignore -> {:ok, nil}
      {:ok, command, args} -> dispatch(command, args, character)
    end
  end

  def process_message(_character, _message), do: {:ok, nil}

  defp dispatch("start", _args, character) do
    location = (character.current_location && character.current_location.name) || "nowhere"

    {:ok,
     [
       "Welcome to MMGO, #{character.name}.",
       "You are currently at #{location}.",
       "Try /help to see available commands."
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("help", _args, _character) do
    {:ok,
     [
       "Available commands:",
       "/status",
       "/inventory",
       "/routes",
       "/travel <location-slug>",
       "/journey",
       "/realms list",
       "/realms quote <realm-slug> <amount>",
       "/realms migrate <realm-slug> <amount>",
       "/realms migrations",
       "/academy status",
       "/academy start basic|wizardry <school1> <school2>|alchemy|mastery|extended|academia",
       "/base status",
       "/base buy <location-slug>",
       "/base build <location-slug>",
       "/base storage <base-id>",
       "/base deposit <base-id> <inventory-item-id> [quantity]",
       "/base withdraw <base-id> <storage-item-id> [quantity]",
       "/alchemy workspace",
       "/alchemy setup [tool1,tool2,...]",
       "/alchemy recipes",
       "/alchemy brew <recipe-code> [quantity]",
       "/alchemy jobs",
       "/craft workshop",
       "/craft setup [tool1,tool2,...]",
       "/craft recipes",
       "/craft build <recipe-code> [quantity]",
       "/craft jobs",
       "/scavenge <resource_code> [quantity]",
       "/party create [name]",
       "/party status",
       "/club create <type> <name>",
       "/club list",
       "/club status <club-id>",
       "/club invite <club-id> <handle>",
       "/club invites",
       "/club accept <invite-id>",
       "/club reject <invite-id>",
       "/club leave <club-id>",
       "/duel challenge <handle> <stake>",
       "/duel accept <duel-id>",
       "/duel reject <duel-id>",
       "/duel cancel <duel-id>",
       "/duel status",
       "/expedition start",
       "/expedition status",
       "/dungeon enter",
       "/dungeon status",
       "/dungeon move <node-slug>",
       "/dungeon extract",
       "/dungeon ritual",
       "/dungeon drops",
       "/encounter status",
       "/encounter fight",
       "/spells",
       "/combat status",
       "/combat cast <spell-id>",
       "/combat wait",
       "/combat resolve",
       "/admin status",
       "/admin realm <slug>",
       "/admin sweep",
       "/admin federation manifest",
       "/admin federation register <manifest-url> [token]",
       "/admin federation sync <realm-slug>",
       "/admin profile <handle>",
       "/admin crime <handle> <crime_type> <severity> [fine]"
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("status", _args, character) do
    journey = Travel.active_journey(character.id)
    enrollment = Academy.current_enrollment(character.id)
    specialization = Academy.active_specialization(character.id)
    party = Parties.active_party_for_character(character.id)
    expedition = Parties.active_expedition_for_character(character.id)
    run = expedition && Dungeons.active_run_for_expedition(expedition.id)
    carry = Survival.carried_weight(character)
    carry_capacity = Survival.carry_capacity(character)
    food_units = Survival.food_units_available(character)

    lines = [
      "#{character.name} — lvl #{character.level}, xp #{character.xp}",
      "Location: #{location_name(character)}",
      "Carry: #{carry}/#{carry_capacity}",
      "Food: #{food_units}",
      "Journey: #{journey_status(journey)}",
      "Academy: #{academy_status(enrollment, specialization)}",
      "Party: #{party_status(party)}",
      "Expedition: #{expedition_status(expedition)}",
      "Dungeon: #{dungeon_status(run)}"
    ]

    {:ok, Enum.join(lines, "\n")}
  end

  defp dispatch("inventory", _args, character) do
    items = Inventory.list_inventory_for_character(character.id)

    body =
      if items == [] do
        ["Inventory is empty."]
      else
        Enum.map(items, fn item ->
          available = Inventory.available_quantity(item)
          reserved = item.reserved_quantity
          suffix = if reserved > 0, do: " (reserved #{reserved})", else: ""
          "- #{item.item_template.name}: #{available}/#{item.quantity}#{suffix}"
        end)
      end

    {:ok, Enum.join(["Inventory:"] ++ body, "\n")}
  end

  defp dispatch("routes", _args, character) do
    with %{id: location_id} = location <- character.current_location do
      routes = Worlds.list_routes_for_location(location_id)

      if routes == [] do
        {:ok, "No routes are available from #{location.name}."}
      else
        {:ok,
         Enum.join(
           ["Routes from #{location.name}:"] ++
             Enum.map(routes, fn route ->
               destination = route_destination(route, location_id)

               "- #{destination.slug}: #{destination.name} (#{route.travel_days} game-days, risk #{route.risk_level})"
             end),
           "\n"
         )}
      end
    else
      nil -> {:ok, "You are not currently placed at a location."}
    end
  end

  defp dispatch("travel", [destination_slug], character) do
    with %{id: location_id} <- character.current_location,
         route when not is_nil(route) <-
           Worlds.route_from_location_to_slug(location_id, destination_slug),
         {:ok, %{journey: journey}} <- Travel.start_journey(character, route) do
      {:ok,
       "Journey started to #{destination_slug}. Arrival: #{Formatter.datetime(journey.arrival_at)}. Food consumed: #{journey.food_units_consumed}."}
    else
      nil ->
        {:ok, "No direct route to #{destination_slug} from your current location."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start journey: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("travel", _args, _character), do: {:ok, "Usage: /travel <location-slug>"}

  defp dispatch("journey", _args, character) do
    case Travel.active_journey(character.id) do
      nil ->
        {:ok, "No active journey."}

      journey ->
        journey = Repo.preload(journey, [:from_location, :to_location])

        {:ok,
         "Journey: #{journey.from_location.name} -> #{journey.to_location.name}, arrival #{Formatter.datetime(journey.arrival_at)}, food #{journey.food_units_consumed}."}
    end
  end

  defp dispatch("realms", ["list"], _character) do
    realms = Federation.list_remote_realms()

    if realms == [] do
      {:ok, "No discoverable realms."}
    else
      {:ok,
       Enum.join(
         ["Discoverable realms:"] ++
           Enum.map(realms, fn realm ->
             currency = realm.currency_code || "unknown"
             endpoint = realm.public_endpoint || "no-endpoint"
             population = realm.population_hint || 1
             "- #{realm.slug}: #{realm.name} (#{currency}, pop #{population}, #{endpoint})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("realms", ["quote", realm_slug, amount_raw], character) do
    amount = parse_positive_integer(amount_raw, 0)
    origin_realm = Worlds.get_realm!(character.realm_id)

    with %{} = destination_realm <- Federation.get_remote_realm_by_slug(realm_slug),
         {:ok, quote} <-
           Federation.quote_remote_exchange(origin_realm, destination_realm, amount) do
      {:ok,
       "Exchange quote: #{amount} #{origin_realm.currency_code || "src"} -> #{quote.converted_amount} #{destination_realm.currency_code || "dst"}. Source pop #{quote.source_population}, destination pop #{quote.destination_population}."}
    else
      nil ->
        {:ok, "No realm with slug #{realm_slug} found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not quote migration currency: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("realms", ["migrate", realm_slug, amount_raw], character) do
    amount = parse_positive_integer(amount_raw, 0)

    with %{} = destination_realm <- Federation.get_remote_realm_by_slug(realm_slug),
         {:ok, %{migration: migration, remote_response: remote_response}} <-
           Federation.start_migration(character, destination_realm, amount) do
      {:ok,
       "Migration started to #{destination_realm.name}. Remote character #{remote_response["destination_character_name"]}. Freeze ends #{Formatter.datetime(migration.freeze_ends_at)}."}
    else
      nil ->
        {:ok, "No realm with slug #{realm_slug} found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start migration: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("realms", ["migrations"], character) do
    migrations = Federation.list_migrations_for_account(character.account_id)

    if migrations == [] do
      {:ok, "No realm migrations."}
    else
      {:ok,
       Enum.join(
         ["Realm migrations:"] ++
           Enum.map(migrations, fn migration ->
             destination_slug =
               (migration.remote_realm && migration.remote_realm.slug) ||
                 (migration.destination_realm && migration.destination_realm.slug) || "unknown"

             "- #{migration.id}: #{migration.origin_realm.slug} -> #{destination_slug} (#{migration.status})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("realms", _args, _character) do
    {:ok,
     "Usage: /realms list | /realms quote <realm-slug> <amount> | /realms migrate <realm-slug> <amount> | /realms migrations"}
  end

  defp dispatch("academy", ["status"], character) do
    enrollment = Academy.current_enrollment(character.id)
    specialization = Academy.active_specialization(character.id)

    {:ok,
     [
       "Enrollment: #{academy_enrollment_line(enrollment)}",
       "Specialization: #{academy_specialization_line(specialization)}"
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("academy", ["start", "basic"], character) do
    case Academy.begin_basic_education(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Basic education started. Completion: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start basic education: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "wizardry", school1, school2], character) do
    case Academy.start_academy_track(character, :wizardry, %{
           primary_school: school1,
           secondary_school: school2
         }) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Wizardry track started. Completion: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start wizardry: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", track], character) when track in ["alchemy", "mastery"] do
    case Academy.start_academy_track(character, String.to_existing_atom(track)) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "#{String.capitalize(track)} track started. Completion: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start #{track}: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "extended"], character) do
    case Academy.start_extended_study(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Extended study started. Completion: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start extended study: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "academia"], character) do
    case Academy.start_academia(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Academia started. Completion: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start academia: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", _args, _character) do
    {:ok,
     "Usage: /academy status | /academy start basic|wizardry <school1> <school2>|alchemy|mastery|extended|academia"}
  end

  defp dispatch("base", ["status"], character) do
    bases = Bases.list_bases_for_character(character.id)

    if bases == [] do
      {:ok, "No bases."}
    else
      {:ok,
       Enum.join(
         ["Bases:"] ++
           Enum.map(bases, fn base ->
             "- #{base.id}: #{base.name} @ #{base.location.name} (#{base.status}, cap #{base.storage_weight_capacity}, used #{Bases.storage_weight(base)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("base", ["buy", location_slug], character) do
    with %{} = location <- Worlds.get_location_by_slug(character.realm_id, location_slug),
         {:ok, base} <- Bases.purchase_city_base(character, location) do
      {:ok, "Base purchased: #{base.name} at #{location.name}."}
    else
      nil ->
        {:ok, "No location with slug #{location_slug} found in your realm."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not buy base: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", ["build", location_slug], character) do
    with %{} = location <- Worlds.get_location_by_slug(character.realm_id, location_slug),
         {:ok, %{base: base}} <- Bases.start_custom_base_build(character, location) do
      {:ok,
       "Base construction started at #{location.name}. Ready: #{Formatter.datetime(base.ready_at)}."}
    else
      nil ->
        {:ok, "No location with slug #{location_slug} found in your realm."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start base construction: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", ["storage", base_id], character) do
    with %{} = base <- load_owned_base(base_id, character.id) do
      items = Bases.list_storage_items(base.id)

      if items == [] do
        {:ok, "Base storage is empty."}
      else
        {:ok,
         Enum.join(
           ["Storage for #{base.name}:"] ++
             Enum.map(items, fn item ->
               "- #{item.id}: #{item.item_template.name} x#{item.quantity}"
             end),
           "\n"
         )}
      end
    else
      nil -> {:ok, "No owned base found for that id."}
    end
  end

  defp dispatch("base", ["deposit", base_id, inventory_item_id], character) do
    dispatch("base", ["deposit", base_id, inventory_item_id, "1"], character)
  end

  defp dispatch("base", ["deposit", base_id, inventory_item_id, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = base <- load_owned_base(base_id, character.id),
         %{} = inventory_item <- load_owned_inventory_item(inventory_item_id, character.id),
         {:ok, _result} <- Bases.deposit_item(character, base, inventory_item, quantity) do
      {:ok, "Deposited #{quantity} item(s) into #{base.name}."}
    else
      nil ->
        {:ok, "Base or inventory item not found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not deposit to base: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", ["withdraw", base_id, storage_item_id], character) do
    dispatch("base", ["withdraw", base_id, storage_item_id, "1"], character)
  end

  defp dispatch("base", ["withdraw", base_id, storage_item_id, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = base <- load_owned_base(base_id, character.id),
         %{} = storage_item <- load_storage_item_for_base(storage_item_id, base.id),
         {:ok, _result} <- Bases.withdraw_item(character, base, storage_item, quantity) do
      {:ok, "Withdrew #{quantity} item(s) from #{base.name}."}
    else
      nil ->
        {:ok, "Base or storage item not found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not withdraw from base: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", _args, _character) do
    {:ok,
     "Usage: /base status | /base buy <location-slug> | /base build <location-slug> | /base storage <base-id> | /base deposit <base-id> <inventory-item-id> [quantity] | /base withdraw <base-id> <storage-item-id> [quantity]"}
  end

  defp dispatch("alchemy", ["workspace"], character) do
    case Alchemy.get_workshop_for_character(character.id) do
      nil ->
        {:ok,
         "No active alchemy workspace. Use /alchemy setup [tool1,tool2,...] to create one at your current location."}

      workspace ->
        location_name = location_name_by_id(workspace.location_id)

        tools =
          if workspace.installed_tool_codes == [],
            do: "none",
            else: Enum.join(workspace.installed_tool_codes, ", ")

        {:ok,
         Enum.join(
           [
             "Workspace: #{workspace.name}",
             "Location: #{location_name}",
             "Status: #{workspace.status}",
             "Tools: #{tools}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("alchemy", ["setup"], character) do
    dispatch("alchemy", ["setup", "cauldron"], character)
  end

  defp dispatch("alchemy", ["setup", tool_codes_csv], character) do
    with %{id: location_id} <- character.current_location do
      tool_codes =
        tool_codes_csv
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      attrs = %{
        name: "#{character.name}'s Workshop",
        location_id: location_id,
        installed_tool_codes: tool_codes
      }

      result =
        case Alchemy.get_workshop_for_character(character.id) do
          nil -> Alchemy.create_workshop(character, attrs)
          workspace -> Alchemy.update_workshop(workspace, attrs)
        end

      case result do
        {:ok, workspace} ->
          {:ok,
           "Alchemy workspace ready at #{location_name_by_id(workspace.location_id)} with tools: #{Enum.join(workspace.installed_tool_codes, ", ")}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not set up alchemy workspace: #{format_changeset(changeset)}"}
      end
    else
      nil -> {:ok, "You must be at a location to set up an alchemy workspace."}
    end
  end

  defp dispatch("alchemy", ["recipes"], _character) do
    recipes = Alchemy.list_recipes()

    if recipes == [] do
      {:ok, "No alchemy recipes are currently registered."}
    else
      {:ok,
       Enum.join(
         ["Alchemy recipes:"] ++
           Enum.map(recipes, fn recipe ->
             "- #{recipe.code}: #{recipe.name} -> #{recipe.result_item_template.name} (#{recipe.brew_time_game_days} game-days, difficulty #{recipe.difficulty})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("alchemy", ["brew", recipe_code], character) do
    dispatch("alchemy", ["brew", recipe_code, "1"], character)
  end

  defp dispatch("alchemy", ["brew", recipe_code, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = workspace <- Alchemy.get_workshop_for_character(character.id),
         %{} = recipe <- Alchemy.get_recipe_by_code(recipe_code),
         {:ok, %{brew_job: brew_job}} <- Alchemy.brew(character, workspace, recipe, quantity) do
      {:ok,
       "Brewing started for #{recipe.name}. Completion: #{Formatter.datetime(brew_job.completes_at)}. Quantity #{brew_job.quantity}."}
    else
      nil ->
        {:ok, "Recipe or workspace not found for brewing request."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start brew: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("alchemy", ["jobs"], character) do
    jobs = Alchemy.list_brew_jobs_for_character(character.id)

    if jobs == [] do
      {:ok, "No brew jobs."}
    else
      {:ok,
       Enum.join(
         ["Brew jobs:"] ++
           Enum.map(jobs, fn brew_job ->
             "- #{brew_job.id}: #{brew_job.recipe.name} x#{brew_job.quantity} (#{brew_job.status})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("alchemy", _args, _character) do
    {:ok,
     "Usage: /alchemy workspace | /alchemy setup [tool1,tool2,...] | /alchemy recipes | /alchemy brew <recipe-code> [quantity] | /alchemy jobs"}
  end

  defp dispatch("craft", ["workspace"], character) do
    case Crafting.get_workshop_for_character(character.id) do
      nil ->
        {:ok,
         "No active crafting workshop. Use /craft setup [tool1,tool2,...] to create one at your current location."}

      workshop ->
        location_name = location_name_by_id(workshop.location_id)

        tools =
          if workshop.installed_tool_codes == [],
            do: "none",
            else: Enum.join(workshop.installed_tool_codes, ", ")

        {:ok,
         Enum.join(
           [
             "Workshop: #{workshop.name}",
             "Location: #{location_name}",
             "Status: #{workshop.status}",
             "Tools: #{tools}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("craft", ["setup"], character) do
    dispatch("craft", ["setup", "forge,anvil"], character)
  end

  defp dispatch("craft", ["setup", tool_codes_csv], character) do
    with %{id: location_id} <- character.current_location do
      tool_codes =
        tool_codes_csv
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      attrs = %{
        name: "#{character.name}'s Workshop",
        location_id: location_id,
        installed_tool_codes: tool_codes
      }

      result =
        case Crafting.get_workshop_for_character(character.id) do
          nil -> Crafting.create_workshop(character, attrs)
          workshop -> Crafting.update_workshop(workshop, attrs)
        end

      case result do
        {:ok, workshop} ->
          {:ok,
           "Crafting workshop ready at #{location_name_by_id(workshop.location_id)} with tools: #{Enum.join(workshop.installed_tool_codes, ", ")}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not set up crafting workshop: #{format_changeset(changeset)}"}
      end
    else
      nil -> {:ok, "You must be at a location to set up a crafting workshop."}
    end
  end

  defp dispatch("craft", ["recipes"], _character) do
    recipes = Crafting.list_recipes()

    if recipes == [] do
      {:ok, "No crafting recipes are currently registered."}
    else
      {:ok,
       Enum.join(
         ["Crafting recipes:"] ++
           Enum.map(recipes, fn recipe ->
             "- #{recipe.code}: #{recipe.name} -> #{recipe.result_item_template.name} (#{recipe.craft_time_game_days} game-days, difficulty #{recipe.difficulty})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("craft", ["build", recipe_code], character) do
    dispatch("craft", ["build", recipe_code, "1"], character)
  end

  defp dispatch("craft", ["build", recipe_code, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = workshop <- Crafting.get_workshop_for_character(character.id),
         %{} = recipe <- Crafting.get_recipe_by_code(recipe_code),
         {:ok, %{craft_job: craft_job}} <- Crafting.craft(character, workshop, recipe, quantity) do
      {:ok,
       "Crafting started for #{recipe.name}. Completion: #{Formatter.datetime(craft_job.completes_at)}. Quantity #{craft_job.quantity}."}
    else
      nil ->
        {:ok, "Recipe or workshop not found for crafting request."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start crafting: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("craft", ["jobs"], character) do
    jobs = Crafting.list_craft_jobs_for_character(character.id)

    if jobs == [] do
      {:ok, "No craft jobs."}
    else
      {:ok,
       Enum.join(
         ["Craft jobs:"] ++
           Enum.map(jobs, fn craft_job ->
             "- #{craft_job.id}: #{craft_job.recipe.name} x#{craft_job.quantity} (#{craft_job.status})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("craft", _args, _character) do
    {:ok,
     "Usage: /craft workshop | /craft setup [tool1,tool2,...] | /craft recipes | /craft build <recipe-code> [quantity] | /craft jobs"}
  end

  defp dispatch("scavenge", [resource_code], character) do
    dispatch("scavenge", [resource_code, "1"], character)
  end

  defp dispatch("scavenge", [resource_code, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{id: location_id} <- character.current_location,
         resource_cache when not is_nil(resource_cache) <-
           Scavenging.available_resource_caches(location_id)
           |> Enum.find(&(&1.resource_code == resource_code)),
         {:ok, %{attempt: attempt}} <-
           Scavenging.start_attempt(character, resource_cache, quantity) do
      {:ok,
       "Scavenging started for #{resource_code}. Completion: #{Formatter.datetime(attempt.completes_at)}. Quantity: #{attempt.quantity_requested}."}
    else
      nil ->
        {:ok, "No available resource named #{resource_code} at your location."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start scavenging: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("scavenge", _args, _character),
    do: {:ok, "Usage: /scavenge <resource_code> [quantity]"}

  defp dispatch("party", ["create" | name_parts], character) do
    name = if name_parts == [], do: nil, else: Enum.join(name_parts, " ")

    case Parties.create_party(character, if(name, do: %{name: name}, else: %{})) do
      {:ok, %{party: party}} ->
        {:ok, "Party created: #{party.name}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not create party: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("party", ["status"], character) do
    case Parties.active_party_for_character(character.id) do
      nil ->
        {:ok, "No active party."}

      party ->
        members = Parties.list_active_members(party)

        {:ok,
         Enum.join(
           [
             "Party: #{party.name}",
             "Members: #{Enum.map_join(members, ", ", & &1.character.name)}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("party", _args, _character),
    do: {:ok, "Usage: /party create [name] | /party status"}

  defp dispatch("club", ["create", club_type | name_parts], character) do
    name = Enum.join(name_parts, " ")

    if name == "" do
      {:ok, "Usage: /club create <type> <name>"}
    else
      case Clubs.create_club(character, %{club_type: club_type, name: name}) do
        {:ok, %{club: club}} ->
          {:ok, "Club created: #{club.name} (#{club.club_type})."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not create club: #{format_changeset(changeset)}"}
      end
    end
  end

  defp dispatch("club", ["list"], character) do
    clubs = Clubs.list_clubs_for_character(character.id)

    if clubs == [] do
      {:ok, "No active clubs."}
    else
      {:ok,
       Enum.join(
         ["Clubs:"] ++
           Enum.map(clubs, fn club ->
             "- #{club.id}: #{club.name} (#{club.club_type})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("club", ["status", club_id], character) do
    with %{} = club <- load_member_club(club_id, character.id) do
      members = Clubs.list_members(club)

      {:ok,
       Enum.join(
         [
           "Club: #{club.name}",
           "Type: #{club.club_type}",
           "Members: #{Enum.map_join(members, ", ", & &1.character.name)}"
         ],
         "\n"
       )}
    else
      nil -> {:ok, "No matching club membership found."}
    end
  end

  defp dispatch("club", ["invite", club_id, handle], character) do
    with %{} = club <- load_leader_club(club_id, character.id),
         %{} = invitee <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, %{invitation: invitation}} <- Clubs.invite_member(club, character, invitee) do
      {:ok, "Invitation #{invitation.id} sent to #{handle}."}
    else
      nil ->
        {:ok, "Club or invitee not found, or you are not the club leader."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not invite member: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["invites"], character) do
    invitations = Clubs.pending_invitations_for_character(character.id)

    if invitations == [] do
      {:ok, "No pending club invitations."}
    else
      {:ok,
       Enum.join(
         ["Pending club invitations:"] ++
           Enum.map(invitations, fn invitation ->
             "- #{invitation.id}: #{invitation.club.name} from #{invitation.inviter_character.name}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("club", ["accept", invitation_id], character) do
    with %{} = invitation <- load_invitation(invitation_id, character.id),
         {:ok, %{club: club}} <- Clubs.accept_invitation(invitation, character) do
      {:ok, "Joined club #{club.name}."}
    else
      nil ->
        {:ok, "No matching pending invitation found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not accept invitation: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["reject", invitation_id], character) do
    with %{} = invitation <- load_invitation(invitation_id, character.id),
         {:ok, _updated_invitation} <- Clubs.reject_invitation(invitation, character) do
      {:ok, "Invitation rejected."}
    else
      nil ->
        {:ok, "No matching pending invitation found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not reject invitation: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["leave", club_id], character) do
    with %{} = club <- load_member_club(club_id, character.id),
         {:ok, updated_club} <- Clubs.leave_club(club, character) do
      {:ok, "Left club #{updated_club.name}."}
    else
      nil ->
        {:ok, "No matching club membership found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not leave club: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", _args, _character) do
    {:ok,
     "Usage: /club create <type> <name> | /club list | /club status <club-id> | /club invite <club-id> <handle> | /club invites | /club accept <invite-id> | /club reject <invite-id> | /club leave <club-id>"}
  end

  defp dispatch("duel", ["challenge", handle, stake_raw], character) do
    stake = parse_positive_integer(stake_raw, 0)

    with %{} = opponent <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, duel} <- PVP.challenge_duel(character, opponent, stake) do
      {:ok, "Duel challenge sent to #{handle}. Duel id #{duel.id}. Stake #{duel.stake_amount}."}
    else
      nil ->
        {:ok, "No character with handle #{handle} found in your realm."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not challenge duel: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["accept", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id, :pending),
         true <- duel.opponent_character_id == character.id,
         {:ok, updated_duel} <- PVP.accept_duel(duel) do
      {:ok, "Duel accepted. Combat #{updated_duel.combat_id} is ready."}
    else
      nil ->
        {:ok, "No matching pending duel found."}

      false ->
        {:ok, "Only the challenged opponent can accept this duel."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not accept duel: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["reject", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id, :pending),
         true <- duel.opponent_character_id == character.id,
         {:ok, _updated_duel} <- PVP.reject_duel(duel, character) do
      {:ok, "Duel rejected."}
    else
      nil ->
        {:ok, "No matching pending duel found."}

      false ->
        {:ok, "Only the challenged opponent can reject this duel."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not reject duel: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["cancel", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id),
         {:ok, _updated_duel} <- PVP.cancel_duel(duel, character) do
      {:ok, "Duel cancelled."}
    else
      nil ->
        {:ok, "No matching duel found."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not cancel duel: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["status"], character) do
    duels = PVP.list_open_duels_for_character(character.id)

    if duels == [] do
      {:ok, "No open duels."}
    else
      {:ok,
       Enum.join(
         ["Open duels:"] ++
           Enum.map(duels, fn duel ->
             opponent_id =
               if duel.challenger_character_id == character.id,
                 do: duel.opponent_character_id,
                 else: duel.challenger_character_id

             "- #{duel.id}: status #{duel.status}, opponent ##{opponent_id}, stake #{duel.stake_amount}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("duel", _args, _character),
    do:
      {:ok,
       "Usage: /duel challenge <handle> <stake> | /duel accept <duel-id> | /duel reject <duel-id> | /duel cancel <duel-id> | /duel status"}

  defp dispatch("expedition", ["start"], character) do
    with %{} = party <- Parties.active_party_for_character(character.id),
         {:ok, %{expedition: expedition}} <- Parties.start_expedition(party) do
      {:ok,
       "Expedition started at #{location_name_by_id(expedition.location_id)}. Food snapshot: #{expedition.food_units_snapshot}. Carry: #{expedition.carried_weight}/#{expedition.carry_capacity}."}
    else
      nil ->
        {:ok, "You need an active party before starting an expedition."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start expedition: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("expedition", ["status"], character) do
    case Parties.active_expedition_for_character(character.id) do
      nil ->
        {:ok, "No active expedition."}

      expedition ->
        members = Parties.active_members_for_expedition(expedition.id)

        {:ok,
         Enum.join(
           [
             "Expedition: #{expedition.id}",
             "Location: #{location_name_by_id(expedition.location_id)}",
             "Members: #{length(members)}",
             "Food snapshot: #{expedition.food_units_snapshot}",
             "Carry: #{expedition.carried_weight}/#{expedition.carry_capacity}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("expedition", _args, _character),
    do: {:ok, "Usage: /expedition start | /expedition status"}

  defp dispatch("dungeon", ["enter"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{id: location_id} <- character.current_location,
         %{} = dungeon <- Dungeons.active_dungeon_at_location(character.realm_id, location_id),
         {:ok, %{run: run}} <- Dungeons.enter_dungeon(expedition, dungeon) do
      {:ok, "Entered dungeon #{dungeon.name}. Current node: #{run.current_node.name}."}
    else
      nil ->
        {:ok, "You must be at an active dungeon entrance with an expedition to enter a dungeon."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not enter dungeon: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["status"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      encounter = Dungeons.current_encounter_for_run(run.id)
      extraction = Dungeons.active_extraction(run.id)

      {:ok,
       Enum.join(
         [
           "Dungeon: #{run.dungeon.name}",
           "Floor: #{run.current_floor.number}",
           "Node: #{run.current_node.slug} — #{run.current_node.name}",
           "Encounter: #{encounter_line(encounter)}",
           "Extraction: #{extraction_line(extraction)}",
           "Steps: #{run.steps_taken}"
         ],
         "\n"
       )}
    else
      nil -> {:ok, "No active dungeon run."}
    end
  end

  defp dispatch("dungeon", ["move", node_slug], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         %{} = node <- Dungeons.get_node_by_slug_in_dungeon(run.dungeon_id, node_slug),
         {:ok, %{run: updated_run}} <- Dungeons.move_run(run, node.id) do
      encounter = Dungeons.current_encounter_for_run(updated_run.id)
      {:ok, "Moved to #{updated_run.current_node.name}. Encounter: #{encounter_line(encounter)}."}
    else
      nil ->
        {:ok, "Node not found in the active dungeon run."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not move in dungeon: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["extract"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{run: updated_run}} <- Dungeons.extract_via_ascent(run) do
      {:ok, "Dungeon extraction complete. Run #{updated_run.id} exited safely."}
    else
      nil ->
        {:ok, "No active dungeon run."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not extract: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["ritual"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{extraction: extraction}} <- Dungeons.start_return_ritual(run, character) do
      {:ok,
       "Return ritual started. Extraction completes at #{Formatter.datetime(extraction.completes_at)}."}
    else
      nil ->
        {:ok, "No active dungeon run."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start return ritual: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["drops"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      drops = Dungeons.list_drops_for_run(run.id)

      if drops == [] do
        {:ok, "No dungeon drops recorded for this run."}
      else
        {:ok,
         Enum.join(
           ["Dungeon drops:"] ++
             Enum.map(drops, fn drop ->
               "- #{drop.id}: #{drop.name} x#{drop.quantity} (#{drop.drop_kind})"
             end),
           "\n"
         )}
      end
    else
      nil -> {:ok, "No active dungeon run."}
    end
  end

  defp dispatch("dungeon", _args, _character),
    do:
      {:ok,
       "Usage: /dungeon enter | /dungeon status | /dungeon move <node-slug> | /dungeon extract | /dungeon ritual | /dungeon drops"}

  defp dispatch("encounter", ["status"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      encounter = Dungeons.current_encounter_for_run(run.id)
      {:ok, "Encounter: #{encounter_line(encounter)}"}
    else
      nil -> {:ok, "No active dungeon encounter."}
    end
  end

  defp dispatch("encounter", ["fight"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         %{} = encounter <- Dungeons.current_encounter_for_run(run.id),
         {:ok, %{combat: combat}} <- Dungeons.start_encounter_combat(encounter) do
      {:ok,
       "Encounter combat started. Combat id #{combat.id}. Use /combat status and /combat cast <spell-id>."}
    else
      nil ->
        {:ok, "No active encounter available to fight."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not start encounter combat: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("encounter", _args, _character),
    do: {:ok, "Usage: /encounter status | /encounter fight"}

  defp dispatch("spells", _args, character) do
    case Grimoires.active_grimoire_for_character(character.id) do
      nil ->
        {:ok, "No active grimoire."}

      grimoire ->
        grimoire = Grimoires.get_grimoire!(grimoire.id)

        if grimoire.entries == [] do
          {:ok, "Active grimoire is empty."}
        else
          {:ok,
           Enum.join(
             ["Prepared spells:"] ++
               Enum.map(grimoire.entries, fn entry ->
                 "- #{entry.spell.id}: #{entry.spell.name} (#{entry.spell.school})"
               end),
             "\n"
           )}
        end
    end
  end

  defp dispatch("combat", ["status"], character) do
    case Combat.active_combat_for_character(character.id) do
      nil ->
        {:ok, "No active combat."}

      combat ->
        {:ok,
         Enum.join(
           [
             "Combat: #{combat.kind}",
             "Turn: #{combat.turn_number}",
             "Status: #{combat.status}",
             "Party HP: #{(combat.sides["party"] && combat.sides["party"]["shared_hp"]) || (combat.sides["attackers"] && combat.sides["attackers"]["shared_hp"])}",
             "Enemy HP: #{(combat.sides["encounter"] && combat.sides["encounter"]["shared_hp"]) || (combat.sides["defenders"] && combat.sides["defenders"]["shared_hp"])}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("combat", ["cast", spell_id], character) do
    with %{} = combat <- Combat.active_combat_for_character(character.id),
         participant when not is_nil(participant) <-
           Enum.find(combat.participants, &(&1.character_id == character.id)),
         {:ok, _action} <-
           Combat.submit_action(combat, participant.id, %{
             action_type: :cast_spell,
             spell_id: spell_id,
             target_side: combat_target_side(combat, participant.side)
           }) do
      {:ok, "Spell queued for combat turn #{combat.turn_number}."}
    else
      nil ->
        {:ok, "No active combat or no combat participant for this character."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not queue spell: #{format_changeset(changeset)}"}

      {:error, reason} ->
        {:ok, "Could not queue spell: #{inspect(reason)}"}
    end
  end

  defp dispatch("combat", ["wait"], character) do
    with %{} = combat <- Combat.active_combat_for_character(character.id),
         participant when not is_nil(participant) <-
           Enum.find(combat.participants, &(&1.character_id == character.id)),
         {:ok, _action} <- Combat.submit_action(combat, participant.id, %{action_type: :wait}) do
      {:ok, "Wait action queued for combat turn #{combat.turn_number}."}
    else
      nil ->
        {:ok, "No active combat or no combat participant for this character."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not queue wait action: #{format_changeset(changeset)}"}

      {:error, reason} ->
        {:ok, "Could not queue wait action: #{inspect(reason)}"}
    end
  end

  defp dispatch("combat", ["resolve"], character) do
    with %{} = combat <- Combat.active_combat_for_character(character.id),
         true <- combat.status == :locked or combat.status == :active_turn,
         {:ok, resolved_combat} <- Combat.resolve_turn(combat) do
      case resolved_combat do
        %{status: :finished, kind: :dungeon_encounter} = finished_combat ->
          {:ok, _result} = Dungeons.sync_encounter_combat(finished_combat)
          {:ok, combat_resolution_text(finished_combat)}

        %{status: :finished, kind: :duel} = finished_combat ->
          if finished_combat.metadata["duel_id"] || finished_combat.metadata[:duel_id] do
            {:ok, _result} = PVP.settle_duel_from_combat(finished_combat)
          end

          {:ok, combat_resolution_text(finished_combat)}

        finished_combat ->
          {:ok, combat_resolution_text(finished_combat)}
      end
    else
      nil ->
        {:ok, "No active combat."}

      false ->
        {:ok, "Combat is not ready to resolve yet."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Could not resolve combat: #{format_changeset(changeset)}"}

      {:error, reason} ->
        {:ok, "Could not resolve combat: #{inspect(reason)}"}
    end
  end

  defp dispatch("combat", _args, _character),
    do: {:ok, "Usage: /combat status | /combat cast <spell-id> | /combat wait | /combat resolve"}

  defp dispatch("admin", ["status"], character) do
    if operator_authorized?(character) do
      report = Operator.system_report()

      {:ok,
       Enum.join(
         [
           "System report:",
           "Realms: #{report.realms}",
           "Characters: #{report.characters}",
           "Locations: #{report.locations}",
           "Routes: #{report.routes}",
           "Journeys: #{report.active_journeys}",
           "Migrations: #{report.active_migrations}",
           "Enrollments: #{report.active_enrollments}",
           "Brew jobs: #{report.active_brew_jobs}",
           "Craft jobs: #{report.active_craft_jobs}",
           "Active bases: #{report.active_bases}",
           "Building bases: #{report.building_bases}",
           "Clubs: #{report.active_clubs}",
           "Pending club invites: #{report.pending_club_invitations}",
           "Scavenges: #{report.active_scavenge_attempts}",
           "Expeditions: #{report.active_expeditions}",
           "Runs: #{report.active_runs}",
           "Combats: #{report.active_combats}",
           "Listings: #{report.active_market_listings}",
           "Market bans: #{report.active_market_bans}",
           "Open crimes: #{report.open_crimes}",
           "Pending notifications: #{report.pending_notifications}",
           "Treasury total: #{report.treasury_balance_total}",
           "Character balances: #{report.character_balance_total}"
         ],
         "\n"
       )}
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["realm", realm_slug], character) do
    if operator_authorized?(character) do
      case Operator.realm_report(realm_slug) do
        {:ok, report} ->
          {:ok,
           Enum.join(
             [
               "Realm #{report.realm.slug} — #{report.realm.name}",
               "Characters: #{report.characters}",
               "Locations: #{report.locations}",
               "Routes: #{report.routes}",
               "Journeys: #{report.active_journeys}",
               "Migrations: #{report.active_migrations}",
               "Enrollments: #{report.active_enrollments}",
               "Brew jobs: #{report.active_brew_jobs}",
               "Craft jobs: #{report.active_craft_jobs}",
               "Active bases: #{report.active_bases}",
               "Building bases: #{report.building_bases}",
               "Clubs: #{report.active_clubs}",
               "Pending club invites: #{report.pending_club_invitations}",
               "Scavenges: #{report.active_scavenge_attempts}",
               "Expeditions: #{report.active_expeditions}",
               "Runs: #{report.active_runs}",
               "Combats: #{report.active_combats}",
               "Listings: #{report.active_market_listings}",
               "Market bans: #{report.active_market_bans}",
               "Open crimes: #{report.open_crimes}",
               "Treasury: #{report.treasury_balance}",
               "Character balances: #{report.character_balance_total}"
             ],
             "\n"
           )}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not load realm report: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["sweep"], character) do
    if operator_authorized?(character) do
      case Operator.maintenance_sweep(actor_handle: operator_handle(character)) do
        {:ok, %{summary: summary}} ->
          {:ok,
           Enum.join(
             [
               "Maintenance sweep complete:",
               "Completed journeys: #{summary.completed_journeys}",
               "Completed migrations: #{summary.completed_migrations}",
               "Completed enrollments: #{summary.completed_enrollments}",
               "Completed brew jobs: #{summary.completed_brew_jobs}",
               "Completed craft jobs: #{summary.completed_craft_jobs}",
               "Completed bases: #{summary.completed_bases}",
               "Completed scavenges: #{summary.completed_attempts}",
               "Refreshed caches: #{summary.refreshed_resource_caches}"
             ],
             "\n"
           )}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not run maintenance sweep: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["federation", "manifest"], character) do
    if operator_authorized?(character) do
      manifest = Federation.export_realm_manifest(Federation.local_realm!())

      {:ok,
       Enum.join(
         [
           "Local realm manifest:",
           "Slug: #{manifest.slug}",
           "Name: #{manifest.name}",
           "Currency: #{manifest.currency_code || "unknown"}",
           "Endpoint: #{manifest.public_endpoint || "unset"}",
           "Population: #{manifest.population_hint}",
           "Magic scope: #{manifest.ruleset["magic_scope"]}"
         ],
         "\n"
       )}
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["federation", "register", manifest_url], character) do
    dispatch("admin", ["federation", "register", manifest_url, ""], character)
  end

  defp dispatch("admin", ["federation", "register", manifest_url, access_token], character) do
    if operator_authorized?(character) do
      token = if access_token == "", do: nil, else: access_token

      case Federation.register_remote_realm(manifest_url, token) do
        {:ok, remote_realm} ->
          {:ok,
           "Registered remote realm #{remote_realm.slug} at #{remote_realm.public_endpoint}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not register remote realm: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["federation", "sync", realm_slug], character) do
    if operator_authorized?(character) do
      with %{} = remote_realm <- Federation.get_remote_realm_by_slug(realm_slug),
           {:ok, updated_remote_realm} <- Federation.sync_remote_realm(remote_realm) do
        {:ok,
         "Synced remote realm #{updated_remote_realm.slug}. Population #{updated_remote_realm.population_hint}."}
      else
        nil ->
          {:ok, "No remote realm with slug #{realm_slug} found."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not sync remote realm: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["profile", handle], character) do
    if operator_authorized?(character) do
      with %{} = target <- Accounts.get_character_by_handle(character.realm_id, handle) do
        profile = Reputation.profile_for_character(target.id)
        crimes = Reputation.list_crimes_for_character(target.id) |> Enum.take(3)

        {:ok,
         Enum.join(
           [
             "Profile for #{handle}:",
             "Reputation: #{(profile && profile.reputation_score) || 0}",
             "Crimes: #{(profile && profile.crime_count) || 0}",
             "Outstanding fines: #{(profile && profile.outstanding_fine) || 0}",
             "NPC hostility: #{(profile && profile.npc_hostility_level) || 0}",
             "Market ban until: #{(profile && profile.market_ban_until && Formatter.datetime(profile.market_ban_until)) || "none"}",
             "Recent crimes: #{recent_crimes_line(crimes)}"
           ],
           "\n"
         )}
      else
        nil -> {:ok, "No character with handle #{handle} found in your realm."}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", ["crime", handle, crime_type, severity_raw], character) do
    dispatch("admin", ["crime", handle, crime_type, severity_raw, "0"], character)
  end

  defp dispatch("admin", ["crime", handle, crime_type, severity_raw, fine_raw], character) do
    if operator_authorized?(character) do
      severity = parse_positive_integer(severity_raw, 0)
      fine_amount = parse_non_negative_integer(fine_raw, 0)

      with %{} = target <- Accounts.get_character_by_handle(character.realm_id, handle),
           {:ok, %{crime_record: crime_record}} <-
             Reputation.record_crime(target, crime_type, %{
               severity: severity,
               fine_amount: fine_amount,
               metadata: %{"source" => "operator_command", "actor" => operator_handle(character)}
             }) do
        {:ok,
         "Crime recorded for #{handle}. Type #{crime_record.crime_type}, severity #{crime_record.severity}, fine #{crime_record.fine_amount}."}
      else
        nil ->
          {:ok, "No character with handle #{handle} found in your realm."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Could not record crime: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Unauthorized."}
    end
  end

  defp dispatch("admin", _args, _character),
    do:
      {:ok,
       "Usage: /admin status | /admin realm <slug> | /admin sweep | /admin federation manifest | /admin federation register <manifest-url> [token] | /admin federation sync <realm-slug> | /admin profile <handle> | /admin crime <handle> <crime_type> <severity> [fine]"}

  defp dispatch(_command, _args, _character) do
    {:ok, "Unknown command. Use /help."}
  end

  defp parse_command(text) do
    text = String.trim(text)

    if text == "" or not String.starts_with?(text, "/") do
      :ignore
    else
      [raw_command | args] = String.split(text, ~r/\s+/, trim: true)

      command =
        raw_command |> String.trim_leading("/") |> String.split("@") |> hd() |> String.downcase()

      {:ok, command, args}
    end
  end

  defp load_character(character_id) do
    character_id
    |> Accounts.get_character!()
    |> Repo.preload([:current_location, :account])
  end

  defp location_name(%Character{current_location: nil}), do: "Unknown"
  defp location_name(%Character{current_location: location}), do: location.name

  defp location_name_by_id(location_id) do
    Worlds.get_location!(location_id).name
  rescue
    Ecto.NoResultsError -> "Unknown"
  end

  defp journey_status(nil), do: "None"

  defp journey_status(journey),
    do:
      "To #{location_name_by_id(journey.to_location_id)} (arrives #{Formatter.datetime(journey.arrival_at)})"

  defp academy_status(nil, nil), do: "None"

  defp academy_status(enrollment, nil) when not is_nil(enrollment),
    do: "Enrollment #{enrollment.program_type} (#{enrollment.status})"

  defp academy_status(nil, specialization), do: "#{specialization.track}"

  defp academy_status(enrollment, specialization),
    do: "#{enrollment.program_type} / #{specialization.track}"

  defp academy_enrollment_line(nil), do: "none"

  defp academy_enrollment_line(enrollment),
    do: "#{enrollment.program_type} (#{enrollment.status})"

  defp academy_specialization_line(nil), do: "none"
  defp academy_specialization_line(specialization), do: specialization.track |> to_string()

  defp party_status(nil), do: "None"
  defp party_status(party), do: party.name
  defp expedition_status(nil), do: "None"

  defp expedition_status(expedition),
    do: "#{expedition.expedition_type} at #{location_name_by_id(expedition.location_id)}"

  defp dungeon_status(nil), do: "None"
  defp dungeon_status(run), do: "#{run.dungeon.name} / #{run.current_node.name}"

  defp route_destination(route, current_location_id) do
    cond do
      route.origin_location_id == current_location_id -> route.destination_location
      route.destination_location_id == current_location_id -> route.origin_location
      true -> route.destination_location
    end
  end

  defp encounter_line(nil), do: "none"
  defp encounter_line(encounter), do: "#{encounter.encounter_kind} (#{encounter.status})"

  defp extraction_line(nil), do: "none"
  defp extraction_line(extraction), do: "#{extraction.extraction_type} (#{extraction.status})"

  defp combat_target_side(combat, participant_side) do
    combat.sides
    |> Map.keys()
    |> Enum.find(fn side -> side != participant_side end)
  end

  defp combat_resolution_text(combat) do
    "Combat resolved. Turn #{combat.turn_number}, status #{combat.status}, winner #{combat.winner_side || "none"}."
  end

  defp operator_authorized?(%Character{} = character) do
    Operator.operator_handle?(operator_handle(character))
  end

  defp operator_handle(%Character{} = character) do
    (character.account && character.account.handle) ||
      Accounts.get_account!(character.account_id).handle
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  defp parse_non_negative_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> default
    end
  end

  defp load_owned_duel(duel_id, character_id, status \\ nil) do
    duel = PVP.get_duel!(duel_id)

    cond do
      character_id not in [duel.challenger_character_id, duel.opponent_character_id] -> nil
      is_nil(status) -> duel
      duel.status == status -> duel
      true -> nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_owned_base(base_id, character_id) do
    base = Bases.get_base!(base_id)
    if base.owner_character_id == character_id, do: base, else: nil
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_member_club(club_id, character_id) do
    club = Clubs.get_club!(club_id)

    if Enum.any?(club.memberships, &(&1.character_id == character_id and &1.status == :active)) do
      club
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_leader_club(club_id, character_id) do
    club = load_member_club(club_id, character_id)

    if club &&
         Enum.any?(
           club.memberships,
           &(&1.character_id == character_id and &1.role == :leader and &1.status == :active)
         ) do
      club
    else
      nil
    end
  end

  defp load_invitation(invitation_id, character_id) do
    invitation =
      ClubInvitation
      |> Repo.get!(invitation_id)
      |> Repo.preload([:club, :inviter_character])

    if invitation.invitee_character_id == character_id and invitation.status == :pending do
      invitation
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_owned_inventory_item(inventory_item_id, character_id) do
    inventory_item = Inventory.get_inventory_item!(inventory_item_id)
    if inventory_item.character_id == character_id, do: inventory_item, else: nil
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_storage_item_for_base(storage_item_id, base_id) do
    storage_item = Bases.get_storage_item!(storage_item_id)
    if storage_item.base_id == base_id, do: storage_item, else: nil
  rescue
    Ecto.NoResultsError -> nil
  end

  defp recent_crimes_line([]), do: "none"

  defp recent_crimes_line(crimes) do
    Enum.map_join(crimes, ", ", fn crime ->
      "#{crime.crime_type}(sev #{crime.severity})"
    end)
  end

  defp format_changeset(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
