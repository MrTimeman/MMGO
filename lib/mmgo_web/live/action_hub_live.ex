defmodule MMGOWeb.ActionHubLive do
  @moduledoc """
  The signed player's current-location activity hub.

  Arrival prose and choices come from the durable event instance for the
  scoped character. The browser may request an option, but `MMGO.Play`
  verifies the event, location, and trusted action before anything changes.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  alias MMGO.{Overworld, Play}

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    if connected?(socket) do
      Phoenix.PubSub.subscribe(MMGO.PubSub, Overworld.character_topic(character.id))
    end

    {:ok,
     socket
     |> assign(:page_title, "Локация")
     |> assign(:activity_result, nil)
     |> refresh_hub()}
  end

  @impl true
  def handle_event(
        "resolve_option",
        %{"event_id" => event_id, "option_code" => option_code},
        socket
      ) do
    case Play.resolve_activity_option(
           socket.assigns.current_scope.character,
           event_id,
           option_code
         ) do
      {:ok, %{action: %{type: :navigate, to: destination}}} ->
        {:noreply, push_navigate(socket, to: destination)}

      {:ok, %{action: %{type: :notice, message: message}}} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, message)}

      {:error, :travelling} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы уже в пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, reason} when reason in [:event_not_found, :event_not_current, :event_not_active] ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Это действие уже завершено. Сцена обновлена.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Этот выбор сейчас недоступен.")}
    end
  end

  @impl true
  def handle_event("request_traveler_contact", %{"target_id" => target_id}, socket) do
    case Play.request_traveler_contact(socket.assigns.current_scope.character, target_id) do
      {:ok, %{encounter: encounter}} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, contact_request_message(encounter))}

      {:error, :travelling} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы уже в пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Сейчас нельзя отправить запрос этому путнику.")}
    end
  end

  @impl true
  def handle_event(
        "respond_to_traveler_contact",
        %{"encounter_id" => encounter_id, "decision" => decision},
        socket
      ) do
    case Play.respond_to_traveler_contact(
           socket.assigns.current_scope.character,
           encounter_id,
           decision
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, traveler_contact_response_message(result))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Этот запрос уже закрыт или больше вам не доступен.")}
    end
  end

  @impl true
  def handle_event(
        "respond_to_overworld_encounter",
        %{"encounter_id" => encounter_id, "action" => action},
        socket
      ) do
    case Play.respond_to_overworld_encounter(
           socket.assigns.current_scope.character,
           encounter_id,
           action
         ) do
      {:ok, %{combat: %{id: _combat_id}}} ->
        {:noreply, push_navigate(socket, to: ~p"/combat")}

      {:ok, %{encounter: encounter}} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, encounter_response_message(encounter))}

      {:error, :travelling} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы уже в пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Этот ответ больше недоступен.")}
    end
  end

  @impl true
  def handle_event("start_scavenging", %{"resource_cache_id" => resource_cache_id}, socket) do
    case Play.start_scavenging(socket.assigns.current_scope.character, resource_cache_id, 1) do
      {:ok, %{attempt: attempt}} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, scavenging_started_message(attempt))}

      {:error, :travelling} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы уже в пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Этот источник уже нельзя обыскать.")}
    end
  end

  @impl true
  def handle_event("hear_secret_cult_rumor", _params, socket) do
    case Play.hear_secret_cult_rumor(socket.assigns.current_scope.character) do
      {:ok, _hub} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "В переулках шепчутся о тропе под Горной Стражей.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Шёпот оборвался: зацепки здесь больше нет.")}
    end
  end

  @impl true
  def handle_event("reveal_secret_cult_passage", _params, socket) do
    case Play.reveal_secret_cult_passage(socket.assigns.current_scope.character) do
      {:ok, _hub} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(
           :activity_result,
           "Хранитель признал вас. Безопасный путь в сеть Тайного Культа открыт."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Тайный проход пока не отвечает.")}
    end
  end

  @impl true
  def handle_event("use_secret_cult_passage", %{"destination-id" => destination_id}, socket) do
    case Play.use_secret_cult_passage(socket.assigns.current_scope.character, destination_id) do
      {:ok, _hub} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Тайный ход закрылся за вашей спиной без следа.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Этот проход сейчас не отвечает.")}
    end
  end

  @impl true
  def handle_event("refresh_activity", _params, socket) do
    {:noreply, refresh_hub(socket)}
  end

  @impl true
  def handle_info({:overworld_contact_updated, _encounter_id}, socket) do
    {:noreply, refresh_hub(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main
        id="activity-hub"
        class="evh-scene"
        aria-label="Занятия в текущей локации"
      >
        <div class="evh-shell">
          <div class="evh-hero">
            <.art_slot id="activity-location-art" kind="hero" label={location_art_label(@location)} />
            <.link id="activity-back-to-map" navigate={~p"/map"} class="evh-exit">← На карту</.link>
            <div class="evh-hero__veil"></div>
            <div class="evh-hero__caption">
              <span class={location_badge_class(@location.kind)}>
                {location_kind_label(@location.kind)}
              </span>
              <h1 class="evh-title">{@location.name}</h1>
            </div>
          </div>

          <article id={"activity-event-#{@event.id}"} class="evh-body">
            <p id="activity-world-date" class="evh-date">{format_world_time(@world_time)}</p>
            <h2 class="evh-event-title">{@event.template.title}</h2>
            <p id="activity-event-body" class="evh-narrative">{@event.template.body}</p>
            <p id="activity-guidance" class="evh-guidance">
              На указателях отмечены доступные отсюда места. Печать или монету попросят отдельно:
              случайным касанием договор не заключить.
            </p>

            <p class="evh-legend">Указатели поблизости</p>
            <div id="activity-options" class="evh-actions">
              <button
                :for={option <- @options}
                id={"activity-option-#{option.code}"}
                type="button"
                class="evh-action"
                phx-click="resolve_option"
                phx-value-event_id={@event.id}
                phx-value-option_code={option.code}
                phx-disable-with="Открываем…"
              >
                <span class="evh-action__glyph">{option_glyph(option.action_key)}</span>
                <span class="evh-action__text">
                  <span class="evh-action__title">{option.label}</span>
                  <span class="evh-action__hint">{option_hint(option.action_key)}</span>
                </span>
                <span class="evh-action__chev" aria-hidden="true">→</span>
              </button>
            </div>

            <p :if={@options == []} id="activity-options-empty" class="evh-outcome">
              Здесь пока нет доступных занятий.
            </p>

            <div :if={@activity_result} id="activity-result" class="evh-outcome" role="status">
              <strong>Готово.</strong>
              <span>{@activity_result}</span>
            </div>

            <section
              :if={@secret_cult.can_hear_rumor? or @secret_cult.stage != :unknown}
              id="activity-secret-cult"
              class="evh-subscene evh-subscene--secret"
            >
              <p class="evh-subscene__kicker">
                необязательная зацепка
              </p>
              <h2 class="evh-subscene__title">Слух о тайном пути</h2>
              <%= cond do %>
                <% @secret_cult.can_hear_rumor? -> %>
                  <p id="secret-cult-rumor-copy" class="evh-subscene__copy">
                    В трактирных разговорах мелькает имя Хранителя. Говорят, под Горной Стражей есть
                    путь, который не отмечен на картах.
                  </p>
                  <button
                    id="secret-cult-hear-rumor"
                    type="button"
                    class="evh-object-btn evh-object-btn--secret"
                    phx-click="hear_secret_cult_rumor"
                  >
                    Расспросить о Хранителе
                  </button>
                <% @secret_cult.can_reveal_passage? -> %>
                  <p id="secret-cult-watchtower-copy" class="evh-subscene__copy">
                    Камни Горной Стражи отвечают на услышанное имя. Здесь можно потребовать встречу с
                    Хранителем и открыть путь к Башне.
                  </p>
                  <button
                    id="secret-cult-reveal-passage"
                    type="button"
                    class="evh-object-btn evh-object-btn--secret"
                    phx-click="reveal_secret_cult_passage"
                  >
                    Позвать Хранителя
                  </button>
                <% @secret_cult.passage_available? -> %>
                  <p id="secret-cult-passage-open" class="evh-subscene__copy evh-subscene__copy--open">
                    Вы носите знак прохода. Сеть Культа может безопасно перенести вас между связными
                    точками, включая Столицу и Башню.
                  </p>
                  <div id="secret-cult-network" class="evh-object-actions">
                    <button
                      :for={destination <- @secret_cult.passage_destinations}
                      id={"secret-cult-travel-#{destination.id}"}
                      type="button"
                      class="evh-object-btn evh-object-btn--passage"
                      phx-click="use_secret_cult_passage"
                      phx-value-destination-id={destination.id}
                    >
                      Тайным ходом в {destination.name}
                    </button>
                  </div>
                <% @secret_cult.stage == :rumor_heard -> %>
                  <p id="secret-cult-rumor-heard" class="evh-subscene__copy">
                    Вы знаете, куда идти: Хранитель ждёт у Горной Стражи, в горах перед Башней.
                  </p>
                <% true -> %>
                  <p
                    id="secret-cult-passage-revoked"
                    class="evh-subscene__copy evh-subscene__copy--muted"
                  >
                    След прохода остался, но действующего права на сеть Культа сейчас нет.
                  </p>
              <% end %>
            </section>

            <section
              :if={
                @scavenging.available_caches != [] or
                  not is_nil(@scavenging.active_attempt) or
                  not is_nil(@scavenging.latest_completed_attempt)
              }
              id="activity-scavenging"
              class="evh-subscene evh-subscene--field"
            >
              <div class="evh-subscene__head">
                <h2 class="evh-subscene__title">Поиск ресурсов</h2>
                <button
                  id="activity-refresh-scavenging"
                  type="button"
                  class="evh-tool-link"
                  phx-click="refresh_activity"
                >
                  сверить записи
                </button>
              </div>

              <article
                :if={@scavenging.active_attempt}
                id={"activity-attempt-#{@scavenging.active_attempt.id}"}
                class="evh-status-slip evh-status-slip--active"
              >
                <p class="evh-status-slip__title">
                  Идёт поиск: {@scavenging.active_attempt.resource_name}
                </p>
                <p class="evh-status-slip__meta">
                  Ищем {@scavenging.active_attempt.quantity_requested} ед. · завершение {format_completion(
                    @scavenging.active_attempt.completes_at
                  )}
                </p>
              </article>

              <article
                :if={@scavenging.latest_completed_attempt}
                id={"activity-scavenge-result-#{@scavenging.latest_completed_attempt.id}"}
                class="evh-status-slip evh-status-slip--done"
              >
                <p class="evh-status-slip__title">
                  Поиск завершён: {@scavenging.latest_completed_attempt.resource_name}
                </p>
                <p class="evh-status-slip__meta">
                  Добыто {@scavenging.latest_completed_attempt.quantity_yielded} ед. · опыт +{@scavenging.latest_completed_attempt.xp_awarded}
                </p>
              </article>

              <ul
                :if={@scavenging.available_caches != []}
                id="activity-scavenge-caches"
                class="evh-ledger"
              >
                <li
                  :for={resource_cache <- @scavenging.available_caches}
                  id={"activity-scavenge-cache-#{resource_cache.id}"}
                  class="evh-ledger__row"
                >
                  <span class="evh-ledger__entry">
                    <span class="evh-ledger__name">{resource_cache.name}</span>
                    <span class="evh-ledger__meta">
                      Осталось: {resource_cache.quantity_remaining} из {resource_cache.quantity_total}
                    </span>
                  </span>
                  <button
                    :if={is_nil(@scavenging.active_attempt)}
                    id={"activity-start-scavenge-#{resource_cache.id}"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small"
                    phx-click="start_scavenging"
                    phx-value-resource_cache_id={resource_cache.id}
                    phx-disable-with="Начинаем…"
                  >
                    Искать 1
                  </button>
                </li>
              </ul>
            </section>

            <section
              :if={@nearby_characters != []}
              id="activity-nearby"
              class="evh-subscene evh-subscene--travellers"
            >
              <div class="evh-subscene__head">
                <h2 class="evh-subscene__title">Путники рядом</h2>
                <span class="evh-subscene__place">
                  {@location.name}
                </span>
              </div>
              <ul class="evh-ledger evh-ledger--people">
                <li
                  :for={nearby <- @nearby_characters}
                  id={"activity-nearby-#{nearby.id}"}
                  class="evh-ledger__row"
                >
                  <span class="evh-ledger__entry">
                    <span class="evh-ledger__name">{nearby.name}</span>
                    <span class="evh-ledger__meta">уровень {nearby.level}</span>
                  </span>
                  <button
                    :if={not pending_contact_with?(@open_encounters, nearby.id)}
                    id={"activity-request-contact-#{nearby.id}"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small evh-contact-request-btn"
                    phx-click="request_traveler_contact"
                    phx-value-target_id={nearby.id}
                    phx-disable-with="Отправляем…"
                  >
                    Заговорить
                  </button>
                  <span
                    :if={pending_contact_with?(@open_encounters, nearby.id)}
                    id={"activity-contact-state-#{nearby.id}"}
                    class="evh-contact-state"
                  >
                    {pending_contact_label(@open_encounters, nearby.id)}
                  </span>
                </li>
              </ul>
            </section>

            <section
              :if={@open_encounters != []}
              id="activity-open-encounters"
              class="evh-subscene evh-subscene--encounters"
            >
              <h2 class="evh-subscene__title">Запросы на связь и встречи</h2>
              <article
                :for={encounter <- @open_encounters}
                id={"activity-encounter-#{encounter.id}"}
                class={[
                  "evh-encounter",
                  encounter.contact_request? && "evh-encounter--contact"
                ]}
              >
                <div class="evh-encounter__head">
                  <p class="evh-encounter__name">
                    {encounter.counterpart.name}
                    <span>· ур. {encounter.counterpart.level}</span>
                  </p>
                  <p class="evh-encounter__status">{encounter_status_label(encounter)}</p>
                </div>

                <div :if={encounter.contact_request?} class="evh-contact-request">
                  <p
                    id={"activity-encounter-#{encounter.id}-contact-copy"}
                    class="evh-encounter__waiting"
                  >
                    <%= if encounter.direction == :incoming do %>
                      Путник предлагает обменяться Telegram-контактами. Имя пользователя откроется
                      вам обоим только после согласия.
                    <% else %>
                      Запрос отправлен. Telegram-имена останутся скрыты, пока путник не согласится.
                    <% end %>
                  </p>

                  <div
                    :if={encounter.can_accept? or encounter.can_decline? or encounter.can_cancel?}
                    id={"activity-encounter-#{encounter.id}-contact-actions"}
                    class="evh-object-actions evh-contact-actions"
                  >
                    <button
                      :if={encounter.can_accept?}
                      id={"activity-encounter-#{encounter.id}-accept-contact"}
                      type="button"
                      class="evh-object-btn evh-object-btn--small evh-object-btn--consent"
                      phx-click="respond_to_traveler_contact"
                      phx-value-encounter_id={encounter.id}
                      phx-value-decision="accept"
                      phx-disable-with="Принимаем…"
                    >
                      Принять и обменяться контактами
                    </button>
                    <button
                      :if={encounter.can_decline?}
                      id={"activity-encounter-#{encounter.id}-decline-contact"}
                      type="button"
                      class="evh-object-btn evh-object-btn--small"
                      phx-click="respond_to_traveler_contact"
                      phx-value-encounter_id={encounter.id}
                      phx-value-decision="decline"
                      phx-disable-with="Отклоняем…"
                    >
                      Отклонить
                    </button>
                    <button
                      :if={encounter.can_cancel?}
                      id={"activity-encounter-#{encounter.id}-cancel-contact"}
                      type="button"
                      class="evh-object-btn evh-object-btn--small"
                      phx-click="respond_to_traveler_contact"
                      phx-value-encounter_id={encounter.id}
                      phx-value-decision="cancel"
                      phx-disable-with="Отменяем…"
                    >
                      Отменить запрос
                    </button>
                  </div>
                </div>

                <div
                  :if={not encounter.contact_request? and encounter.can_respond?}
                  class="evh-object-actions"
                >
                  <button
                    id={"activity-encounter-#{encounter.id}-greet"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="greet"
                  >
                    Поприветствовать
                  </button>
                  <button
                    id={"activity-encounter-#{encounter.id}-trade"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="trade"
                  >
                    Предложить обмен
                  </button>
                  <button
                    :if={@overworld.attack_available?}
                    id={"activity-encounter-#{encounter.id}-attack"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small evh-object-btn--danger"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="attack"
                  >
                    Напасть
                  </button>
                  <button
                    id={"activity-encounter-#{encounter.id}-avoid"}
                    type="button"
                    class="evh-object-btn evh-object-btn--small"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="avoid"
                  >
                    Разойтись
                  </button>
                </div>
                <p
                  :if={not encounter.contact_request? and not encounter.can_respond?}
                  class="evh-encounter__waiting"
                >
                  Ваш ответ уже сделан; ждём решения другого путника.
                </p>
              </article>
            </section>
          </article>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_hub(socket) do
    case Play.activity_hub_state(socket.assigns.current_scope.character) do
      {:ok, hub} ->
        socket
        |> assign(:realm, hub.realm)
        |> assign(:character, hub.character)
        |> assign(:location, hub.location)
        |> assign(:world_time, hub.world_time)
        |> assign(:event, hub.event)
        |> assign(:options, hub.options)
        |> assign(:nearby_characters, hub.nearby_characters)
        |> assign(:open_encounters, hub.open_encounters)
        |> assign(:scavenging, hub.scavenging)
        |> assign(:secret_cult, hub.secret_cult)
        |> assign(:survival, hub.survival)
        |> assign(:atmosphere, hub.atmosphere)
        |> assign(:overworld, hub.overworld)

      {:error, :travelling} ->
        socket
        |> put_flash(:info, "Вы уже в пути.")
        |> push_navigate(to: ~p"/travel")

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Не удалось определить вашу текущую локацию.")
        |> push_navigate(to: ~p"/map")
    end
  end

  defp format_world_time(world_time) do
    "#{world_time.day}-й день #{world_time.month_name}, #{world_time.year} год · #{world_time.season_name}"
  end

  defp location_art_label(location) do
    case location.kind do
      :city -> "#{location.name} — городская площадь"
      :tower -> "#{location.name} — башня на горизонте"
      :wilderness -> "#{location.name} — дикая дорога"
      :dungeon_entrance -> "#{location.name} — врата в глубины"
      _ -> "#{location.name} — текущая локация"
    end
  end

  defp location_badge_class(kind), do: ["evh-badge", "evh-badge--#{kind}"]

  defp location_kind_label(:city), do: "город"
  defp location_kind_label(:tower), do: "башня"
  defp location_kind_label(:wilderness), do: "глушь"
  defp location_kind_label(:base), do: "база"
  defp location_kind_label(:dungeon_entrance), do: "врата подземелья"
  defp location_kind_label(_kind), do: "локация"

  defp option_glyph("academy"), do: "❦"
  defp option_glyph("spells"), do: "✶"
  defp option_glyph("routes"), do: "✦"
  defp option_glyph("npc_shops"), do: "⚖"
  defp option_glyph("party"), do: "◆"
  defp option_glyph("party_hub"), do: "◆"
  defp option_glyph("dungeon"), do: "⚔"
  defp option_glyph("base"), do: "⌂"
  defp option_glyph("base_storage"), do: "⌂"
  defp option_glyph("craft"), do: "⚒"
  defp option_glyph("alchemy"), do: "⚗"
  defp option_glyph("rest"), do: "☾"
  defp option_glyph("scavenge"), do: "☙"
  defp option_glyph(_action_key), do: "◇"

  defp option_hint("academy"), do: "учёба, экзамены и клубы"
  defp option_hint("spells"), do: "работа с гримуаром"
  defp option_hint("routes"), do: "выбрать следующий путь"
  defp option_hint("npc_shops"), do: "рынок, обмен и сделки"
  defp option_hint("party"), do: "собрать отряд"
  defp option_hint("party_hub"), do: "найти спутников или создать отряд"
  defp option_hint("dungeon"), do: "подготовиться к спуску"
  defp option_hint("base"), do: "владение, припасы и отдых"
  defp option_hint("base_storage"), do: "склад базы и её запасы"
  defp option_hint("craft"), do: "верстак и снаряжение"
  defp option_hint("alchemy"), do: "рецепты и реагенты"
  defp option_hint("rest"), do: "восстановить силы у припасов"
  defp option_hint("scavenge"), do: "осмотреть местные ресурсы"
  defp option_hint(_action_key), do: "доступно в этой локации"

  defp contact_request_message(encounter) do
    "Запрос для #{encounter.counterpart.name} отправлен. Telegram-имена скрыты до обоюдного согласия."
  end

  defp traveler_contact_response_message(%{decision: :accept, encounter: encounter}) do
    "Вы приняли запрос #{encounter.counterpart.name}. Контакт придёт в личных вестях и Telegram, если у вас обоих указан публичный @username."
  end

  defp traveler_contact_response_message(%{decision: :decline, encounter: encounter}) do
    "Вы отклонили запрос #{encounter.counterpart.name}. Контакты не раскрыты."
  end

  defp traveler_contact_response_message(%{decision: :cancel, encounter: encounter}) do
    "Запрос для #{encounter.counterpart.name} отменён. Контакты не раскрыты."
  end

  defp encounter_response_message(%{status: :greeted, counterpart: counterpart}) do
    "Вы и #{counterpart.name} обменялись приветствиями."
  end

  defp encounter_response_message(%{status: :trading, counterpart: counterpart}) do
    "Вы договорились обсудить обмен с #{counterpart.name}."
  end

  defp encounter_response_message(%{status: :avoided, counterpart: counterpart}) do
    "Вы разошлись с #{counterpart.name} без лишнего риска."
  end

  defp encounter_response_message(%{counterpart: counterpart}) do
    "Ваш выбор передан #{counterpart.name}."
  end

  defp encounter_status_label(%{contact_request?: true, direction: :incoming}),
    do: "ждёт вашего решения"

  defp encounter_status_label(%{contact_request?: true, direction: :outgoing}),
    do: "ожидает согласия"

  defp encounter_status_label(%{status: :pending}), do: "ожидает ответа"
  defp encounter_status_label(%{status: :active}), do: "встреча идёт"
  defp encounter_status_label(%{status: :greeted}), do: "завершено: приветствие"
  defp encounter_status_label(%{status: :trading}), do: "завершено: обмен"
  defp encounter_status_label(%{status: :avoided}), do: "завершено: разошлись"
  defp encounter_status_label(_encounter), do: "завершено"

  defp pending_contact_with?(encounters, character_id) do
    Enum.any?(encounters, &(&1.contact_request? and &1.counterpart.id == character_id))
  end

  defp pending_contact_label(encounters, character_id) do
    case Enum.find(encounters, &(&1.contact_request? and &1.counterpart.id == character_id)) do
      %{direction: :incoming} -> "Запрос получен"
      %{direction: :outgoing} -> "Запрос отправлен"
      _encounter -> "Запрос открыт"
    end
  end

  defp scavenging_started_message(attempt) do
    "Поиск #{attempt.resource_name} начался. Результат придёт после завершения работы."
  end

  defp format_completion(%DateTime{} = completion), do: Calendar.strftime(completion, "%H:%M UTC")
  defp format_completion(_completion), do: "скоро"
end
