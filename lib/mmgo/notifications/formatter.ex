defmodule MMGO.Notifications.Formatter do
  alias MMGO.Notifications.Notification

  def render(%Notification{kind: "journey_arrived", payload: payload}) do
    {:ok,
     %{
       text: "Путешествие завершено. Вы прибыли в место №#{payload["to_location_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "academy_completed", payload: payload}) do
    track_suffix =
      case payload["track"] do
        nil -> ""
        track -> " Путь: #{track_label(track)}."
      end

    text =
      case {payload["status"], payload["outcome_tier"]} do
        {"failed", "capstone_incomplete"} ->
          "Обучение по программе «#{program_label(payload["program_type"])}» завершилось без выпуска: итоговое испытание не пройдено.#{track_suffix}"

        {"failed", _outcome_tier} ->
          "Обучение по программе «#{program_label(payload["program_type"])}» завершилось без выпуска.#{track_suffix}"

        _other ->
          "Обучение по программе «#{program_label(payload["program_type"])}» завершено.#{track_suffix}"
      end

    {:ok, %{text: text, opts: [parse_mode: "HTML"]}}
  end

  def render(%Notification{kind: "scavenge_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Поиск ресурсов завершён. Добыто: #{payload["quantity_yielded"]} ед. Запись №#{payload["attempt_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "brew_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Зелье готово. Получено: #{payload["yielded_quantity"]} ед. Варка №#{payload["brew_job_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "craft_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Работа в мастерской завершена. Получено: #{payload["yielded_quantity"]} ед. Заказ №#{payload["craft_job_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "research_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Исследование завершено. #{project_kind_label(payload["project_kind"])}: #{payload["title"]}. Проект №#{payload["project_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "base_ready", payload: payload}) do
    {:ok,
     %{
       text:
         "Владение готово. Дом №#{payload["base_id"]} в месте №#{payload["location_id"]} теперь действует.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "realm_migration_started", payload: payload}) do
    {:ok,
     %{
       text:
         "Переход в мир «#{payload["destination_realm_name"]}» начался. Переход №#{payload["migration_id"]}. Заморозка закончится: #{payload["freeze_ends_at"] || "время не указано"}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "realm_migration_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Переход между мирами завершён. Получено пассивного опыта: #{payload["passive_xp_awarded"]}. Переход №#{payload["migration_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "dungeon_extraction_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Выход из подземелья завершён. Экспедиция №#{payload["run_id"]} покинула глубины: #{extraction_label(payload["extraction_type"])}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "dungeon_run_failed", payload: payload}) do
    {:ok,
     %{
       text:
         "Экспедиция в подземелье провалилась. Запись №#{payload["run_id"]}. Потеряно трофеев: #{payload["lost_item_count"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "club_invitation", payload: payload}) do
    {:ok,
     %{
       text:
         "Приглашение в клуб «#{payload["club_name"]}» (#{club_type_label(payload["club_type"])}). Письмо №#{payload["invitation_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "organization_invitation", payload: payload}) do
    {:ok,
     %{
       text:
         "Приглашение в организацию «#{payload["organization_name"]}» (#{organization_kind_label(payload["organization_kind"])}). Письмо №#{payload["invitation_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "overworld_contact_request", payload: payload}) do
    {:ok,
     %{
       text:
         "Путник «#{payload["requester_name"]}» хочет обменяться с вами контактами Telegram. Примите запрос, только если хотите раскрыть друг другу свои @username. Если кнопки недоступны: /road accept #{payload["encounter_id"]} или /road reject #{payload["encounter_id"]}.",
       opts: [
         reply_markup: %{
           inline_keyboard: [
             [
               %{
                 text: "Принять",
                 callback_data: "road:accept:#{payload["encounter_id"]}"
               },
               %{
                 text: "Отклонить",
                 callback_data: "road:reject:#{payload["encounter_id"]}"
               }
             ]
           ]
         }
       ]
     }}
  end

  def render(%Notification{kind: "overworld_contact_accepted", payload: payload}) do
    text =
      case payload["telegram_username"] do
        username when is_binary(username) and username != "" ->
          "Вы и путник «#{payload["counterpart_name"]}» согласились обменяться контактами. Telegram: @#{username}"

        _username ->
          "Вы и путник «#{payload["counterpart_name"]}» согласились обменяться контактами, но у одного из вас нет публичного @username. Контакты не раскрыты."
      end

    {:ok, %{text: text, opts: []}}
  end

  def render(%Notification{kind: "overworld_contact_rejected", payload: payload}) do
    text =
      case payload["decision"] do
        "cancel" ->
          "Путник «#{payload["counterpart_name"]}» отменил запрос на обмен контактами Telegram. Никакие @username не были раскрыты."

        _decision ->
          "Путник «#{payload["counterpart_name"]}» отклонил обмен контактами Telegram. Никакие @username не были раскрыты."
      end

    {:ok,
     %{
       text: text,
       opts: []
     }}
  end

  def render(%Notification{}), do: {:error, :unsupported_notification_kind}

  defp program_label("basic"), do: "Базовое образование"
  defp program_label("academy_core"), do: "Ядро Академии"
  defp program_label("extended_study"), do: "Расширенный курс"
  defp program_label("academia"), do: "Академия наук"
  defp program_label(_program), do: "неизвестная программа"

  defp track_label("wizardry"), do: "Чародейство"
  defp track_label("alchemy"), do: "Алхимия"
  defp track_label("mastery"), do: "Мастерство"
  defp track_label(_track), do: "не указан"

  defp project_kind_label("spell"), do: "Заклинание"
  defp project_kind_label("potion"), do: "Зелье"
  defp project_kind_label("tool"), do: "Инструмент"
  defp project_kind_label("thesis"), do: "Тезис"
  defp project_kind_label(_kind), do: "Проект"

  defp extraction_label("safe"), do: "безопасный выход"
  defp extraction_label("forced"), do: "вынужденный выход"
  defp extraction_label("emergency"), do: "аварийный выход"
  defp extraction_label(_type), do: "способ не указан"

  defp club_type_label("general_interest"), do: "общий круг"
  defp club_type_label("dueling"), do: "дуэльный клуб"
  defp club_type_label("research"), do: "исследовательское общество"
  defp club_type_label("expedition_planning"), do: "экспедиционный стол"
  defp club_type_label(_type), do: "иной круг"

  defp organization_kind_label("guild"), do: "гильдия"
  defp organization_kind_label("company"), do: "компания"
  defp organization_kind_label("council"), do: "совет"
  defp organization_kind_label("cult"), do: "культ"
  defp organization_kind_label(_kind), do: "организация"
end
