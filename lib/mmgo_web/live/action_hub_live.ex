defmodule MMGOWeb.ActionHubLive do
  @moduledoc """
  The signed player's current-location activity hub.

  Arrival prose and choices come from the durable event instance for the
  scoped character. The browser may request an option, but `MMGO.Play`
  verifies the event, location, and trusted action before anything changes.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
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
  def handle_event("start_overworld_encounter", %{"target_id" => target_id}, socket) do
    case Play.start_overworld_encounter(socket.assigns.current_scope.character, target_id) do
      {:ok, %{encounter: encounter}} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, encounter_started_message(encounter))}

      {:error, :travelling} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы уже в пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_hub()
         |> assign(:activity_result, "Сейчас нельзя начать встречу с этим путником.")}
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
            <h2 class="font-serif text-xl text-amber-100">{@event.template.title}</h2>
            <p id="activity-event-body" class="evh-narrative">{@event.template.body}</p>

            <p class="evh-legend">Здесь можно</p>
            <div id="activity-options" class="evh-actions">
              <button
                :for={option <- @options}
                id={"activity-option-#{option.code}"}
                type="button"
                class="evh-action text-left"
                phx-click="resolve_option"
                phx-value-event_id={@event.id}
                phx-value-option_code={option.code}
              >
                <span class="evh-action__glyph">{option_glyph(option.action_key)}</span>
                <span class="evh-action__text">
                  <span class="evh-action__title">{option.label}</span>
                  <span class="evh-action__hint">{option_hint(option.action_key)}</span>
                </span>
                <span class="evh-action__chev" aria-hidden="true">›</span>
              </button>
            </div>

            <p :if={@options == []} id="activity-options-empty" class="evh-outcome">
              Здесь пока нет доступных занятий.
            </p>

            <p :if={@activity_result} id="activity-result" class="evh-outcome" role="status">
              {@activity_result}
            </p>

            <section
              :if={@secret_cult.can_hear_rumor? or @secret_cult.stage != :unknown}
              id="activity-secret-cult"
              class="mt-8 border-t border-violet-500/25 pt-5"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">тайный путь</p>
              <h2 class="mt-1 font-serif text-xl text-violet-100">Тайный Культ</h2>
              <%= cond do %>
                <% @secret_cult.can_hear_rumor? -> %>
                  <p id="secret-cult-rumor-copy" class="mt-2 text-sm leading-6 text-stone-300">
                    В трактирных разговорах мелькает имя Хранителя. Говорят, под Горной Стражей есть
                    путь, который не отмечен на картах.
                  </p>
                  <button
                    id="secret-cult-hear-rumor"
                    type="button"
                    class="mt-4 rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:border-violet-200 hover:bg-violet-300/10"
                    phx-click="hear_secret_cult_rumor"
                  >
                    Расспросить о Хранителе
                  </button>
                <% @secret_cult.can_reveal_passage? -> %>
                  <p id="secret-cult-watchtower-copy" class="mt-2 text-sm leading-6 text-stone-300">
                    Камни Горной Стражи отвечают на услышанное имя. Здесь можно потребовать встречу с
                    Хранителем и открыть путь к Башне.
                  </p>
                  <button
                    id="secret-cult-reveal-passage"
                    type="button"
                    class="mt-4 rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:border-violet-200 hover:bg-violet-300/10"
                    phx-click="reveal_secret_cult_passage"
                  >
                    Позвать Хранителя
                  </button>
                <% @secret_cult.passage_available? -> %>
                  <p id="secret-cult-passage-open" class="mt-2 text-sm leading-6 text-emerald-100">
                    Вы носите знак прохода. Сеть Культа может безопасно перенести вас между связными
                    точками, включая Столицу и Башню.
                  </p>
                  <div id="secret-cult-network" class="mt-4 flex flex-wrap gap-2">
                    <button
                      :for={destination <- @secret_cult.passage_destinations}
                      id={"secret-cult-travel-#{destination.id}"}
                      type="button"
                      class="rounded border border-emerald-300/50 px-3 py-2 text-sm text-emerald-100 transition hover:border-emerald-200 hover:bg-emerald-300/10"
                      phx-click="use_secret_cult_passage"
                      phx-value-destination-id={destination.id}
                    >
                      Тайным ходом в {destination.name}
                    </button>
                  </div>
                <% @secret_cult.stage == :rumor_heard -> %>
                  <p id="secret-cult-rumor-heard" class="mt-2 text-sm leading-6 text-stone-300">
                    Вы знаете, куда идти: Хранитель ждёт у Горной Стражи, в горах перед Башней.
                  </p>
                <% true -> %>
                  <p id="secret-cult-passage-revoked" class="mt-2 text-sm leading-6 text-stone-400">
                    След прохода остался, но действующего права на сеть Культа сейчас нет.
                  </p>
              <% end %>
            </section>

            <section id="activity-scavenging" class="mt-8 border-t border-stone-700/70 pt-5">
              <div class="flex flex-wrap items-baseline justify-between gap-3">
                <h2 class="font-serif text-xl text-amber-100">Поиск ресурсов</h2>
                <button
                  id="activity-refresh-scavenging"
                  type="button"
                  class="text-xs text-stone-400 underline-offset-2 transition hover:text-stone-200 hover:underline"
                  phx-click="refresh_activity"
                >
                  Обновить
                </button>
              </div>

              <article
                :if={@scavenging.active_attempt}
                id={"activity-attempt-#{@scavenging.active_attempt.id}"}
                class="mt-3 rounded-md border border-amber-500/35 bg-stone-950/45 p-3"
              >
                <p class="text-sm text-amber-100">
                  Идёт поиск: {@scavenging.active_attempt.resource_name}
                </p>
                <p class="mt-1 text-xs text-stone-400">
                  Ищем {@scavenging.active_attempt.quantity_requested} ед. · завершение {format_completion(
                    @scavenging.active_attempt.completes_at
                  )}
                </p>
              </article>

              <article
                :if={@scavenging.latest_completed_attempt}
                id={"activity-scavenge-result-#{@scavenging.latest_completed_attempt.id}"}
                class="mt-3 rounded-md border border-emerald-500/35 bg-stone-950/45 p-3"
              >
                <p class="text-sm text-emerald-100">
                  Поиск завершён: {@scavenging.latest_completed_attempt.resource_name}
                </p>
                <p class="mt-1 text-xs text-stone-400">
                  Добыто {@scavenging.latest_completed_attempt.quantity_yielded} ед. · опыт +{@scavenging.latest_completed_attempt.xp_awarded}
                </p>
              </article>

              <p
                :if={@scavenging.available_caches == [] and is_nil(@scavenging.active_attempt)}
                id="activity-scavenging-empty"
                class="mt-2 text-sm text-stone-400"
              >
                Здесь пока нечего собирать.
              </p>

              <ul
                :if={@scavenging.available_caches != []}
                id="activity-scavenge-caches"
                class="mt-3 space-y-2"
              >
                <li
                  :for={resource_cache <- @scavenging.available_caches}
                  id={"activity-scavenge-cache-#{resource_cache.id}"}
                  class="flex items-center justify-between gap-3 rounded-md border border-stone-700/80 bg-stone-950/40 px-3 py-2"
                >
                  <span>
                    <span class="block text-sm text-stone-100">{resource_cache.name}</span>
                    <span class="block text-xs text-stone-500">
                      Осталось: {resource_cache.quantity_remaining} из {resource_cache.quantity_total}
                    </span>
                  </span>
                  <button
                    :if={is_nil(@scavenging.active_attempt)}
                    id={"activity-start-scavenge-#{resource_cache.id}"}
                    type="button"
                    class="rounded border border-emerald-500/50 px-2 py-1 text-xs text-emerald-100 transition hover:border-emerald-300 hover:bg-emerald-400/10"
                    phx-click="start_scavenging"
                    phx-value-resource_cache_id={resource_cache.id}
                  >
                    Искать 1
                  </button>
                </li>
              </ul>
            </section>

            <section id="activity-nearby" class="mt-8 border-t border-stone-700/70 pt-5">
              <div class="flex items-baseline justify-between gap-3">
                <h2 class="font-serif text-xl text-amber-100">Путники рядом</h2>
                <span class="text-xs uppercase tracking-[0.14em] text-stone-500">
                  {@location.name}
                </span>
              </div>
              <p
                :if={@nearby_characters == []}
                id="activity-nearby-empty"
                class="mt-2 text-sm text-stone-400"
              >
                Поблизости никого нет.
              </p>
              <ul :if={@nearby_characters != []} class="mt-3 space-y-2">
                <li
                  :for={nearby <- @nearby_characters}
                  id={"activity-nearby-#{nearby.id}"}
                  class="flex items-center justify-between gap-3 rounded-md border border-stone-700/80 bg-stone-950/40 px-3 py-2"
                >
                  <span>
                    <span class="block text-sm text-stone-100">{nearby.name}</span>
                    <span class="block text-xs text-stone-500">уровень {nearby.level}</span>
                  </span>
                  <button
                    id={"activity-start-encounter-#{nearby.id}"}
                    type="button"
                    class="rounded border border-amber-500/50 px-2 py-1 text-xs text-amber-100 transition hover:border-amber-300 hover:bg-amber-400/10"
                    phx-click="start_overworld_encounter"
                    phx-value-target_id={nearby.id}
                  >
                    Заговорить
                  </button>
                </li>
              </ul>
            </section>

            <section :if={@open_encounters != []} id="activity-open-encounters" class="mt-5">
              <h2 class="font-serif text-xl text-amber-100">Незавершённые встречи</h2>
              <article
                :for={encounter <- @open_encounters}
                id={"activity-encounter-#{encounter.id}"}
                class="mt-3 rounded-md border border-amber-500/35 bg-stone-950/45 p-3"
              >
                <div class="flex flex-wrap items-baseline justify-between gap-2">
                  <p class="text-sm text-stone-100">
                    {encounter.counterpart.name}
                    <span class="text-stone-500">· ур. {encounter.counterpart.level}</span>
                  </p>
                  <p class="text-xs text-stone-400">{encounter_status_label(encounter.status)}</p>
                </div>

                <div :if={encounter.can_respond?} class="mt-3 flex flex-wrap gap-2">
                  <button
                    id={"activity-encounter-#{encounter.id}-greet"}
                    type="button"
                    class="rounded border border-stone-600 px-2 py-1 text-xs text-stone-200 transition hover:border-stone-400"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="greet"
                  >
                    Поприветствовать
                  </button>
                  <button
                    id={"activity-encounter-#{encounter.id}-trade"}
                    type="button"
                    class="rounded border border-stone-600 px-2 py-1 text-xs text-stone-200 transition hover:border-stone-400"
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
                    class="rounded border border-red-500/55 px-2 py-1 text-xs text-red-200 transition hover:border-red-300 hover:bg-red-500/10"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="attack"
                  >
                    Напасть
                  </button>
                  <button
                    id={"activity-encounter-#{encounter.id}-avoid"}
                    type="button"
                    class="rounded border border-stone-600 px-2 py-1 text-xs text-stone-200 transition hover:border-stone-400"
                    phx-click="respond_to_overworld_encounter"
                    phx-value-encounter_id={encounter.id}
                    phx-value-action="avoid"
                  >
                    Разойтись
                  </button>
                </div>
                <p :if={not encounter.can_respond?} class="mt-2 text-xs text-stone-500">
                  Ваш ответ уже сделан; ждём решения другого путника.
                </p>
              </article>
            </section>
          </article>

          <footer class="evh-compass" aria-label="Состояние персонажа">
            <span id="activity-survival-state" class="evh-compass__label">
              {@character.name} · {survival_status(@survival)}
            </span>
            <div class="evh-compass__chips">
              <.link id="activity-open-inventory" navigate={~p"/inventory"} class="evh-chip">
                Котомка
              </.link>
              <.link id="activity-plan-route" navigate={~p"/map"} class="evh-chip">
                Проложить путь
              </.link>
            </div>
          </footer>
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

  defp encounter_started_message(encounter) do
    "Вы обозначили встречу с #{encounter.counterpart.name}. Можно выбрать, как поступить."
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

  defp encounter_status_label(:pending), do: "ожидает ответа"
  defp encounter_status_label(:active), do: "встреча идёт"
  defp encounter_status_label(:greeted), do: "завершено: приветствие"
  defp encounter_status_label(:trading), do: "завершено: обмен"
  defp encounter_status_label(:avoided), do: "завершено: разошлись"
  defp encounter_status_label(_status), do: "завершено"

  defp scavenging_started_message(attempt) do
    "Поиск #{attempt.resource_name} начался. Результат придёт после завершения работы."
  end

  defp format_completion(%DateTime{} = completion), do: Calendar.strftime(completion, "%H:%M UTC")
  defp format_completion(_completion), do: "скоро"

  defp survival_status(%{starving?: true, health_drain: health_drain}) do
    "голод: урон #{health_drain}"
  end

  defp survival_status(%{recovered?: true}), do: "силы восстановлены"
  defp survival_status(%{food_units: food_units}), do: "еда #{food_units}"
end
