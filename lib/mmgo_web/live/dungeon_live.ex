defmodule MMGOWeb.DungeonLive do
  @moduledoc """
  Scoped browser surface for an active party expedition beneath the Tower.

  Every action is delegated to `MMGO.Play`, which re-resolves the current
  expedition, node, encounter, loot, and resource from persisted state.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Подземелье")
     |> assign(:error, nil)
     |> refresh_dungeon()}
  end

  @impl true
  def handle_event("enter", _params, socket) do
    case Play.enter_current_dungeon(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket |> put_flash(:info, "Экспедиция вошла в Подземелье.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("move", %{"node-id" => node_id}, socket) do
    case Play.move_in_dungeon(socket.assigns.character, node_id) do
      {:ok, state} -> {:noreply, socket |> assign(:error, nil) |> assign_state(state)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("avoid", _params, socket) do
    case Play.avoid_current_dungeon_encounter(socket.assigns.character) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Встреча обойдена.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("start_combat", _params, socket) do
    case Play.start_current_dungeon_combat(socket.assigns.character) do
      {:ok, %{combat: combat}} -> {:noreply, push_navigate(socket, to: ~p"/combat/#{combat.id}")}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("sync_combat", _params, socket) do
    case Play.sync_current_dungeon_combat(socket.assigns.character) do
      {:ok, %{failed?: true}} ->
        {:noreply, push_navigate(socket, to: ~p"/defeat")}

      {:ok, %{state: state}} ->
        {:noreply, socket |> put_flash(:info, "Итог встречи сохранён.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("claim_loot", %{"loot-drop-id" => loot_drop_id}, socket) do
    case Play.claim_current_dungeon_loot(socket.assigns.character, loot_drop_id) do
      {:ok, state} ->
        {:noreply,
         socket |> put_flash(:info, "Добыча добавлена в котомку.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("harvest", %{"resource-id" => resource_id}, socket) do
    case Play.harvest_current_dungeon_resource(socket.assigns.character, resource_id, 1) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ресурс собран: поиск занял 1 игровой день и принёс опыт.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("extract", _params, socket) do
    case Play.extract_current_dungeon(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Экспедиция поднялась к вратам Башни.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("return_ritual", _params, socket) do
    case Play.begin_current_return_ritual(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ритуал возвращения начат. Он завершится по времени мира.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_dungeon(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main id="dungeon-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-5xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="dungeon-back-to-party"
              navigate={~p"/party"}
              class="text-sm text-amber-200 underline decoration-amber-500/40 underline-offset-4"
            >
              ← Отряд
            </.link>
            <button
              id="dungeon-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200 hover:border-stone-400"
            >
              Обновить состояние
            </button>
          </div>

          <header class="rounded-2xl border border-amber-400/25 bg-gradient-to-br from-stone-900 via-stone-950 to-amber-950/30 p-6 shadow-2xl">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-amber-300/75">
              экспедиция · подземелье
            </p>
            <h1 class="mt-2 font-serif text-3xl text-amber-100">{dungeon_title(@state)}</h1>
            <p class="mt-3 max-w-3xl text-sm leading-6 text-stone-300">{dungeon_subtitle(@state)}</p>
          </header>

          <div
            :if={@error}
            id="dungeon-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section
            :if={is_nil(@state.expedition)}
            id="dungeon-no-expedition"
            class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6"
          >
            <h2 class="font-serif text-2xl text-stone-100">Сначала соберите экспедицию</h2>
            <p class="mt-2 text-sm leading-6 text-stone-400">
              В Подземелье входит активный отряд, собранный у врат Башни.
            </p>
            <.link
              id="dungeon-form-party"
              navigate={~p"/party"}
              class="mt-4 inline-flex rounded-lg bg-amber-300 px-4 py-3 text-sm font-semibold text-stone-950 hover:bg-amber-200"
            >
              Открыть отряд
            </.link>
          </section>

          <section
            :if={@state.expedition}
            id="dungeon-expedition"
            class="grid gap-4 lg:grid-cols-[1.5fr_1fr]"
          >
            <article class="rounded-2xl border border-stone-700 bg-stone-900/80 p-5 shadow-lg">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.2em] text-stone-500">состав</p>
                  <h2 class="mt-1 font-serif text-2xl text-stone-100">{@state.party.name}</h2>
                </div>
                <span
                  id="dungeon-run-status"
                  class="rounded-full border border-amber-300/25 bg-amber-300/10 px-3 py-1 text-xs font-semibold text-amber-100"
                >
                  {run_status(@state.run)}
                </span>
              </div>
              <ul id="dungeon-members" class="mt-4 space-y-2">
                <li
                  :for={member <- @state.members}
                  id={"dungeon-member-#{member.character_id}"}
                  class="flex items-center justify-between rounded-lg bg-stone-950/55 px-3 py-2 text-sm"
                >
                  <span>{member.character.name}</span>
                  <span class="text-stone-400">ур. {member.character.level}</span>
                </li>
              </ul>
              <div
                id="dungeon-loot-policy"
                class="mt-4 rounded-xl border border-violet-300/20 bg-violet-950/20 p-3"
              >
                <p class="text-xs uppercase tracking-[0.18em] text-violet-200/70">делёж добычи</p>
                <p id="dungeon-loot-policy-value" class="mt-1 font-medium text-violet-100">
                  {loot_policy_label(@state.loot_policy)}
                </p>
                <p id="dungeon-loot-policy-note" class="mt-1 text-xs leading-5 text-stone-400">
                  Это договорённость отряда: доступный трофей технически может взять любой участник.
                </p>
              </div>
            </article>

            <article
              id="dungeon-supplies"
              class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-5 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">припасы</p>
              <%= if @state.survival do %>
                <p id="dungeon-survival-food" class="mt-2 font-serif text-3xl text-emerald-100">
                  {@state.survival.food_units_remaining}
                </p>
                <p class="text-sm text-emerald-100/75">
                  ед. еды из {@state.survival.food_units_initial} на старте · расход {@state.survival.food_units_consumed}
                </p>
                <p id="dungeon-survival-carry" class="mt-3 text-sm text-stone-300">
                  Вес: {@state.survival.carried_weight} / {@state.survival.carry_capacity}
                </p>
                <p
                  :if={@state.survival.encumbered?}
                  id="dungeon-overloaded"
                  class="mt-2 text-sm text-amber-200"
                >
                  Перегруз удваивает стоимость каждого перехода.
                </p>
                <p
                  :if={
                    @state.survival.food_units_remaining == 0 and
                      @state.survival.foodless_game_days == 0
                  }
                  id="dungeon-starvation-risk"
                  class="mt-2 text-sm text-amber-200"
                >
                  Рационы закончились: следующий переход займёт больше времени.
                </p>
                <p
                  :if={@state.survival.foodless_game_days > 0}
                  id="dungeon-starvation-risk"
                  class="mt-2 text-sm text-red-200"
                >
                  <%= if @state.survival.shared_hp_drain > 0 do %>
                    Без еды уже {@state.survival.foodless_game_days} игровых дней: перед следующим боем отряд потеряет {@state.survival.shared_hp_drain} общего здоровья.
                  <% else %>
                    Без еды уже {@state.survival.foodless_game_days} игровых дней: следующий переход усилит истощение.
                  <% end %>
                </p>
              <% else %>
                <p class="mt-2 font-serif text-3xl text-emerald-100">
                  {@state.supply.total_food_units}
                </p>
                <p class="text-sm text-emerald-100/75">
                  ед. еды · около {@state.supply.projected_days} игровых дней
                </p>
                <p class="mt-3 text-sm text-stone-300">
                  Вес: {@state.supply.total_carried_weight} / {@state.supply.total_carry_capacity}
                </p>
              <% end %>
            </article>

            <article
              :if={is_map(@state.route_plan)}
              id="dungeon-route-plan"
              class="rounded-2xl border border-lime-400/20 bg-lime-950/15 p-5 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-lime-200/75">маршрутный план</p>
              <p id="dungeon-route-plan-status" class="mt-2 font-serif text-2xl text-lime-100">
                {route_plan_status(@state.route_plan)}
              </p>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                {route_plan_description(@state.route_plan)}
              </p>
            </article>
          </section>

          <section
            :if={@state.expedition && is_nil(@state.run)}
            id="dungeon-entry"
            class="rounded-2xl border border-amber-400/25 bg-amber-950/20 p-6"
          >
            <h2 class="font-serif text-2xl text-amber-100">Врата</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              <%= if @state.entry_dungeon do %>
                {@state.entry_dungeon.name} ждёт у текущей точки экспедиции. Вход создаёт настоящий маршрут и содержимое первого узла.
              <% else %>
                Экспедиция должна собраться у активного входа в Подземелье.
              <% end %>
            </p>
            <button
              :if={@state.can_enter?}
              id="dungeon-enter"
              type="button"
              phx-click="enter"
              class="mt-4 rounded-lg bg-amber-300 px-4 py-3 text-sm font-semibold text-stone-950 hover:bg-amber-200"
            >
              Войти в Подземелье
            </button>
            <p
              :if={@state.entry_dungeon && not @state.can_enter?}
              id="dungeon-entry-waiting"
              class="mt-4 text-sm text-stone-400"
            >
              Вход открывает лидер отряда.
            </p>
          </section>

          <section :if={@state.run} id="dungeon-run" class="space-y-5">
            <article
              id="dungeon-current-node"
              class="rounded-2xl border border-amber-400/25 bg-stone-900/85 p-6 shadow-xl"
            >
              <p class="text-xs uppercase tracking-[0.22em] text-amber-300/75">текущий узел</p>
              <h2 class="mt-2 font-serif text-3xl text-amber-100">{@state.current_node.name}</h2>
              <p class="mt-2 text-sm text-stone-400">
                {node_kind_label(@state.current_node.kind)} · шагов в походе: {@state.run.steps_taken}
              </p>

              <div
                :if={@state.current_encounter}
                id="dungeon-encounter"
                class="mt-5 rounded-xl border border-rose-400/25 bg-rose-950/20 p-4"
              >
                <p class="text-xs uppercase tracking-[0.18em] text-rose-200/70">встреча</p>
                <h3 class="mt-1 font-serif text-xl text-rose-100">
                  {encounter_label(@state.current_encounter)}
                </h3>
                <p class="mt-1 text-sm text-stone-300">
                  Угроза: {@state.current_encounter.threat_level} · {encounter_status(
                    @state.current_encounter.status
                  )}
                </p>
                <div class="mt-4 flex flex-wrap gap-2">
                  <button
                    :if={@state.can_start_combat?}
                    id="dungeon-start-combat"
                    type="button"
                    phx-click="start_combat"
                    class="rounded bg-rose-300 px-3 py-2 text-sm font-semibold text-stone-950 hover:bg-rose-200"
                  >
                    Начать бой
                  </button>
                  <button
                    :if={@state.can_avoid_encounter?}
                    id="dungeon-avoid-encounter"
                    type="button"
                    phx-click="avoid"
                    class="rounded border border-rose-300/50 px-3 py-2 text-sm text-rose-100"
                  >
                    Обойти встречу
                  </button>
                  <.link
                    :if={@state.active_combat && @state.active_combat.status != :finished}
                    id="dungeon-open-combat"
                    navigate={~p"/combat/#{@state.active_combat.id}"}
                    class="rounded bg-rose-300 px-3 py-2 text-sm font-semibold text-stone-950"
                  >
                    Вернуться к бою
                  </.link>
                  <button
                    :if={@state.active_combat && @state.active_combat.status == :finished}
                    id="dungeon-sync-combat"
                    type="button"
                    phx-click="sync_combat"
                    class="rounded bg-amber-300 px-3 py-2 text-sm font-semibold text-stone-950"
                  >
                    Применить итог боя
                  </button>
                </div>
              </div>

              <div
                :if={@state.available_resources != []}
                id="dungeon-resources"
                class="mt-5 rounded-xl border border-emerald-400/20 bg-emerald-950/15 p-4"
              >
                <h3 class="font-serif text-xl text-emerald-100">Ресурсы узла</h3>
                <p id="dungeon-scavenging-time" class="mt-1 text-sm text-emerald-100/75">
                  Осмотр каждого ресурса занимает 1 игровой день и даёт до 3 опыта каждому участнику отряда.
                </p>
                <article
                  :for={resource <- @state.available_resources}
                  id={"dungeon-resource-#{resource.id}"}
                  class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 p-3 text-sm"
                >
                  <span>{resource_label(resource)} · осталось {resource.quantity_remaining}</span>
                  <button
                    id={"dungeon-harvest-#{resource.id}"}
                    type="button"
                    phx-click="harvest"
                    phx-value-resource-id={resource.id}
                    class="rounded border border-emerald-300/50 px-3 py-2 text-emerald-100"
                  >
                    Собрать 1 · 1 игровой день
                  </button>
                </article>
              </div>

              <div
                :if={@state.available_loot != []}
                id="dungeon-loot"
                class="mt-5 rounded-xl border border-violet-400/25 bg-violet-950/20 p-4"
              >
                <h3 class="font-serif text-xl text-violet-100">Добыча</h3>
                <article
                  :for={loot <- @state.available_loot}
                  id={"dungeon-loot-#{loot.id}"}
                  class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 p-3 text-sm"
                >
                  <span>{loot_label(loot)} · ×{loot.amount}</span>
                  <button
                    id={"dungeon-claim-#{loot.id}"}
                    type="button"
                    phx-click="claim_loot"
                    phx-value-loot-drop-id={loot.id}
                    class="rounded border border-violet-300/50 px-3 py-2 text-violet-100"
                  >
                    Взять
                  </button>
                </article>
              </div>

              <div
                id="dungeon-return-ritual-readiness"
                class="mt-5 rounded-xl border border-amber-300/20 bg-amber-950/15 p-4"
              >
                <p class="text-xs uppercase tracking-[0.18em] text-amber-200/75">
                  ритуал возвращения
                </p>
                <%= cond do %>
                  <% not @state.return_ritual.wizardry_specialist? -> %>
                    <p class="mt-1 text-sm leading-6 text-stone-300">
                      Нужна активная специализация волшебника.
                    </p>
                  <% not @state.return_ritual.active_grimoire? -> %>
                    <p class="mt-1 text-sm leading-6 text-stone-300">
                      Нужен активный гримуар с подготовленной формулой возвращения.
                    </p>
                  <% @state.return_ritual.prepared? -> %>
                    <p
                      id="dungeon-return-ritual-prepared"
                      class="mt-1 text-sm leading-6 text-amber-100"
                    >
                      Подготовлена формула: {@state.return_ritual.prepared_spell_name}.
                    </p>
                  <% true -> %>
                    <p class="mt-1 text-sm leading-6 text-stone-300">
                      В активном гримуаре нет подготовленного Ритуала возвращения.
                    </p>
                <% end %>
              </div>

              <div class="mt-5 flex flex-wrap gap-2">
                <button
                  :if={@state.can_extract?}
                  id="dungeon-extract"
                  type="button"
                  phx-click="extract"
                  class="rounded bg-emerald-300 px-3 py-2 text-sm font-semibold text-stone-950"
                >
                  Подняться к Башне
                </button>
                <button
                  :if={@state.can_return_ritual?}
                  id="dungeon-return-ritual"
                  type="button"
                  phx-click="return_ritual"
                  class="rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
                >
                  Начать ритуал возвращения
                </button>
                <p
                  :if={@state.active_extraction}
                  id="dungeon-active-extraction"
                  class="rounded border border-sky-300/30 px-3 py-2 text-sm text-sky-100"
                >
                  Ритуал активен до {format_time(@state.active_extraction.completes_at)}.
                </p>
              </div>
            </article>

            <section
              id="dungeon-map"
              class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
            >
              <div class="flex flex-wrap items-end justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.2em] text-stone-500">разведанная карта</p>
                  <h2 class="mt-1 font-serif text-2xl text-stone-100">Соседние проходы</h2>
                </div>
                <span class="text-sm text-stone-400">
                  Неизведанное открывается только у текущего узла.
                </span>
              </div>
              <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                <article
                  :for={row <- @state.nodes}
                  id={"dungeon-node-#{row.node.id}"}
                  class={node_card_class(row)}
                >
                  <p class="text-xs uppercase tracking-[0.16em] text-stone-500">
                    {node_kind_label(row.node.kind)}
                  </p>
                  <h3 class="mt-1 font-serif text-lg text-stone-100">{row.node.name}</h3>
                  <p class="mt-1 text-xs text-stone-400">{node_progress_label(row)}</p>
                  <button
                    :if={row.reachable?}
                    id={"dungeon-move-#{row.node.id}"}
                    type="button"
                    phx-click="move"
                    phx-value-node-id={row.node.id}
                    class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
                  >
                    Перейти
                  </button>
                </article>
              </div>
            </section>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_dungeon(socket) do
    case Play.dungeon_state(socket.assigns.current_scope.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_state(state)
      {:error, _reason} -> push_navigate(socket, to: ~p"/play")
    end
  end

  defp assign_state(socket, state),
    do:
      socket
      |> assign(:character, state.character)
      |> assign(:atmosphere, state.atmosphere)
      |> assign(:state, state)
      |> assign(:error, nil)

  defp dungeon_title(%{run: nil, entry_dungeon: nil}), do: "Подземелье недоступно"
  defp dungeon_title(%{run: nil, entry_dungeon: dungeon}), do: dungeon.name
  defp dungeon_title(%{dungeon: dungeon}), do: dungeon.name

  defp dungeon_subtitle(%{run: nil}),
    do: "Соберите готовый отряд у входа, чтобы создать настоящую экспедицию."

  defp dungeon_subtitle(%{current_node: node}),
    do: "Маршрут, бой, находки и выход сохраняются в состоянии похода: #{node.name}."

  defp run_status(nil), do: "у врат"
  defp run_status(_run), do: "в глубине"
  defp route_plan_status(%{"status" => "available"}), do: "план готов"
  defp route_plan_status(%{"status" => "consumed"}), do: "план применён"
  defp route_plan_status(_route_plan), do: "план записан"

  defp route_plan_description(%{"status" => "available", "xp_bonus_bps" => bonus_bps}) do
    "Первый выигранный бой в этом походе получит +#{div(bonus_bps, 100)}% XP для отряда."
  end

  defp route_plan_description(%{"status" => "consumed", "xp_awarded" => xp_awarded}) do
    "План уже сработал и добавил #{xp_awarded} XP в общий итог первой победы."
  end

  defp route_plan_description(_route_plan), do: "Маршрутная заметка привязана к этому походу."

  defp node_kind_label(:entrance), do: "вход"
  defp node_kind_label(:room), do: "зал"
  defp node_kind_label(:rest), do: "привал"
  defp node_kind_label(:hazard), do: "аномалия"
  defp node_kind_label(:boss), do: "логово"
  defp node_kind_label(:stairs_up), do: "подъём"
  defp node_kind_label(:stairs_down), do: "спуск"
  defp node_kind_label(:exit), do: "выход"
  defp node_kind_label(_kind), do: "узел"

  defp encounter_label(encounter),
    do: String.capitalize(String.replace(encounter.encounter_kind, "_", " "))

  defp encounter_status(:pending), do: "ожидает решения"
  defp encounter_status(:active), do: "бой идёт"
  defp encounter_status(:cleared), do: "побеждена"
  defp encounter_status(:avoided), do: "обойдена"
  defp encounter_status(:failed), do: "провалена"

  defp resource_label(resource),
    do: (resource.item_template && resource.item_template.name) || resource.resource_code

  defp loot_label(%{reward_kind: :currency}), do: "Монеты"
  defp loot_label(loot), do: (loot.item_template && loot.item_template.name) || "Трофей"

  defp loot_policy_label("leader"), do: "Решает лидер"
  defp loot_policy_label("free_for_all"), do: "Первый взял"
  defp loot_policy_label(_policy), do: "По кругу"

  defp format_time(nil), do: "неизвестного часа"
  defp format_time(datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp node_card_class(%{current?: true}),
    do: "rounded-xl border border-amber-300/60 bg-amber-950/25 p-4"

  defp node_card_class(%{reachable?: true}),
    do: "rounded-xl border border-amber-300/25 bg-stone-950/60 p-4"

  defp node_card_class(_row), do: "rounded-xl border border-stone-700 bg-stone-950/40 p-4"

  defp node_progress_label(%{current?: true}), do: "вы здесь"
  defp node_progress_label(%{reachable?: true}), do: "доступный проход"
  defp node_progress_label(%{node_state: nil}), do: "виден издалека"

  defp node_progress_label(%{node_state: state}),
    do: "#{state.status} · встреча: #{encounter_status(state.encounter_status)}"

  defp error_message(:not_party_leader), do: "Вход в Подземелье открывает лидер отряда."

  defp error_message(:dungeon_entry_unavailable),
    do: "Экспедиция должна находиться у активного входа в Подземелье."

  defp error_message(:dungeon_node_unavailable), do: "Этот проход сейчас недоступен."
  defp error_message(:dungeon_encounter_unavailable), do: "Текущая встреча больше не доступна."
  defp error_message(:dungeon_combat_not_finished), do: "Итог боя пока не готов к применению."
  defp error_message(:dungeon_loot_unavailable), do: "Этот трофей нельзя взять отсюда."
  defp error_message(:dungeon_resource_unavailable), do: "Этот ресурс больше нельзя собрать."

  defp error_message(:dungeon_extraction_unavailable),
    do: "Отступление возможно только после решения текущей встречи."

  defp error_message(:return_ritual_unavailable),
    do: "Ритуал может начать участник с подготовкой волшебника."

  defp error_message(_reason),
    do: "Действие Подземелья не выполнено: состояние похода изменилось."
end
