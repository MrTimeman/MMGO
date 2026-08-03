defmodule MMGOWeb.NotificationsLive do
  @moduledoc """
  Scoped in-world delivery history for the current character.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Вести")
     |> refresh_notifications()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_notifications(socket)}

  @impl true
  def render(%{state: _state} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="notifications-screen" class="mail-scene">
        <div class="mail-desk">
          <div class="mail-tools">
            <.link id="notifications-back-map" navigate={~p"/map"} class="mail-exit">
              ← отнести архив на место
            </.link>
            <button
              id="notifications-refresh"
              type="button"
              phx-click="refresh"
              class="mail-refresh"
            >
              Перечитать почту
            </button>
          </div>

          <header class="mail-ledger">
            <span class="mail-ledger__cord" aria-hidden="true"></span>
            <p>личный архив доставок</p>
            <h1>Вести и письма</h1>
            <span>
              Здесь писарь хранит ожидающие, доставленные и неудавшиеся послания.
            </span>
          </header>

          <section id="notification-history" class="mail-stack">
            <article
              :if={@state.notifications == []}
              id="notifications-empty"
              class="ovl-note mail-empty"
            >
              <span class="ovl-note__seal" aria-hidden="true">∅</span>
              <div class="ovl-note__body">
                <h2 class="ovl-note__title">Пустая почтовая полка</h2>
                <p class="ovl-note__text">Писарь ещё не принёс ни одной вести.</p>
              </div>
            </article>

            <article
              :for={notification <- @state.notifications}
              id={"notification-#{notification.id}"}
              class={[
                "ovl-note mail-letter",
                notification.status == :pending && "is-unread",
                notification.status == :sent && "is-accepted",
                notification.status in [:failed, :discarded] && "mail-letter--spoiled"
              ]}
            >
              <span class="ovl-note__seal" aria-hidden="true">
                {notification_mark(notification.kind)}
              </span>
              <div class="ovl-note__body">
                <div class="ovl-note__top">
                  <h2 class="ovl-note__title">{kind_label(notification.kind)}</h2>
                  <span
                    id={"notification-status-#{notification.id}"}
                    class={["mail-stamp", "mail-stamp--#{notification.status}"]}
                  >
                    {status_label(notification.status)}
                  </span>
                </div>
                <p class="ovl-note__from">
                  {channel_label(notification.channel)} · поставлено {format_time(
                    notification.scheduled_at
                  )}
                </p>
                <p class="ovl-note__text">{payload_summary(notification.payload)}</p>
                <p :if={notification.delivered_at} class="mail-delivered">
                  Доставлено: {format_time(notification.delivered_at)}
                </p>
                <p
                  :if={notification.error}
                  id={"notification-error-#{notification.id}"}
                  class="mail-error"
                >
                  Послание не удалось доставить.
                </p>
              </div>
            </article>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_notifications(socket) do
    case Play.notifications_state(socket.assigns.current_scope.character) do
      {:ok, state} ->
        assign(socket, :state, state)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Не удалось прочитать архив вестей.")
        |> push_navigate(to: ~p"/map")
    end
  end

  defp kind_label("journey_arrived"), do: "Прибытие"
  defp kind_label("scavenge_completed"), do: "Поиск ресурсов"
  defp kind_label("brew_completed"), do: "Варка завершена"
  defp kind_label("craft_completed"), do: "Заказ готов"
  defp kind_label("academy_completed"), do: "Академия"
  defp kind_label("research_completed"), do: "Исследование"
  defp kind_label("base_ready"), do: "Владение готово"
  defp kind_label("realm_migration_started"), do: "Переход между мирами"
  defp kind_label("realm_migration_completed"), do: "Прибытие в новый мир"
  defp kind_label("dungeon_extraction_completed"), do: "Выход из подземелья"
  defp kind_label("dungeon_run_failed"), do: "Экспедиция провалена"
  defp kind_label("party_invitation"), do: "Приглашение в отряд"
  defp kind_label("club_invitation"), do: "Клубное приглашение"
  defp kind_label("organization_invitation"), do: "Приглашение организации"
  defp kind_label("overworld_contact_request"), do: "Запрос Telegram-контакта"
  defp kind_label("overworld_contact_accepted"), do: "Контактами обменялись"
  defp kind_label("overworld_contact_rejected"), do: "Запрос контакта закрыт"
  defp kind_label(_kind), do: "Иная весть"

  defp channel_label(:telegram), do: "Telegram"
  defp channel_label(:in_app), do: "в приложении"
  defp channel_label(_channel), do: "другой канал"

  defp status_label(:pending), do: "ожидает"
  defp status_label(:sent), do: "доставлено"
  defp status_label(:failed), do: "ошибка"
  defp status_label(:discarded), do: "отменено"
  defp status_label(_status), do: "неизвестно"

  defp notification_mark("journey_arrived"), do: "⌖"
  defp notification_mark("scavenge_completed"), do: "◆"
  defp notification_mark("academy_completed"), do: "А"
  defp notification_mark("research_completed"), do: "И"
  defp notification_mark("party_invitation"), do: "О"
  defp notification_mark("club_invitation"), do: "К"
  defp notification_mark("organization_invitation"), do: "Г"
  defp notification_mark("overworld_contact_request"), do: "↔"
  defp notification_mark("overworld_contact_accepted"), do: "✓"
  defp notification_mark("overworld_contact_rejected"), do: "×"
  defp notification_mark(_kind), do: "✦"

  defp payload_summary(payload) when is_map(payload) and map_size(payload) > 0 do
    payload
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" · ", fn {key, value} ->
      "#{payload_key_label(key)}: #{payload_value(key, value)}"
    end)
  end

  defp payload_summary(_payload), do: "Письмо не содержит дополнительных сведений."

  defp payload_key_label(key) do
    case to_string(key) do
      "status" ->
        "состояние"

      "program_type" ->
        "программа"

      "track" ->
        "путь"

      "outcome_tier" ->
        "итог"

      "quantity_yielded" ->
        "добыто"

      "yielded_quantity" ->
        "получено"

      "project_kind" ->
        "вид проекта"

      "title" ->
        "название"

      "kind" ->
        "вид"

      "destination_realm_name" ->
        "новый мир"

      "freeze_ends_at" ->
        "конец заморозки"

      "passive_xp_awarded" ->
        "пассивный опыт"

      "extraction_type" ->
        "способ выхода"

      "lost_item_count" ->
        "потеряно трофеев"

      "club_name" ->
        "клуб"

      "club_type" ->
        "вид клуба"

      "party_name" ->
        "отряд"

      "organization_name" ->
        "организация"

      "organization_kind" ->
        "вид организации"

      "requester_name" ->
        "путник"

      "counterpart_name" ->
        "путник"

      "telegram_username" ->
        "Telegram"

      "encounter_id" ->
        "номер запроса"

      "decision" ->
        "решение"

      key_string ->
        if String.ends_with?(key_string, "_id"), do: "номер записи", else: "сведения"
    end
  end

  defp payload_value(key, value) when is_binary(value) do
    case {to_string(key), value} do
      {"status", "arrived"} ->
        "прибыл"

      {"status", "completed"} ->
        "завершено"

      {"status", "failed"} ->
        "провалено"

      {"status", _status} ->
        "неизвестно"

      {"program_type", "basic"} ->
        "Базовое образование"

      {"program_type", "basic_education"} ->
        "Базовое образование"

      {"program_type", "academy_core"} ->
        "Ядро Академии"

      {"program_type", "extended_study"} ->
        "Расширенный курс"

      {"program_type", "academia"} ->
        "Академия наук"

      {"program_type", _program_type} ->
        "неизвестная программа"

      {"track", "wizardry"} ->
        "Чародейство"

      {"track", "alchemy"} ->
        "Алхимия"

      {"track", "mastery"} ->
        "Мастерство"

      {"track", _track} ->
        "не указан"

      {"outcome_tier", "distinction"} ->
        "с отличием"

      {"outcome_tier", "pass"} ->
        "зачёт"

      {"outcome_tier", "probation"} ->
        "испытательный выпуск"

      {"outcome_tier", "expulsion"} ->
        "отчисление"

      {"outcome_tier", "capstone_incomplete"} ->
        "не пройден итоговый проект"

      {"outcome_tier", _outcome_tier} ->
        "итог не указан"

      {"project_kind", "spell"} ->
        "заклинание"

      {"project_kind", "potion"} ->
        "зелье"

      {"project_kind", "tool"} ->
        "инструмент"

      {"project_kind", "thesis"} ->
        "тезис"

      {"project_kind", "course"} ->
        "курс"

      {"project_kind", _project_kind} ->
        "проект"

      {"kind", "city_purchase"} ->
        "городское жильё"

      {"kind", "custom_build"} ->
        "полевое владение"

      {"kind", _kind} ->
        "владение"

      {"extraction_type", "ascent"} ->
        "подъём к выходу"

      {"extraction_type", "return_ritual"} ->
        "ритуал возвращения"

      {"extraction_type", "safe"} ->
        "безопасный выход"

      {"extraction_type", "forced"} ->
        "вынужденный выход"

      {"extraction_type", "emergency"} ->
        "аварийный выход"

      {"extraction_type", _extraction_type} ->
        "неизвестный способ"

      {"club_type", "general_interest"} ->
        "общий круг"

      {"club_type", "dueling"} ->
        "дуэльный клуб"

      {"club_type", "research"} ->
        "исследовательское общество"

      {"club_type", "expedition_planning"} ->
        "экспедиционный стол"

      {"club_type", _club_type} ->
        "иной круг"

      {"organization_kind", "guild"} ->
        "гильдия"

      {"organization_kind", "company"} ->
        "компания"

      {"organization_kind", "council"} ->
        "совет"

      {"organization_kind", "cult"} ->
        "культ"

      {"organization_kind", _organization_kind} ->
        "организация"

      {"telegram_username", username} ->
        username = String.trim_leading(username, "@")
        "@#{username}"

      {"decision", "accept"} ->
        "принято"

      {"decision", "decline"} ->
        "отклонено"

      {"decision", "cancel"} ->
        "отменено"

      {key, other}
      when key in [
             "title",
             "destination_realm_name",
             "freeze_ends_at",
             "club_name",
             "party_name",
             "organization_name",
             "requester_name",
             "counterpart_name"
           ] ->
        other

      {key, other} ->
        if String.ends_with?(key, "_id"), do: other, else: "записано"
    end
  end

  defp payload_value(_key, value) when is_integer(value), do: to_string(value)

  defp payload_value(_key, value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp payload_value(_key, true), do: "да"
  defp payload_value(_key, false), do: "нет"
  defp payload_value(_key, _value), do: "записано"

  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "—"
end
