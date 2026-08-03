defmodule MMGO.Telegram.ChangesetErrors do
  @moduledoc false

  alias Ecto.Changeset

  @generic_error "данные не прошли проверку"

  @field_labels %{
    action: "Действие",
    actor_character_id: "Участник",
    amount: "Сумма",
    capacity: "Вместимость",
    character_id: "Персонаж",
    code: "Код",
    converted_currency_amount: "Сумма после обмена",
    credit_account_id: "Счёт получателя",
    current_balance: "Баланс",
    current_location_id: "Текущая локация",
    debit_account_id: "Счёт отправителя",
    description: "Описание",
    destination_character_id: "Персонаж назначения",
    destination_location_id: "Локация назначения",
    destination_realm_id: "Мир назначения",
    display_name: "Отображаемое имя",
    durability: "Прочность",
    entries: "Записи",
    formula: "Формула",
    handle: "Имя пользователя",
    id: "Запись",
    invitation_id: "Приглашение",
    invitee_character_id: "Приглашённый персонаж",
    item_template_id: "Предмет",
    kind: "Тип",
    level: "Уровень",
    location_id: "Локация",
    metadata: "Данные",
    name: "Название",
    nutrition_units: "Питательность",
    opponent_character_id: "Соперник",
    organization_id: "Организация",
    origin_location_id: "Локация отправления",
    origin_realm_id: "Исходный мир",
    owner_character_id: "Владелец",
    payload: "Данные",
    permissions: "Права",
    primary_school: "Первая школа",
    quantity: "Количество",
    rank: "Ранг",
    realm_id: "Мир",
    reserved_quantity: "Зарезервированное количество",
    role: "Роль",
    route_id: "Маршрут",
    ruleset: "Правила мира",
    secondary_school: "Вторая школа",
    slot_index: "Ячейка",
    source_location_id: "Исходная локация",
    source_realm_id: "Исходный мир",
    status: "Состояние",
    target_character_id: "Другой персонаж",
    title: "Название",
    to_location_id: "Локация назначения",
    total_price: "Итоговая цена",
    track: "Направление обучения",
    unit_price: "Цена за единицу",
    weight: "Вес",
    xp: "Опыт",
    yielded_quantity: "Полученное количество"
  }

  # Domain errors stay in English inside contexts and changesets. Only this presentation
  # boundary turns the stable, user-relevant ones into Telegram copy.
  @domain_messages %{
    "action is invalid" => "выбрано недопустимое действие",
    "amount must be greater than zero" => "сумма должна быть больше нуля",
    "at least one recipient is required" => "нужно указать хотя бы одного получателя",
    "basic education has already been completed" => "базовое образование уже завершено",
    "basic education must be completed first" => "сначала нужно завершить базовое образование",
    "basic education re-enrollment is still on a one-year cooldown" =>
      "повторное поступление станет доступно после годового перерыва",
    "character already has an active brew job" => "у персонажа уже идёт варка",
    "character already has an active craft job" => "у персонажа уже идёт ремесленная работа",
    "character already has an active enrollment" => "у персонажа уже есть активное обучение",
    "character already has an active journey" => "у персонажа уже есть активный путь",
    "character already has an active migration" => "у персонажа уже идёт переселение",
    "character already has an active research project" =>
      "у персонажа уже есть активное исследование",
    "character already has an active scavenging attempt" => "у персонажа уже идёт сбор ресурсов",
    "character does not belong to this contact request" =>
      "персонаж не участвует в этом запросе на знакомство",
    "character has already answered this contact request" =>
      "персонаж уже ответил на этот запрос на знакомство",
    "character is not an active club member" => "персонаж не состоит в этом клубе",
    "character is not an active organization member" => "персонаж не состоит в этой организации",
    "character must be at the base location" => "персонаж должен находиться у своей базы",
    "character must be at the workshop location" => "персонаж должен находиться в мастерской",
    "character must be placed at a location before travelling" =>
      "перед путешествием персонаж должен находиться в локации",
    "character must be specialized in alchemy" => "для этого нужна специализация по алхимии",
    "character must be specialized in mastery" => "для этого нужна ремесленная специализация",
    "character must belong to the same realm" => "персонаж должен находиться в том же мире",
    "characters must be at the same location" => "персонажи должны находиться в одной локации",
    "characters must belong to the same realm" => "персонажи должны находиться в одном мире",
    "contact decision is invalid" => "выбран недопустимый ответ на запрос",
    "contact request is not pending" => "запрос на знакомство уже обработан",
    "contact requests require an explicit consent decision" =>
      "для обмена контактами нужно явно принять или отклонить запрос",
    "course enrollment is not active" => "запись на курс уже не активна",
    "course is not active" => "курс сейчас не активен",
    "course is not available in this realm" => "курс недоступен в этом мире",
    "craft job is not active" => "ремесленная работа уже не активна",
    "craft job is not due yet" => "ремесленная работа ещё не завершена",
    "brew job is not active" => "варка уже не активна",
    "brew job is not due yet" => "варка ещё не завершена",
    "duel is not active" => "дуэль уже не активна",
    "duel is not pending" => "вызов на дуэль уже обработан",
    "duels cannot start in a safe zone" => "в безопасной зоне нельзя начинать дуэль",
    "encounter is not active" => "встреча уже не активна",
    "encounter is not a traveler contact request" =>
      "эта встреча не является запросом на знакомство",
    "enrollment is not active" => "обучение уже не активно",
    "enrollment is not due yet" => "обучение ещё не завершено",
    "event is not active" => "событие уже не активно",
    "expedition is not active" => "экспедиция уже не активна",
    "grimoire is at capacity" => "в гримуаре больше нет свободных ячеек",
    "grimoire tier is invalid" => "выбран недопустимый тип гримуара",
    "ingredient selection is required" => "нужно выбрать ингредиенты",
    "invitation does not belong to this character" =>
      "это приглашение предназначено другому персонажу",
    "invitation is not pending" => "приглашение уже обработано",
    "invitee must belong to the same realm" => "приглашённый должен находиться в том же мире",
    "journey could not be found" => "путь не найден",
    "journey is not active" => "путь уже не активен",
    "journey is not due yet" => "путь ещё не завершён",
    "location must belong to the same realm" => "локация должна находиться в том же мире",
    "missing required crafting materials" => "не хватает материалов для работы",
    "missing required ingredients" => "не хватает нужных ингредиентов",
    "only active Academy Core students or active Professors can found clubs" =>
      "создавать клубы могут только действующие студенты Академии и профессора",
    "only the requested traveler may answer" =>
      "ответить может только путник, которому отправлен запрос",
    "only the requesting traveler may cancel" =>
      "отменить запрос может только отправивший его путник",
    "organization is not active" => "организация уже не активна",
    "party invitation could not be found" => "приглашение в отряд не найдено",
    "party invitation is not pending" => "приглашение в отряд уже обработано",
    "party is not active" => "отряд уже не активен",
    "project is not active" => "исследование уже не активно",
    "project is not due yet" => "исследование ещё не завершено",
    "quantity exceeds the available inventory" => "у персонажа нет такого количества предметов",
    "quantity exceeds the remaining resources" => "в источнике нет такого количества ресурсов",
    "quantity must be greater than zero" => "количество должно быть больше нуля",
    "recipient accounts must be distinct" => "счета получателей не должны повторяться",
    "recipient transfers are invalid" => "распределение между получателями задано неверно",
    "route is not connected to the character's current location" =>
      "маршрут не связан с текущей локацией персонажа",
    "route must belong to the same realm as the character" =>
      "маршрут должен находиться в том же мире, что и персонаж",
    "sealed spirit cannot use ordinary roads" =>
      "запечатанный дух не может пользоваться обычными дорогами",
    "sealed grimoires cannot be modified" => "запечатанный гримуар нельзя изменить",
    "spell is already inscribed" => "заклинание уже записано в гримуар",
    "term is not active" => "учебный триместр уже не активен",
    "workshop is not active" => "мастерская уже не активна",
    "workshop does not belong to this character" =>
      "эта мастерская принадлежит другому персонажу",
    "workshop must belong to the same realm" => "мастерская должна находиться в том же мире",
    "is insufficient for this transfer" => "недостаточно средств для перевода",
    "must belong to the same realm" => "должно относиться к тому же миру",
    "must differ from the departure location" => "должно отличаться от места отправления",
    "must differ from the origin location" => "должно отличаться от исходной локации",
    "must differ from the origin realm" => "должен отличаться от исходного мира",
    "must differ from the challenger" => "должен отличаться от вызывающего персонажа",
    "must differ from the initiator" => "должен отличаться от инициатора",
    "must equal quantity multiplied by unit price" =>
      "должна равняться произведению количества и цены за единицу",
    "must be empty for basic education" => "не должно быть указано для базового образования",
    "is required for academy core study" => "обязательно для обучения в Академии"
  }

  @spec format(Changeset.t()) :: String.t()
  def format(%Changeset{errors: []}), do: @generic_error

  def format(%Changeset{} = changeset) do
    changeset.errors
    |> Enum.reverse()
    |> Enum.map(fn {field, error} -> {field_label(field), translate_error(error, field)} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("; ", fn {label, messages} ->
      "#{label}: #{messages |> Enum.uniq() |> Enum.join(", ")}"
    end)
  end

  defp translate_error({"can't be blank", _opts}, _field), do: "не заполнено"
  defp translate_error({"has already been taken", _opts}, _field), do: "уже занято"
  defp translate_error({"is invalid", _opts}, _field), do: "имеет недопустимое значение"
  defp translate_error({"has invalid format", _opts}, _field), do: "имеет недопустимый формат"

  defp translate_error({"has an invalid entry", _opts}, _field),
    do: "содержит недопустимое значение"

  defp translate_error({"is reserved", _opts}, _field), do: "зарезервировано"
  defp translate_error({"must be accepted", _opts}, _field), do: "требует подтверждения"

  defp translate_error({"does not match confirmation", _opts}, _field),
    do: "не совпадает с подтверждением"

  defp translate_error({"is still associated with this entry", _opts}, _field),
    do: "всё ещё связано с этой записью"

  defp translate_error({"are still associated with this entry", _opts}, _field),
    do: "всё ещё связаны с этой записью"

  defp translate_error({"should have %{count} item(s)", opts}, field),
    do: count_message(opts, field, "должно содержать %{count} элементов")

  defp translate_error({"should have at least %{count} item(s)", opts}, field),
    do: count_message(opts, field, "должно содержать не менее %{count} элементов")

  defp translate_error({"should have at most %{count} item(s)", opts}, field),
    do: count_message(opts, field, "должно содержать не более %{count} элементов")

  defp translate_error({"should be %{count} character(s)", opts}, field),
    do: count_message(opts, field, "длина должна быть %{count} символов")

  defp translate_error({"should be at least %{count} character(s)", opts}, field),
    do: count_message(opts, field, "длина должна быть не менее %{count} символов")

  defp translate_error({"should be at most %{count} character(s)", opts}, field),
    do: count_message(opts, field, "длина должна быть не более %{count} символов")

  defp translate_error({"should be %{count} byte(s)", opts}, field),
    do: count_message(opts, field, "размер должен быть %{count} байт")

  defp translate_error({"should be at least %{count} byte(s)", opts}, field),
    do: count_message(opts, field, "размер должен быть не менее %{count} байт")

  defp translate_error({"should be at most %{count} byte(s)", opts}, field),
    do: count_message(opts, field, "размер должен быть не более %{count} байт")

  defp translate_error({"must be less than %{number}", opts}, field),
    do: number_message(opts, field, "должно быть меньше %{number}")

  defp translate_error({"must be greater than %{number}", opts}, field),
    do: number_message(opts, field, "должно быть больше %{number}")

  defp translate_error({"must be less than or equal to %{number}", opts}, field),
    do: number_message(opts, field, "должно быть не больше %{number}")

  defp translate_error({"must be greater than or equal to %{number}", opts}, field),
    do: number_message(opts, field, "должно быть не меньше %{number}")

  defp translate_error({"must be equal to %{number}", opts}, field),
    do: number_message(opts, field, "должно быть равно %{number}")

  defp translate_error({message, _opts}, field) when is_binary(message) do
    Map.get(@domain_messages, message, fallback_message(field))
  end

  defp count_message(opts, field, template) do
    interpolate_number(template, opts[:count], field)
  end

  defp number_message(opts, field, template) do
    interpolate_number(template, opts[:number], field)
  end

  defp interpolate_number(template, value, _field) when is_integer(value) or is_float(value) do
    String.replace(template, "%{count}", to_string(value))
    |> String.replace("%{number}", to_string(value))
  end

  defp interpolate_number(_template, _value, field), do: fallback_message(field)

  defp field_label(field), do: Map.get(@field_labels, field, "Данные")

  defp fallback_message(field) when field in [:status, :action],
    do: "действие сейчас недоступно"

  defp fallback_message(field)
       when field in [
              :id,
              :character_id,
              :invitation_id,
              :item_template_id,
              :location_id,
              :route_id
            ],
       do: "выбранная запись недоступна"

  defp fallback_message(_field), do: @generic_error
end
