defmodule MMGO.Telegram.Commands do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts
  alias MMGO.Accounts.{Character, SpecialProfiles}
  alias MMGO.Academy
  alias MMGO.Academia
  alias MMGO.Alchemy
  alias MMGO.Bases
  alias MMGO.Clubs
  alias MMGO.Clubs.Invitation, as: ClubInvitation
  alias MMGO.Combat
  alias MMGO.Combat.{Turn, TurnArtifacts}
  alias MMGO.Combat.Resolution, as: CombatResolution
  alias MMGO.Crafting
  alias MMGO.Dungeons
  alias MMGO.Events
  alias MMGO.Federation
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.NPCShops
  alias MMGO.Operator
  alias MMGO.Organizations
  alias MMGO.Overworld
  alias MMGO.Parties
  alias MMGO.Play
  alias MMGO.Progression
  alias MMGO.PVP
  alias MMGO.Reputation
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Survival
  alias MMGO.Telegram.ChangesetErrors
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
    location =
      (character.current_location && character.current_location.name) || "место не определено"

    {:ok,
     [
       "#{character.name}, персонаж готов.",
       "Сейчас вы в локации «#{location}».",
       "Основная игра — в Mini App: там видны контекст, доступные действия и их результат.",
       "Бот оставлен для быстрых проверок. /help — короткий список команд."
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("play", _args, character) do
    {:ok, "Открываю MMGO для #{character.name}. Продолжайте игру кнопкой ниже."}
  end

  defp dispatch("help", _args, _character) do
    {:ok,
     [
       "Быстрые команды:",
       "/play — открыть игру",
       "/status — понять, где вы и что делать дальше",
       "/inventory — проверить вещи и ресурсы",
       "/routes — посмотреть соседние направления",
       "/journey — проверить текущий переход",
       "/spells — посмотреть подготовленные заклинания",
       "",
       "Выборы, торговля, риск и другие игровые действия доступны в Mini App."
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("status", _args, character) do
    journey = Travel.active_journey(character.id)
    carry = Survival.carried_weight(character)
    carry_capacity = Survival.carry_capacity(character)
    food_units = Survival.food_units_available(character)

    lines = [
      "#{character.name} · уровень #{character.level} · опыт #{character.xp}",
      "Локация: #{location_name(character)}",
      "Еда: #{food_units}",
      "Груз: #{carry}/#{carry_capacity}",
      "Сейчас: #{journey_status(journey)}",
      "Следующий шаг: #{telegram_next_step(journey)}"
    ]

    {:ok, Enum.join(lines, "\n")}
  end

  defp dispatch("inventory", _args, character) do
    items = Inventory.list_inventory_for_character(character.id)

    body =
      if items == [] do
        ["Пока ничего нет."]
      else
        Enum.map(items, fn item ->
          available = Inventory.available_quantity(item)
          reserved = item.reserved_quantity
          suffix = if reserved > 0, do: " (зарезервировано: #{reserved})", else: ""
          "- #{item.item_template.name}: #{available}/#{item.quantity}#{suffix}"
        end)
      end

    {:ok, Enum.join(["С собой:"] ++ body, "\n")}
  end

  defp dispatch("event", ["current"], character) do
    case Events.current_event(character) do
      nil ->
        {:ok, "Сейчас нет активного события."}

      event ->
        options = Enum.sort_by(event.template.options, & &1.position)

        {:ok,
         Enum.join(
           [event.template.title, event.template.body, "Варианты:"] ++
             Enum.map(options, fn option ->
               "- #{option.code}: #{option.label}"
             end),
           "\n"
         )}
    end
  end

  defp dispatch("event", ["choose", option_code], character) do
    with %{} = event <- Events.current_event(character),
         {:ok, %{option: option}} <- Events.resolve_option(event, option_code) do
      {:ok, option.result_text}
    else
      nil ->
        {:ok, "Сейчас нет активного события."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось выбрать вариант события: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("event", _args, _character),
    do: {:ok, "Формат: /event current | /event choose <option-code>"}

  defp dispatch("progression", ["milestones"], character) do
    grants = Progression.list_reward_grants(character.id)
    milestones = Progression.list_milestones()

    if milestones == [] do
      {:ok, "Этапы развития пока не настроены."}
    else
      claimed = MapSet.new(Enum.map(grants, & &1.milestone_id))

      {:ok,
       Enum.join(
         ["Этапы развития:"] ++
           Enum.map(milestones, fn milestone ->
             status = if MapSet.member?(claimed, milestone.id), do: "получено", else: "закрыто"
             "- уровень #{milestone.level}: #{milestone.title} (#{status})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("progression", _args, _character),
    do: {:ok, "Формат: /progression milestones"}

  defp dispatch("routes", _args, character) do
    with %{id: location_id} = location <- character.current_location do
      routes = Worlds.list_routes_for_location(location_id)

      if routes == [] do
        {:ok, "Из локации «#{location.name}» сейчас нет доступных маршрутов."}
      else
        {:ok,
         Enum.join(
           ["Куда можно отправиться из локации «#{location.name}»:"] ++
             Enum.map(routes, fn route ->
               destination = route_destination(route, location_id)

               "- #{destination.name} — #{route.travel_days} дн., риск #{route.risk_level}"
             end) ++
             ["", "Маршрут выбирается на карте в MMGO."],
           "\n"
         )}
      end
    else
      nil -> {:ok, "Текущая локация ещё не определена."}
    end
  end

  defp dispatch("road", ["encounter", handle], character) do
    with %{} = target <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, encounter} <- Overworld.create_encounter(character, target) do
      {:ok, "Дорожная встреча создана: #{encounter.id}. Проверить: /road status."}
    else
      nil ->
        {:ok, "В вашем мире не найден персонаж с именем #{handle}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось создать встречу: #{format_changeset(changeset)}"}

      {:error, _reason} ->
        {:ok, "Сейчас нельзя создать встречу с этим путником."}
    end
  end

  defp dispatch("road", ["talk", handle], character) do
    with %{} = target <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, %{encounter: encounter}} <-
           Play.request_traveler_contact(character, target.id) do
      {:ok, "Запрос на обмен Telegram-контактами отправлен. Встреча: #{encounter.id}."}
    else
      nil ->
        {:ok, "В вашем мире не найден персонаж с именем #{handle}."}

      {:error, _reason} ->
        {:ok, "Сейчас нельзя отправить этому путнику запрос на обмен контактами."}
    end
  end

  defp dispatch("road", ["status"], character) do
    encounters = Overworld.list_open_encounters_for_character(character.id)

    if encounters == [] do
      {:ok, "Сейчас нет активных дорожных встреч."}
    else
      {:ok,
       Enum.join(
         ["Дорожные встречи:"] ++
           Enum.map(encounters, fn encounter ->
             other_character =
               if encounter.initiator_character_id == character.id,
                 do: encounter.target_character.name,
                 else: encounter.initiator_character.name

             "- #{encounter.id}: #{status_label(encounter.status)} · #{other_character} · #{encounter.location.name}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("road", [action, encounter_id], character)
       when action in ["greet", "trade", "attack", "avoid"] do
    with %{} = encounter <- load_overworld_encounter(encounter_id, character.id),
         {:ok, result} <- Overworld.respond(encounter, character, action) do
      {:ok, road_response_text(action, result)}
    else
      nil ->
        {:ok, "Подходящая дорожная встреча не найдена."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось выполнить действие во встрече: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("road", [decision, encounter_id], character)
       when decision in ["accept", "reject"] do
    contact_decision = if decision == "accept", do: "accept", else: "decline"

    case Play.respond_to_traveler_contact(character, encounter_id, contact_decision) do
      {:ok, %{encounter: encounter}} ->
        {:ok, traveler_contact_response_text(decision, encounter)}

      {:error, _reason} ->
        {:ok, "Этот запрос на обмен контактами уже недоступен."}
    end
  end

  defp dispatch("road", _args, _character) do
    {:ok,
     "Формат: /road talk <handle> | /road accept <encounter-id> | /road reject <encounter-id> | /road encounter <handle> | /road status | /road greet <encounter-id> | /road trade <encounter-id> | /road attack <encounter-id> | /road avoid <encounter-id>"}
  end

  defp dispatch("travel", [destination_slug], character) do
    with %{id: location_id} <- character.current_location,
         route when not is_nil(route) <-
           Worlds.route_from_location_to_slug(location_id, destination_slug),
         {:ok, %{journey: journey}} <- Travel.start_journey(character, route) do
      {:ok,
       "Путь к #{destination_slug} начат. Прибытие: #{Formatter.datetime(journey.arrival_at)}. Потрачено еды: #{journey.food_units_consumed}."}
    else
      nil ->
        {:ok, "Из текущей локации нет прямого маршрута к #{destination_slug}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать путь: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("travel", _args, _character), do: {:ok, "Формат: /travel <location-slug>"}

  defp dispatch("journey", _args, character) do
    case Travel.active_journey(character.id) do
      nil ->
        {:ok, "Сейчас вы никуда не переходите. Откройте карту MMGO, чтобы выбрать направление."}

      journey ->
        journey = Repo.preload(journey, [:from_location, :to_location])

        {:ok,
         "Путь: #{journey.from_location.name} → #{journey.to_location.name}\nПрибытие: #{Formatter.datetime(journey.arrival_at)}\nПотрачено еды: #{journey.food_units_consumed}"}
    end
  end

  defp dispatch("realms", ["list"], _character) do
    realms = Federation.list_remote_realms()

    if realms == [] do
      {:ok, "Другие доступные миры не найдены."}
    else
      {:ok,
       Enum.join(
         ["Доступные миры:"] ++
           Enum.map(realms, fn realm ->
             currency = realm.currency_code || "валюта не указана"
             endpoint = realm.public_endpoint || "адрес не указан"
             population = realm.population_hint || 1
             "- #{realm.slug}: #{realm.name} (#{currency}, население #{population}, #{endpoint})"
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
       "Расчёт обмена: #{amount} #{origin_realm.currency_code || "исходная валюта"} → #{quote.converted_amount} #{destination_realm.currency_code || "целевая валюта"}. Население исходного мира: #{quote.source_population}, целевого: #{quote.destination_population}."}
    else
      nil ->
        {:ok, "Мир с кодом #{realm_slug} не найден."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось рассчитать обмен при переселении: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("realms", ["migrate", realm_slug, amount_raw], character) do
    amount = parse_positive_integer(amount_raw, 0)

    with %{} = destination_realm <- Federation.get_remote_realm_by_slug(realm_slug),
         {:ok, %{migration: migration, remote_response: remote_response}} <-
           Federation.start_migration(character, destination_realm, amount) do
      {:ok,
       "Переселение в мир «#{destination_realm.name}» начато. Персонаж в новом мире: #{remote_response["destination_character_name"]}. Ограничение закончится #{Formatter.datetime(migration.freeze_ends_at)}."}
    else
      nil ->
        {:ok, "Мир с кодом #{realm_slug} не найден."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать переселение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("realms", ["migrations"], character) do
    migrations = Federation.list_migrations_for_account(character.account_id)

    if migrations == [] do
      {:ok, "Переселений между мирами нет."}
    else
      {:ok,
       Enum.join(
         ["Переселения между мирами:"] ++
           Enum.map(migrations, fn migration ->
             destination_slug =
               (migration.remote_realm && migration.remote_realm.slug) ||
                 (migration.destination_realm && migration.destination_realm.slug) || "неизвестно"

             "- #{migration.id}: #{migration.origin_realm.slug} → #{destination_slug} (#{status_label(migration.status)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("realms", _args, _character) do
    {:ok,
     "Формат: /realms list | /realms quote <realm-slug> <amount> | /realms migrate <realm-slug> <amount> | /realms migrations"}
  end

  defp dispatch("academy", ["status"], character) do
    enrollment = Academy.current_enrollment(character.id)
    specialization = Academy.active_specialization(character.id)

    {:ok,
     [
       "Обучение: #{academy_enrollment_line(enrollment)}",
       "Специализация: #{academy_specialization_line(specialization)}"
     ]
     |> Enum.join("\n")}
  end

  defp dispatch("academy", ["start", "basic"], character) do
    case Academy.begin_basic_education(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Базовое образование начато. Завершение: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать базовое образование: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "wizardry", school1, school2], character) do
    case Academy.start_academy_track(character, :wizardry, %{
           primary_school: school1,
           secondary_school: school2
         }) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Обучение чародейству начато. Завершение: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать обучение чародейству: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", track], character) when track in ["alchemy", "mastery"] do
    case Academy.start_academy_track(character, String.to_existing_atom(track)) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Направление «#{academy_track_label(track)}» начато. Завершение: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok,
         "Не удалось начать направление «#{academy_track_label(track)}»: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "extended"], character) do
    case Academy.start_extended_study(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Углублённое обучение начато. Завершение: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать углублённое обучение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["start", "academia"], character) do
    case Academy.start_academia(character) do
      {:ok, %{enrollment: enrollment}} ->
        {:ok,
         "Академическая ступень начата. Завершение: #{Formatter.datetime(enrollment.expected_completion_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать академическую ступень: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", ["tuition", amount_raw], character) do
    amount = parse_positive_integer(amount_raw, 0)

    case NPCShops.pay_tuition(character, amount) do
      {:ok, _result} ->
        {:ok, "Внесена плата за обучение: #{amount}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось оплатить обучение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academy", _args, _character) do
    {:ok,
     "Формат: /academy status | /academy start basic|wizardry <school1> <school2>|alchemy|mastery|extended|academia | /academy tuition <amount>"}
  end

  defp dispatch("academia", ["projects"], character) do
    projects = Academia.list_projects_for_character(character.id)

    if projects == [] do
      {:ok, "Исследовательских проектов нет."}
    else
      {:ok,
       Enum.join(
         ["Исследовательские проекты:"] ++
           Enum.map(projects, fn project ->
             "- #{project.id}: #{project_kind_label(project.project_kind)} · #{project.title} (#{status_label(project.status)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("academia", ["start", project_kind | title_parts], character) do
    title = Enum.join(title_parts, " ")

    if title == "" do
      {:ok, "Формат: /academia start <spell|potion|tool|thesis|course> <title>"}
    else
      case Academia.start_project(character, project_kind, title) do
        {:ok, %{project: project}} ->
          {:ok,
           "Исследование «#{project.title}» начато. Завершение: #{Formatter.datetime(project.completes_at)}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось начать исследование: #{format_changeset(changeset)}"}
      end
    end
  end

  defp dispatch("academia", ["professor"], character) do
    case Academia.appoint_professor(character) do
      {:ok, professor} ->
        {:ok, "Звание профессора присвоено #{Formatter.datetime(professor.appointed_at)}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось присвоить звание профессора: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("academia", ["publish-course" | title_parts], character) do
    title = Enum.join(title_parts, " ")

    if title == "" do
      {:ok, "Формат: /academia publish-course <title>"}
    else
      case Academia.publish_course(character, title) do
        {:ok, publication} ->
          {:ok, "Курс опубликован: #{publication.title}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось опубликовать курс: #{format_changeset(changeset)}"}
      end
    end
  end

  defp dispatch("academia", _args, _character) do
    {:ok,
     "Формат: /academia projects | /academia start <spell|potion|tool|thesis|course> <title> | /academia professor | /academia publish-course <title>"}
  end

  defp dispatch("base", ["status"], character) do
    bases = Bases.list_bases_for_character(character.id)

    if bases == [] do
      {:ok, "У вас пока нет баз."}
    else
      {:ok,
       Enum.join(
         ["Ваши базы:"] ++
           Enum.map(bases, fn base ->
             "- #{base.id}: #{base.name} · #{base.location.name} (#{status_label(base.status)}, вместимость #{base.storage_weight_capacity}, занято #{Bases.storage_weight(base)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("base", ["buy", location_slug], character) do
    with %{} = location <- Worlds.get_location_by_slug(character.realm_id, location_slug),
         {:ok, base} <- Bases.purchase_city_base(character, location) do
      {:ok, "База «#{base.name}» куплена в локации «#{location.name}»."}
    else
      nil ->
        {:ok, "В вашем мире не найдена локация с кодом #{location_slug}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось купить базу: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", ["build", location_slug], character) do
    with %{} = location <- Worlds.get_location_by_slug(character.realm_id, location_slug),
         {:ok, %{base: base}} <- Bases.start_custom_base_build(character, location) do
      {:ok,
       "Строительство базы в локации «#{location.name}» начато. Готовность: #{Formatter.datetime(base.ready_at)}."}
    else
      nil ->
        {:ok, "В вашем мире не найдена локация с кодом #{location_slug}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать строительство базы: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", ["storage", base_id], character) do
    with %{} = base <- load_owned_base(base_id, character.id) do
      items = Bases.list_storage_items(base.id)

      if items == [] do
        {:ok, "Хранилище базы пусто."}
      else
        {:ok,
         Enum.join(
           ["Хранилище базы «#{base.name}»:"] ++
             Enum.map(items, fn item ->
               "- #{item.id}: #{item.item_template.name} x#{item.quantity}"
             end),
           "\n"
         )}
      end
    else
      nil -> {:ok, "Ваша база с таким идентификатором не найдена."}
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
      {:ok, "В хранилище базы «#{base.name}» помещено: #{quantity} ед."}
    else
      nil ->
        {:ok, "База или предмет в инвентаре не найдены."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось поместить предмет в хранилище: #{format_changeset(changeset)}"}
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
      {:ok, "Из хранилища базы «#{base.name}» забрано: #{quantity} ед."}
    else
      nil ->
        {:ok, "База или предмет в хранилище не найдены."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось забрать предмет из хранилища: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("base", _args, _character) do
    {:ok,
     "Формат: /base status | /base buy <location-slug> | /base build <location-slug> | /base storage <base-id> | /base deposit <base-id> <inventory-item-id> [quantity] | /base withdraw <base-id> <storage-item-id> [quantity]"}
  end

  defp dispatch("alchemy", ["workspace"], character) do
    case Alchemy.get_workshop_for_character(character.id) do
      nil ->
        {:ok,
         "Нет действующей алхимической мастерской. Создать её в текущей локации: /alchemy setup [tool1,tool2,...]."}

      workspace ->
        location_name = location_name_by_id(workspace.location_id)

        tools =
          if workspace.installed_tool_codes == [],
            do: "нет",
            else: tool_codes_label(workspace.installed_tool_codes)

        {:ok,
         Enum.join(
           [
             "Мастерская: #{workspace.name}",
             "Локация: #{location_name}",
             "Состояние: #{status_label(workspace.status)}",
             "Инструменты: #{tools}"
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
        name: "Мастерская #{character.name}",
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
           "Алхимическая мастерская готова в локации «#{location_name_by_id(workspace.location_id)}». Инструменты: #{tool_codes_label(workspace.installed_tool_codes)}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось устроить алхимическую мастерскую: #{format_changeset(changeset)}"}
      end
    else
      nil -> {:ok, "Чтобы устроить алхимическую мастерскую, нужно находиться в локации."}
    end
  end

  defp dispatch("alchemy", ["recipes"], character) do
    recipes = Alchemy.list_recipes_for_character(character)

    if recipes == [] do
      {:ok, "Алхимические рецепты пока не зарегистрированы."}
    else
      {:ok,
       Enum.join(
         ["Алхимические рецепты:"] ++
           Enum.map(recipes, fn recipe ->
             "- #{recipe.code}: #{recipe.name} → #{recipe.result_item_template.name} (#{recipe.brew_time_game_days} игровых дн., сложность #{recipe.difficulty})"
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
       "Зелье «#{recipe.name}» поставлено вариться. Готовность: #{Formatter.datetime(brew_job.completes_at)}. Количество: #{brew_job.quantity}."}
    else
      nil ->
        {:ok, "Для варки не найдены рецепт или мастерская."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать варку: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("alchemy", ["jobs"], character) do
    jobs = Alchemy.list_brew_jobs_for_character(character.id)

    if jobs == [] do
      {:ok, "Сейчас ничего не варится."}
    else
      {:ok,
       Enum.join(
         ["Текущая варка:"] ++
           Enum.map(jobs, fn brew_job ->
             "- #{brew_job.id}: #{brew_job.recipe.name} ×#{brew_job.quantity} (#{status_label(brew_job.status)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("alchemy", _args, _character) do
    {:ok,
     "Формат: /alchemy workspace | /alchemy setup [tool1,tool2,...] | /alchemy recipes | /alchemy brew <recipe-code> [quantity] | /alchemy jobs"}
  end

  defp dispatch("npc", ["shops"], character) do
    shops =
      (character.current_location &&
         NPCShops.list_shops_for_location(character.current_location.id)) || []

    if shops == [] do
      {:ok, "В этой локации нет лавок торговцев."}
    else
      {:ok,
       Enum.join(
         ["Лавки торговцев:"] ++
           Enum.map(shops, fn shop ->
             "- #{shop.code}: #{shop.name}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("npc", ["browse", shop_code], character) do
    with %{id: location_id} <- character.current_location,
         %{} = shop <- NPCShops.get_shop_by_code(location_id, shop_code) do
      {:ok,
       Enum.join(
         ["Лавка «#{shop.name}»:"] ++
           Enum.map(shop.offers, fn offer ->
             "- #{offer.id}: #{offer.item_template.name} · купить за #{offer.buy_price} / продать за #{offer.sell_price}"
           end),
         "\n"
       )}
    else
      nil -> {:ok, "В текущей локации нет лавки с кодом #{shop_code}."}
    end
  end

  defp dispatch("npc", ["buy", offer_id], character) do
    dispatch("npc", ["buy", offer_id, "1"], character)
  end

  defp dispatch("npc", ["buy", offer_id, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = offer <- safe_get_offer(offer_id),
         {:ok, _result} <- NPCShops.buy(character, offer, quantity) do
      {:ok, "У торговца куплено: #{quantity} ед."}
    else
      nil ->
        {:ok, "Предложение торговца не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось совершить покупку: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("npc", ["sell", offer_id, inventory_item_id], character) do
    dispatch("npc", ["sell", offer_id, inventory_item_id, "1"], character)
  end

  defp dispatch("npc", ["sell", offer_id, inventory_item_id, quantity_raw], character) do
    quantity = parse_positive_integer(quantity_raw, 1)

    with %{} = offer <- safe_get_offer(offer_id),
         %{} = inventory_item <- load_owned_inventory_item(inventory_item_id, character.id),
         {:ok, %{payout: payout}} <- NPCShops.sell(character, offer, inventory_item, quantity) do
      {:ok, "Торговцу продано: #{quantity} ед. Выручка: #{payout}."}
    else
      nil ->
        {:ok, "Предложение торговца или предмет в инвентаре не найдены."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось совершить продажу: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("npc", _args, _character) do
    {:ok,
     "Формат: /npc shops | /npc browse <shop-code> | /npc buy <offer-id> [quantity] | /npc sell <offer-id> <inventory-item-id> [quantity]"}
  end

  defp dispatch("charity", ["donate", amount_raw], character) do
    amount = parse_positive_integer(amount_raw, 0)

    case NPCShops.donate_to_charity(character, amount) do
      {:ok, _result} ->
        {:ok, "В благотворительный фонд пожертвовано: #{amount}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось сделать пожертвование: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("charity", _args, _character), do: {:ok, "Формат: /charity donate <amount>"}

  defp dispatch("craft", ["workspace"], character) do
    case Crafting.get_workshop_for_character(character.id) do
      nil ->
        {:ok,
         "Нет действующей ремесленной мастерской. Создать её в текущей локации: /craft setup [tool1,tool2,...]."}

      workshop ->
        location_name = location_name_by_id(workshop.location_id)

        tools =
          if workshop.installed_tool_codes == [],
            do: "нет",
            else: tool_codes_label(workshop.installed_tool_codes)

        {:ok,
         Enum.join(
           [
             "Мастерская: #{workshop.name}",
             "Локация: #{location_name}",
             "Состояние: #{status_label(workshop.status)}",
             "Инструменты: #{tools}"
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
        name: "Мастерская #{character.name}",
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
           "Ремесленная мастерская готова в локации «#{location_name_by_id(workshop.location_id)}». Инструменты: #{tool_codes_label(workshop.installed_tool_codes)}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось устроить ремесленную мастерскую: #{format_changeset(changeset)}"}
      end
    else
      nil -> {:ok, "Чтобы устроить ремесленную мастерскую, нужно находиться в локации."}
    end
  end

  defp dispatch("craft", ["recipes"], _character) do
    recipes = Crafting.list_recipes()

    if recipes == [] do
      {:ok, "Ремесленные чертежи пока не зарегистрированы."}
    else
      {:ok,
       Enum.join(
         ["Ремесленные чертежи:"] ++
           Enum.map(recipes, fn recipe ->
             "- #{recipe.code}: #{recipe.name} → #{recipe.result_item_template.name} (#{recipe.craft_time_game_days} игровых дн., сложность #{recipe.difficulty})"
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
       "Работа над «#{recipe.name}» начата. Готовность: #{Formatter.datetime(craft_job.completes_at)}. Количество: #{craft_job.quantity}."}
    else
      nil ->
        {:ok, "Для работы не найдены чертёж или мастерская."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать работу: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("craft", ["jobs"], character) do
    jobs = Crafting.list_craft_jobs_for_character(character.id)

    if jobs == [] do
      {:ok, "Сейчас в мастерской нет работ."}
    else
      {:ok,
       Enum.join(
         ["Работы в мастерской:"] ++
           Enum.map(jobs, fn craft_job ->
             "- #{craft_job.id}: #{craft_job.recipe.name} ×#{craft_job.quantity} (#{status_label(craft_job.status)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("craft", _args, _character) do
    {:ok,
     "Формат: /craft workshop | /craft setup [tool1,tool2,...] | /craft recipes | /craft build <recipe-code> [quantity] | /craft jobs"}
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
       "Сбор ресурса #{resource_code} начат. Завершение: #{Formatter.datetime(attempt.completes_at)}. Количество: #{attempt.quantity_requested}."}
    else
      nil ->
        {:ok, "В текущей локации нет доступного ресурса #{resource_code}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать сбор ресурсов: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("scavenge", _args, _character),
    do: {:ok, "Формат: /scavenge <resource_code> [quantity]"}

  defp dispatch("party", ["create" | name_parts], character) do
    name = if name_parts == [], do: nil, else: Enum.join(name_parts, " ")

    case Parties.create_party(character, if(name, do: %{name: name}, else: %{})) do
      {:ok, %{party: party}} ->
        {:ok, "Отряд создан: #{party.name}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось создать отряд: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("party", ["status"], character) do
    case Parties.active_party_for_character(character.id) do
      nil ->
        {:ok, "У вас нет активного отряда."}

      party ->
        members = Parties.list_active_members(party)

        {:ok,
         Enum.join(
           [
             "Отряд: #{party.name}",
             "Участники: #{Enum.map_join(members, ", ", & &1.character.name)}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("party", _args, _character),
    do: {:ok, "Формат: /party create [name] | /party status"}

  defp dispatch("org", ["create", kind | name_parts], character) do
    name = Enum.join(name_parts, " ")

    if name == "" do
      {:ok, "Формат: /org create <cult|company|council|guild> <name>"}
    else
      attrs =
        if kind == "cult" do
          %{fast_travel_enabled: true, linked_location_ids: [character.current_location_id]}
        else
          %{}
        end

      case Organizations.create_organization(character, kind, name, attrs) do
        {:ok, %{organization: organization}} ->
          {:ok,
           "Организация создана: #{organization.name} (#{organization_kind_label(organization.kind)})."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось создать организацию: #{format_changeset(changeset)}"}
      end
    end
  end

  defp dispatch("org", ["list"], character) do
    orgs = Organizations.list_organizations_for_character(character.id)

    if orgs == [] do
      {:ok, "Вы не состоите в организациях."}
    else
      {:ok,
       Enum.join(
         ["Организации:"] ++
           Enum.map(orgs, fn org ->
             "- #{org.id}: #{org.name} (#{organization_kind_label(org.kind)})"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("org", ["role", org_id, code, rank_raw, permissions_csv | title_parts], character) do
    rank = parse_non_negative_integer(rank_raw, 0)
    permissions = permissions_csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    title = Enum.join(title_parts, " ")

    with %{} = organization <- load_owned_organization(org_id, character.id),
         {:ok, role} <-
           Organizations.add_role(organization, character, %{
             code: code,
             title: title,
             rank: rank,
             permissions: permissions
           }) do
      {:ok, "Должность создана: #{role.title} (#{role.code})."}
    else
      nil ->
        {:ok, "Подходящее членство в организации не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось создать должность: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("org", ["invite", org_id, handle, role_code], character) do
    with %{} = organization <- load_owned_organization(org_id, character.id),
         %{} = invitee <- Accounts.get_character_by_handle(character.realm_id, handle),
         %{} = role <- Enum.find(organization.roles, &(&1.code == role_code)),
         {:ok, invitation} <- Organizations.invite_member(organization, character, invitee, role) do
      {:ok, "Приглашение в организацию #{invitation.id} отправлено персонажу #{handle}."}
    else
      nil ->
        {:ok, "Организация, приглашённый персонаж или должность не найдены."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось пригласить участника: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("org", ["invites"], character) do
    invitations = Organizations.pending_invitations_for_character(character.id)

    if invitations == [] do
      {:ok, "Нет ожидающих приглашений в организации."}
    else
      {:ok,
       Enum.join(
         ["Приглашения в организации:"] ++
           Enum.map(invitations, fn invitation ->
             "- #{invitation.id}: #{invitation.organization.name} · должность «#{invitation.role.title}»"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("org", ["accept", invitation_id], character) do
    with %{} = invitation <- load_org_invitation(invitation_id, character.id),
         {:ok, _membership} <- Organizations.accept_invitation(invitation, character) do
      {:ok, "Приглашение в организацию принято."}
    else
      nil ->
        {:ok, "Подходящее приглашение в организацию не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось принять приглашение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("org", ["reject", invitation_id], character) do
    with %{} = invitation <- load_org_invitation(invitation_id, character.id),
         {:ok, _invitation} <- Organizations.reject_invitation(invitation, character) do
      {:ok, "Приглашение в организацию отклонено."}
    else
      nil ->
        {:ok, "Подходящее приглашение в организацию не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось отклонить приглашение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("org", ["travel", org_id, location_slug], character) do
    with %{} = organization <- load_owned_organization(org_id, character.id),
         %{} = location <- Worlds.get_location_by_slug(character.realm_id, location_slug),
         {:ok, updated_character} <-
           Organizations.use_fast_travel(character, organization, location) do
      {:ok,
       "Переход организации завершён. Новая локация: #{location_name_by_id(updated_character.current_location_id)}."}
    else
      nil ->
        {:ok, "Организация или локация не найдены."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось воспользоваться переходом организации: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("org", _args, _character) do
    {:ok,
     "Формат: /org create <cult|company|council|guild> <name> | /org list | /org role <org-id> <code> <rank> <perm1,perm2,...> <title> | /org invite <org-id> <handle> <role-code> | /org invites | /org accept <invite-id> | /org reject <invite-id> | /org travel <org-id> <location-slug>"}
  end

  defp dispatch("club", ["create", club_type | name_parts], character) do
    name = Enum.join(name_parts, " ")

    if name == "" do
      {:ok, "Формат: /club create <type> <name>"}
    else
      case Clubs.create_club(character, %{club_type: club_type, name: name}) do
        {:ok, %{club: club}} ->
          {:ok, "Клуб создан: #{club.name} (#{club_type_label(club.club_type)})."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось создать клуб: #{format_changeset(changeset)}"}
      end
    end
  end

  defp dispatch("club", ["list"], character) do
    clubs = Clubs.list_clubs_for_character(character.id)

    if clubs == [] do
      {:ok, "Вы не состоите в активных клубах."}
    else
      {:ok,
       Enum.join(
         ["Клубы:"] ++
           Enum.map(clubs, fn club ->
             "- #{club.id}: #{club.name} (#{club_type_label(club.club_type)})"
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
           "Клуб: #{club.name}",
           "Направление: #{club_type_label(club.club_type)}",
           "Участники: #{Enum.map_join(members, ", ", & &1.character.name)}"
         ],
         "\n"
       )}
    else
      nil -> {:ok, "Подходящее членство в клубе не найдено."}
    end
  end

  defp dispatch("club", ["invite", club_id, handle], character) do
    with %{} = club <- load_member_club(club_id, character.id),
         %{} = invitee <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, %{invitation: invitation}} <- Clubs.invite_member(club, character, invitee) do
      {:ok, "Приглашение #{invitation.id} отправлено персонажу #{handle}."}
    else
      nil ->
        {:ok,
         "Клуб или приглашённый персонаж не найдены, либо ваша роль не позволяет приглашать."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось пригласить участника: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["invites"], character) do
    invitations = Clubs.pending_invitations_for_character(character.id)

    if invitations == [] do
      {:ok, "Нет ожидающих приглашений в клубы."}
    else
      {:ok,
       Enum.join(
         ["Приглашения в клубы:"] ++
           Enum.map(invitations, fn invitation ->
             "- #{invitation.id}: #{invitation.club.name} · от #{invitation.inviter_character.name}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("club", ["accept", invitation_id], character) do
    with %{} = invitation <- load_invitation(invitation_id, character.id),
         {:ok, %{club: club}} <- Clubs.accept_invitation(invitation, character) do
      {:ok, "Вы вступили в клуб «#{club.name}»."}
    else
      nil ->
        {:ok, "Подходящее ожидающее приглашение не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось принять приглашение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["reject", invitation_id], character) do
    with %{} = invitation <- load_invitation(invitation_id, character.id),
         {:ok, _updated_invitation} <- Clubs.reject_invitation(invitation, character) do
      {:ok, "Приглашение отклонено."}
    else
      nil ->
        {:ok, "Подходящее ожидающее приглашение не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось отклонить приглашение: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", ["leave", club_id], character) do
    with %{} = club <- load_member_club(club_id, character.id),
         {:ok, updated_club} <- Clubs.leave_club(club, character) do
      {:ok, "Вы вышли из клуба «#{updated_club.name}»."}
    else
      nil ->
        {:ok, "Подходящее членство в клубе не найдено."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось выйти из клуба: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("club", _args, _character) do
    {:ok,
     "Формат: /club create <type> <name> | /club list | /club status <club-id> | /club invite <club-id> <handle> | /club invites | /club accept <invite-id> | /club reject <invite-id> | /club leave <club-id>"}
  end

  defp dispatch("duel", ["challenge", handle, stake_raw], character) do
    stake = parse_positive_integer(stake_raw, 0)

    with %{} = opponent <- Accounts.get_character_by_handle(character.realm_id, handle),
         {:ok, duel} <- PVP.challenge_duel(character, opponent, stake) do
      {:ok,
       "Вызов на дуэль отправлен персонажу #{handle}. Дуэль: #{duel.id}. Ставка: #{duel.stake_amount}."}
    else
      nil ->
        {:ok, "В вашем мире не найден персонаж с именем #{handle}."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось вызвать на дуэль: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["accept", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id, :pending),
         true <- duel.opponent_character_id == character.id,
         {:ok, updated_duel} <- PVP.accept_duel(duel, character) do
      {:ok, "Дуэль принята. Бой #{updated_duel.combat_id} готов."}
    else
      nil ->
        {:ok, "Подходящая ожидающая дуэль не найдена."}

      false ->
        {:ok, "Принять дуэль может только вызванный соперник."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось принять дуэль: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["reject", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id, :pending),
         true <- duel.opponent_character_id == character.id,
         {:ok, _updated_duel} <- PVP.reject_duel(duel, character) do
      {:ok, "Дуэль отклонена."}
    else
      nil ->
        {:ok, "Подходящая ожидающая дуэль не найдена."}

      false ->
        {:ok, "Отклонить дуэль может только вызванный соперник."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось отклонить дуэль: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["cancel", duel_id], character) do
    with %{} = duel <- load_owned_duel(duel_id, character.id),
         {:ok, _updated_duel} <- PVP.cancel_duel(duel, character) do
      {:ok, "Дуэль отменена."}
    else
      nil ->
        {:ok, "Подходящая дуэль не найдена."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось отменить дуэль: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("duel", ["status"], character) do
    duels = PVP.list_open_duels_for_character(character.id)

    if duels == [] do
      {:ok, "Открытых дуэлей нет."}
    else
      {:ok,
       Enum.join(
         ["Открытые дуэли:"] ++
           Enum.map(duels, fn duel ->
             opponent_id =
               if duel.challenger_character_id == character.id,
                 do: duel.opponent_character_id,
                 else: duel.challenger_character_id

             "- #{duel.id}: #{status_label(duel.status)}, соперник ##{opponent_id}, ставка #{duel.stake_amount}"
           end),
         "\n"
       )}
    end
  end

  defp dispatch("duel", _args, _character),
    do:
      {:ok,
       "Формат: /duel challenge <handle> <stake> | /duel accept <duel-id> | /duel reject <duel-id> | /duel cancel <duel-id> | /duel status"}

  defp dispatch("expedition", ["start"], character) do
    with %{} = party <- Parties.active_party_for_character(character.id),
         {:ok, %{expedition: expedition}} <- Parties.start_expedition(party) do
      {:ok,
       "Экспедиция начата в локации «#{location_name_by_id(expedition.location_id)}». Запас еды: #{expedition.food_units_snapshot}. Груз: #{expedition.carried_weight}/#{expedition.carry_capacity}."}
    else
      nil ->
        {:ok, "Для начала экспедиции нужен активный отряд."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать экспедицию: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("expedition", ["status"], character) do
    case Parties.active_expedition_for_character(character.id) do
      nil ->
        {:ok, "Активной экспедиции нет."}

      expedition ->
        members = Parties.active_members_for_expedition(expedition.id)

        {:ok,
         Enum.join(
           [
             "Экспедиция: #{expedition.id}",
             "Локация: #{location_name_by_id(expedition.location_id)}",
             "Участники: #{length(members)}",
             "Запас еды: #{expedition.food_units_snapshot}",
             "Груз: #{expedition.carried_weight}/#{expedition.carry_capacity}"
           ],
           "\n"
         )}
    end
  end

  defp dispatch("expedition", _args, _character),
    do: {:ok, "Формат: /expedition start | /expedition status"}

  defp dispatch("dungeon", ["enter"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{id: location_id} <- character.current_location,
         %{} = dungeon <- Dungeons.active_dungeon_at_location(character.realm_id, location_id),
         {:ok, %{run: run}} <- Dungeons.enter_dungeon(expedition, dungeon) do
      {:ok, "Вы вошли в подземелье «#{dungeon.name}». Текущий зал: #{run.current_node.name}."}
    else
      nil ->
        {:ok, "Чтобы войти, экспедиция должна находиться у действующего входа в подземелье."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось войти в подземелье: #{format_changeset(changeset)}"}
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
           "Подземелье: #{run.dungeon.name}",
           "Этаж: #{run.current_floor.number}",
           "Зал: #{run.current_node.slug} — #{run.current_node.name}",
           "Встреча: #{encounter_line(encounter)}",
           "Возвращение: #{extraction_line(extraction)}",
           "Шагов: #{run.steps_taken}"
         ],
         "\n"
       )}
    else
      nil -> {:ok, "Активного похода в подземелье нет."}
    end
  end

  defp dispatch("dungeon", ["move", node_slug], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         %{} = node <- Dungeons.get_node_by_slug_in_dungeon(run.dungeon_id, node_slug),
         {:ok, %{run: updated_run}} <- Dungeons.move_run(run, node.id) do
      encounter = Dungeons.current_encounter_for_run(updated_run.id)

      {:ok,
       "Переход в зал «#{updated_run.current_node.name}». Встреча: #{encounter_line(encounter)}."}
    else
      nil ->
        {:ok, "Зал не найден в текущем подземелье."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось перейти в другой зал: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["extract"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{run: updated_run}} <- Dungeons.extract_via_ascent(run) do
      {:ok,
       "Выход из подземелья завершён. Экспедиция #{updated_run.id} выбралась в безопасности."}
    else
      nil ->
        {:ok, "Активного похода в подземелье нет."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось выйти из подземелья: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["ritual"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         {:ok, %{extraction: extraction}} <- Dungeons.start_return_ritual(run, character) do
      {:ok,
       "Ритуал возвращения начат. Выход завершится #{Formatter.datetime(extraction.completes_at)}."}
    else
      nil ->
        {:ok, "Активного похода в подземелье нет."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать ритуал возвращения: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("dungeon", ["drops"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      drops = Dungeons.list_drops_for_run(run.id)

      if drops == [] do
        {:ok, "В этом походе добыча не найдена."}
      else
        {:ok,
         Enum.join(
           ["Добыча из подземелья:"] ++
             Enum.map(drops, fn drop ->
               "- #{drop.id}: #{drop.name} ×#{drop.quantity} (#{drop_kind_label(drop.drop_kind)})"
             end),
           "\n"
         )}
      end
    else
      nil -> {:ok, "Активного похода в подземелье нет."}
    end
  end

  defp dispatch("dungeon", _args, _character),
    do:
      {:ok,
       "Формат: /dungeon enter | /dungeon status | /dungeon move <node-slug> | /dungeon extract | /dungeon ritual | /dungeon drops"}

  defp dispatch("encounter", ["status"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id) do
      encounter = Dungeons.current_encounter_for_run(run.id)
      {:ok, "Встреча: #{encounter_line(encounter)}"}
    else
      nil -> {:ok, "Активной встречи в подземелье нет."}
    end
  end

  defp dispatch("encounter", ["fight"], character) do
    with %{} = expedition <- Parties.active_expedition_for_character(character.id),
         %{} = run <- Dungeons.active_run_for_expedition(expedition.id),
         %{} = encounter <- Dungeons.current_encounter_for_run(run.id),
         {:ok, %{combat: combat}} <- Dungeons.start_encounter_combat(encounter) do
      {:ok,
       "Бой во встрече начат. Бой: #{combat.id}. Команды: /combat status и /combat cast <spell-id>."}
    else
      nil ->
        {:ok, "Нет активной встречи, в которой можно начать бой."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось начать бой: #{format_changeset(changeset)}"}
    end
  end

  defp dispatch("encounter", _args, _character),
    do: {:ok, "Формат: /encounter status | /encounter fight"}

  defp dispatch("spells", _args, character) do
    case Grimoires.active_grimoire_for_character(character.id) do
      nil ->
        {:ok, "Активный гримуар пока не выбран."}

      grimoire ->
        grimoire = Grimoires.get_grimoire!(grimoire.id)

        if grimoire.entries == [] do
          {:ok, "В активном гримуаре пока нет подготовленных заклинаний."}
        else
          {:ok,
           Enum.join(
             ["Подготовленные заклинания:"] ++
               Enum.map(grimoire.entries, fn entry ->
                 "- #{entry.spell.name} · #{spell_school_label(entry.spell.school)}"
               end),
             "\n"
           )}
        end
    end
  end

  defp dispatch("combat", ["status"], character) do
    case Combat.active_combat_for_character(character.id) do
      nil ->
        {:ok, "Активного боя нет."}

      combat ->
        {:ok,
         Enum.join(
           [
             "Бой: #{combat_kind_label(combat.kind)}",
             "Ход: #{combat.turn_number}",
             "Состояние: #{status_label(combat.status)}",
             "Здоровье отряда: #{(combat.sides["party"] && combat.sides["party"]["shared_hp"]) || (combat.sides["attackers"] && combat.sides["attackers"]["shared_hp"])}",
             "Здоровье противника: #{(combat.sides["encounter"] && combat.sides["encounter"]["shared_hp"]) || (combat.sides["defenders"] && combat.sides["defenders"]["shared_hp"])}"
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
      {:ok, "Заклинание подготовлено для хода #{combat.turn_number}."}
    else
      nil ->
        {:ok, "Активный бой не найден, либо персонаж не участвует в нём."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось подготовить заклинание: #{format_changeset(changeset)}"}

      {:error, _reason} ->
        {:ok, "Не удалось подготовить заклинание. Проверьте ход, цель и гримуар."}
    end
  end

  defp dispatch("combat", ["wait"], character) do
    with %{} = combat <- Combat.active_combat_for_character(character.id),
         participant when not is_nil(participant) <-
           Enum.find(combat.participants, &(&1.character_id == character.id)),
         {:ok, _action} <- Combat.submit_action(combat, participant.id, %{action_type: :wait}) do
      {:ok, "Ожидание подготовлено для хода #{combat.turn_number}."}
    else
      nil ->
        {:ok, "Активный бой не найден, либо персонаж не участвует в нём."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось выбрать ожидание: #{format_changeset(changeset)}"}

      {:error, _reason} ->
        {:ok, "Не удалось выбрать ожидание. Возможно, ход уже закрыт."}
    end
  end

  defp dispatch("combat", ["resolve"], character) do
    with %{} = combat <- Combat.active_combat_for_character(character.id),
         true <- combat.status == :locked,
         %Turn{id: turn_id} <- Repo.get_by(Turn, combat_id: combat.id, number: combat.turn_number),
         {:ok, resolved_combat} <- Combat.resolve_turn(combat),
         :ok <- TurnArtifacts.persist(combat.id, turn_id) do
      case CombatResolution.finalize(resolved_combat) do
        {:ok, _result} ->
          {:ok, combat_resolution_text(resolved_combat)}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Бой завершён, но награды выдать не удалось: #{format_changeset(changeset)}"}

        {:error, _reason} ->
          {:ok, "Бой завершён, но награды сейчас выдать не удалось."}
      end
    else
      nil ->
        {:ok, "Активного боя нет."}

      false ->
        {:ok, "Бой ещё не готов к расчёту хода."}

      {:error, %Changeset{} = changeset} ->
        {:ok, "Не удалось рассчитать бой: #{format_changeset(changeset)}"}

      {:error, _reason} ->
        {:ok, "Не удалось рассчитать бой. Попробуйте обновить его состояние."}
    end
  end

  defp dispatch("combat", _args, _character),
    do: {:ok, "Формат: /combat status | /combat cast <spell-id> | /combat wait | /combat resolve"}

  defp dispatch("admin", ["status"], character) do
    if operator_authorized?(character) do
      report = Operator.system_report()

      {:ok,
       Enum.join(
         [
           "Системный отчёт:",
           "Миры: #{report.realms}",
           "Персонажи: #{report.characters}",
           "Локации: #{report.locations}",
           "Маршруты: #{report.routes}",
           "Активные пути: #{report.active_journeys}",
           "Активные переселения: #{report.active_migrations}",
           "Активное обучение: #{report.active_enrollments}",
           "Исследовательские проекты: #{report.active_research_projects}",
           "Профессора: #{report.active_professors}",
           "Публикации: #{report.publications}",
           "Варка зелий: #{report.active_brew_jobs}",
           "Ремесленные работы: #{report.active_craft_jobs}",
           "Активные базы: #{report.active_bases}",
           "Строящиеся базы: #{report.building_bases}",
           "Циклы подземелий: #{report.active_dungeon_cycles}",
           "Клубы: #{report.active_clubs}",
           "Ожидающие приглашения в клубы: #{report.pending_club_invitations}",
           "Сборы ресурсов: #{report.active_scavenge_attempts}",
           "Экспедиции: #{report.active_expeditions}",
           "Походы: #{report.active_runs}",
           "Бои: #{report.active_combats}",
           "Объявления на рынке: #{report.active_market_listings}",
           "Лавки торговцев: #{report.active_npc_shops}",
           "Предложения торговцев: #{report.npc_shop_offers}",
           "Запреты на торговлю: #{report.active_market_bans}",
           "Незакрытые преступления: #{report.open_crimes}",
           "Ожидающие уведомления: #{report.pending_notifications}",
           "Всего в казне: #{report.treasury_balance_total}",
           "Средства персонажей: #{report.character_balance_total}"
         ],
         "\n"
       )}
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", ["realm", realm_slug], character) do
    if operator_authorized?(character) do
      case Operator.realm_report(realm_slug) do
        {:ok, report} ->
          {:ok,
           Enum.join(
             [
               "Мир #{report.realm.slug} — #{report.realm.name}",
               "Персонажи: #{report.characters}",
               "Локации: #{report.locations}",
               "Маршруты: #{report.routes}",
               "Активные пути: #{report.active_journeys}",
               "Активные переселения: #{report.active_migrations}",
               "Активное обучение: #{report.active_enrollments}",
               "Исследовательские проекты: #{report.active_research_projects}",
               "Профессора: #{report.active_professors}",
               "Публикации: #{report.publications}",
               "Варка зелий: #{report.active_brew_jobs}",
               "Ремесленные работы: #{report.active_craft_jobs}",
               "Активные базы: #{report.active_bases}",
               "Строящиеся базы: #{report.building_bases}",
               "Циклы подземелий: #{report.active_dungeon_cycles}",
               "Клубы: #{report.active_clubs}",
               "Ожидающие приглашения в клубы: #{report.pending_club_invitations}",
               "Сборы ресурсов: #{report.active_scavenge_attempts}",
               "Экспедиции: #{report.active_expeditions}",
               "Походы: #{report.active_runs}",
               "Бои: #{report.active_combats}",
               "Объявления на рынке: #{report.active_market_listings}",
               "Лавки торговцев: #{report.active_npc_shops}",
               "Предложения торговцев: #{report.npc_shop_offers}",
               "Запреты на торговлю: #{report.active_market_bans}",
               "Незакрытые преступления: #{report.open_crimes}",
               "Казна: #{report.treasury_balance}",
               "Средства персонажей: #{report.character_balance_total}"
             ],
             "\n"
           )}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось загрузить отчёт по миру: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", ["sweep"], character) do
    if operator_authorized?(character) do
      case Operator.maintenance_sweep(actor_handle: operator_handle(character)) do
        {:ok, %{summary: summary}} ->
          {:ok,
           Enum.join(
             [
               "Обслуживание завершено:",
               "Завершённые пути: #{summary.completed_journeys}",
               "Завершённые переселения: #{summary.completed_migrations}",
               "Завершённое обучение: #{summary.completed_enrollments}",
               "Завершённые исследования: #{summary.completed_research_projects}",
               "Завершённая варка: #{summary.completed_brew_jobs}",
               "Завершённые ремесленные работы: #{summary.completed_craft_jobs}",
               "Завершённые базы: #{summary.completed_bases}",
               "Завершённые циклы подземелий: #{summary.completed_dungeon_cycles}",
               "Завершённые сборы ресурсов: #{summary.completed_attempts}",
               "Обновлённые залежи ресурсов: #{summary.refreshed_resource_caches}"
             ],
             "\n"
           )}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось выполнить обслуживание: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", ["dungeon", "maintain", dungeon_slug], character) do
    if operator_authorized?(character) do
      with %{} = dungeon <- Dungeons.get_dungeon_by_slug(character.realm_id, dungeon_slug),
           {:ok, %{state: state}} <- Dungeons.maintain_dungeon_by_id(dungeon.id) do
        {:ok,
         "Подземелье #{dungeon.slug} обслужено. Цикл: #{state.cycle_number}, давление: #{state.pressure_level}, аномалия: #{state.anomaly_level}."}
      else
        nil ->
          {:ok, "В вашем мире не найдено подземелье с кодом #{dungeon_slug}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось обслужить подземелье: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", ["federation", "manifest"], character) do
    if operator_authorized?(character) do
      manifest = Federation.export_realm_manifest(Federation.local_realm!())

      {:ok,
       Enum.join(
         [
           "Манифест локального мира:",
           "Код: #{manifest.slug}",
           "Название: #{manifest.name}",
           "Валюта: #{manifest.currency_code || "неизвестно"}",
           "Адрес: #{manifest.public_endpoint || "не задан"}",
           "Население: #{manifest.population_hint}",
           "Область магии: #{manifest.ruleset["magic_scope"]}"
         ],
         "\n"
       )}
    else
      {:ok, "Недостаточно прав."}
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
           "Удалённый мир #{remote_realm.slug} зарегистрирован по адресу #{remote_realm.public_endpoint}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось зарегистрировать удалённый мир: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", ["federation", "sync", realm_slug], character) do
    if operator_authorized?(character) do
      with %{} = remote_realm <- Federation.get_remote_realm_by_slug(realm_slug),
           {:ok, updated_remote_realm} <- Federation.sync_remote_realm(remote_realm) do
        {:ok,
         "Удалённый мир #{updated_remote_realm.slug} синхронизирован. Население: #{updated_remote_realm.population_hint}."}
      else
        nil ->
          {:ok, "Удалённый мир с кодом #{realm_slug} не найден."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось синхронизировать удалённый мир: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
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
             "Профиль #{handle}:",
             "Репутация: #{(profile && profile.reputation_score) || 0}",
             "Преступления: #{(profile && profile.crime_count) || 0}",
             "Неоплаченные штрафы: #{(profile && profile.outstanding_fine) || 0}",
             "Враждебность торговцев: #{(profile && profile.npc_hostility_level) || 0}",
             "Запрет торговли до: #{(profile && profile.market_ban_until && Formatter.datetime(profile.market_ban_until)) || "нет"}",
             "Последние преступления: #{recent_crimes_line(crimes)}"
           ],
           "\n"
         )}
      else
        nil -> {:ok, "В вашем мире не найден персонаж с именем #{handle}."}
      end
    else
      {:ok, "Недостаточно прав."}
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
         "Преступление персонажа #{handle} зарегистрировано. Вид: #{crime_type_label(crime_record.crime_type)}, тяжесть: #{crime_record.severity}, штраф: #{crime_record.fine_amount}."}
      else
        nil ->
          {:ok, "В вашем мире не найден персонаж с именем #{handle}."}

        {:error, %Changeset{} = changeset} ->
          {:ok, "Не удалось зарегистрировать преступление: #{format_changeset(changeset)}"}
      end
    else
      {:ok, "Недостаточно прав."}
    end
  end

  defp dispatch("admin", _args, _character) do
    {:ok,
     "Формат: /admin status | /admin realm <slug> | /admin sweep | /admin dungeon maintain <dungeon-slug> | /admin federation manifest | /admin federation register <manifest-url> [token] | /admin federation sync <realm-slug> | /admin profile <handle> | /admin crime <handle> <crime_type> <severity> [fine]"}
  end

  defp dispatch(_command, _args, _character) do
    {:ok, "Не знаю такой команды. /help покажет короткий список доступных действий."}
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

  defp location_name(%Character{current_location: nil}), do: "неизвестно"
  defp location_name(%Character{current_location: location}), do: location.name

  defp location_name_by_id(location_id) do
    Worlds.get_location!(location_id).name
  rescue
    Ecto.NoResultsError -> "неизвестно"
  end

  defp journey_status(nil), do: "вы на месте"

  defp journey_status(journey),
    do:
      "переход в «#{location_name_by_id(journey.to_location_id)}» до #{Formatter.datetime(journey.arrival_at)}"

  defp telegram_next_step(nil),
    do: "откройте MMGO и выберите действие в текущей локации"

  defp telegram_next_step(_journey),
    do: "переход уже идёт; /journey покажет время прибытия"

  defp academy_enrollment_line(nil), do: "нет"

  defp academy_enrollment_line(enrollment),
    do: "#{academy_track_label(enrollment.program_type)} (#{status_label(enrollment.status)})"

  defp academy_specialization_line(nil), do: "нет"

  defp academy_specialization_line(specialization),
    do: academy_track_label(specialization.track)

  defp academy_track_label(value) do
    case to_string(value) do
      "basic" -> "базовое образование"
      "basic_education" -> "базовое образование"
      "academy_core" -> "основная программа академии"
      "wizardry" -> "чародейство"
      "alchemy" -> "алхимия"
      "mastery" -> "мастерство"
      "extended" -> "углублённое обучение"
      "extended_study" -> "углублённое обучение"
      "academia" -> "академическая ступень"
      _other -> "неизвестная программа"
    end
  end

  defp project_kind_label(value) do
    case to_string(value) do
      "spell" -> "заклинание"
      "potion" -> "зелье"
      "tool" -> "инструмент"
      "thesis" -> "диссертация"
      "course" -> "учебный курс"
      _other -> "исследовательский проект"
    end
  end

  defp tool_codes_label(codes), do: Enum.map_join(codes, ", ", &tool_code_label/1)

  defp tool_code_label(value) do
    case to_string(value) do
      "cauldron" -> "котёл"
      "demo_travel_ration" -> "дорожный паёк"
      "demo_lumen_dust" -> "светящаяся пыль"
      "construction_material" -> "строительные материалы"
      "forge" -> "горн"
      "anvil" -> "наковальня"
      "hammer" -> "молот"
      "workbench" -> "верстак"
      _other -> "неизвестный инструмент"
    end
  end

  defp organization_kind_label(value) do
    case to_string(value) do
      "cult" -> "культ"
      "company" -> "компания"
      "council" -> "совет"
      "guild" -> "гильдия"
      _other -> "организация"
    end
  end

  defp club_type_label(value) do
    case to_string(value) do
      "dueling" -> "дуэльный"
      "academic" -> "учебный"
      "social" -> "общественный"
      "exploration" -> "исследовательский"
      _other -> "клуб"
    end
  end

  defp drop_kind_label(value) do
    case to_string(value) do
      "item" -> "предмет"
      "currency" -> "монеты"
      "resource" -> "ресурс"
      "artifact" -> "артефакт"
      _other -> "награда"
    end
  end

  defp spell_school_label(value) do
    case to_string(value) do
      "fire" -> "огонь"
      "water" -> "вода"
      "air" -> "воздух"
      "earth" -> "земля"
      "light" -> "свет"
      "darkness" -> "тьма"
      _other -> "неизвестная школа"
    end
  end

  defp combat_kind_label(value) do
    case to_string(value) do
      "duel" -> "дуэль"
      "dungeon" -> "подземелье"
      "encounter" -> "встреча"
      "overworld" -> "дорожная встреча"
      _other -> "бой"
    end
  end

  defp crime_type_label(value) do
    case to_string(value) do
      "theft" -> "кража"
      "fraud" -> "мошенничество"
      "assault" -> "нападение"
      "smuggling" -> "контрабанда"
      _other -> "нарушение"
    end
  end

  defp encounter_kind_label(value) do
    case to_string(value) do
      "combat" -> "бой"
      "creature" -> "существо"
      "hazard" -> "опасность"
      "loot" -> "добыча"
      "puzzle" -> "загадка"
      "traveler" -> "путник"
      _other -> "неизвестная встреча"
    end
  end

  defp extraction_type_label(value) do
    case to_string(value) do
      "ascent" -> "подъём"
      "return_ritual" -> "ритуал возвращения"
      "ritual" -> "ритуал возвращения"
      _other -> "возвращение"
    end
  end

  defp combat_side_label(nil), do: "нет"

  defp combat_side_label(value) do
    case to_string(value) do
      "party" -> "отряд"
      "attackers" -> "нападающие"
      "defenders" -> "защитники"
      "encounter" -> "противник"
      _other -> "не определён"
    end
  end

  defp status_label(value) do
    case to_string(value) do
      "active" -> "активно"
      "available" -> "доступно"
      "building" -> "строится"
      "cancelled" -> "отменено"
      "completed" -> "завершено"
      "failed" -> "провалено"
      "finished" -> "завершено"
      "in_progress" -> "в процессе"
      "locked" -> "закрыто"
      "open" -> "открыто"
      "pending" -> "ожидает"
      "rejected" -> "отклонено"
      "resolved" -> "завершено"
      "running" -> "идёт"
      "succeeded" -> "успешно"
      _other -> "состояние уточняется"
    end
  end

  defp route_destination(route, current_location_id) do
    cond do
      route.origin_location_id == current_location_id -> route.destination_location
      route.destination_location_id == current_location_id -> route.origin_location
      true -> route.destination_location
    end
  end

  defp road_response_text(_action, %{combat: combat}),
    do: "Дорожный бой начат: #{combat.id}. Проверить: /combat status."

  defp road_response_text("greet", %{encounter: encounter}),
    do: "Вы поприветствовали путника. Состояние встречи: #{status_label(encounter.status)}."

  defp road_response_text("trade", %{encounter: encounter}),
    do: "Вы предложили торговлю. Состояние встречи: #{status_label(encounter.status)}."

  defp road_response_text("avoid", %{encounter: encounter}),
    do: "Вы избежали встречи. Состояние встречи: #{status_label(encounter.status)}."

  defp road_response_text(_action, %{encounter: encounter}),
    do: "Встреча обновлена: #{status_label(encounter.status)}."

  defp traveler_contact_response_text("accept", encounter),
    do:
      "Запрос принят. Если у обоих путников есть публичный @username, контакты придут отдельными сообщениями. Состояние встречи: #{status_label(encounter.status)}."

  defp traveler_contact_response_text("reject", encounter),
    do:
      "Запрос отклонён. Telegram-контакты не раскрыты. Состояние встречи: #{status_label(encounter.status)}."

  defp encounter_line(nil), do: "нет"

  defp encounter_line(encounter),
    do: "#{encounter_kind_label(encounter.encounter_kind)} (#{status_label(encounter.status)})"

  defp extraction_line(nil), do: "нет"

  defp extraction_line(extraction),
    do:
      "#{extraction_type_label(extraction.extraction_type)} (#{status_label(extraction.status)})"

  defp combat_target_side(combat, participant_side) do
    combat.sides
    |> Map.keys()
    |> Enum.find(fn side -> side != participant_side end)
  end

  defp combat_resolution_text(combat) do
    "Бой рассчитан. Ход: #{combat.turn_number}, состояние: #{status_label(combat.status)}, победитель: #{combat_side_label(combat.winner_side)}."
  end

  defp operator_authorized?(%Character{} = character) do
    Operator.operator_handle?(operator_handle(character)) and
      SpecialProfiles.operator_profile_allowed?(character)
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

  defp load_owned_organization(org_id, character_id) do
    organization = Organizations.get_organization!(org_id)

    if Enum.any?(
         organization.memberships,
         &(&1.character_id == character_id and &1.status == :active)
       ) do
      organization
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_org_invitation(invitation_id, character_id) do
    invitation =
      MMGO.Organizations.Invitation
      |> Repo.get!(invitation_id)
      |> Repo.preload([:organization, :inviter_character, :role])

    if invitation.invitee_character_id == character_id and invitation.status == :pending do
      invitation
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
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

  defp safe_get_offer(offer_id) do
    NPCShops.get_offer!(offer_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_overworld_encounter(encounter_id, character_id) do
    encounter = Overworld.get_encounter!(encounter_id)

    if character_id in [encounter.initiator_character_id, encounter.target_character_id] do
      encounter
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp recent_crimes_line([]), do: "нет"

  defp recent_crimes_line(crimes) do
    Enum.map_join(crimes, ", ", fn crime ->
      "#{crime_type_label(crime.crime_type)} (тяжесть #{crime.severity})"
    end)
  end

  defp format_changeset(%Changeset{} = changeset) do
    ChangesetErrors.format(changeset)
  end
end
