defmodule MMGOWeb.CombatLive do
  @moduledoc """
  Scoped, server-rendered combat surface.

  The browser supplies only a proposed action selection. `MMGO.Play` checks
  that the current scoped character belongs to the requested combat, while the
  combat context locks the exact participant, turn, spell, item, and target
  before sealing anything. Resolution is performed by the durable turn worker,
  never by a client timer or a scripted UI sequence.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @refresh_interval 1_000

  @impl true
  def mount(params, _session, socket) do
    character = socket.assigns.current_scope.character

    case load_combat_state(character, params["id"]) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(:page_title, "Бой")
         |> assign(:action_error, nil)
         |> assign_combat_state(state)
         |> schedule_refresh()}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, combat_error_message(reason))
         |> push_navigate(to: ~p"/map")}
    end
  end

  @impl true
  def handle_event("submit_action", %{"combat_action" => attrs}, socket) when is_map(attrs) do
    state = socket.assigns.combat_state

    case Play.submit_combat_action(socket.assigns.current_scope.character, state.combat.id, attrs) do
      {:ok, updated_state} ->
        {:noreply,
         socket
         |> assign_combat_state(updated_state)
         |> assign(:action_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:action_form, action_form(state, attrs))
         |> assign(:action_error, combat_error_message(reason))}
    end
  end

  def handle_event("submit_action", _params, socket) do
    {:noreply, assign(socket, :action_error, combat_error_message(:invalid_action))}
  end

  @impl true
  def handle_event("flee", _params, socket) do
    state = socket.assigns.combat_state

    case Play.flee_combat(socket.assigns.current_scope.character, state.combat.id) do
      {:ok, updated_state} ->
        {:noreply,
         socket
         |> assign_combat_state(updated_state)
         |> assign(:action_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :action_error, combat_error_message(reason))}
    end
  end

  @impl true
  def handle_info(:refresh_combat, socket) do
    state = socket.assigns.combat_state

    case Play.combat_state(socket.assigns.current_scope.character, state.combat.id) do
      {:ok, updated_state} ->
        {:noreply,
         socket
         |> assign_combat_state(updated_state, preserve_form?: true)
         |> schedule_refresh()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, combat_error_message(reason))
         |> push_navigate(to: ~p"/map")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main
        id="combat-screen"
        class="min-h-full bg-stone-950 px-4 py-6 text-stone-100 sm:px-6 sm:py-9"
      >
        <div class="mx-auto w-full max-w-6xl space-y-6">
          <header class="overflow-hidden rounded-[2rem] border border-amber-400/20 bg-gradient-to-br from-stone-900 via-stone-950 to-amber-950/30 px-6 py-7 shadow-2xl sm:px-8">
            <div class="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
              <div class="max-w-2xl">
                <p class="text-xs font-semibold uppercase tracking-[0.28em] text-amber-300/80">
                  {combat_kind_label(@combat_state.combat.kind)}
                </p>
                <h1 class="mt-2 font-serif text-3xl font-semibold tracking-tight text-amber-100 sm:text-4xl">
                  Круг решения
                </h1>
                <p class="mt-3 text-sm leading-6 text-stone-300">
                  Ход фиксируется на стороне мира. После печати действие нельзя подменить
                  браузером, а исход появится после единого разрешения всех сторон.
                </p>
              </div>

              <div class="flex flex-wrap items-center gap-3">
                <span
                  id="combat-status"
                  class="rounded-full border border-amber-300/25 bg-amber-300/10 px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.16em] text-amber-200"
                >
                  {combat_status_label(@combat_state.combat.status)}
                </span>
                <.link
                  id="combat-back-to-map"
                  navigate={~p"/map"}
                  class="inline-flex min-h-11 items-center justify-center rounded-xl border border-stone-600 px-4 py-2 text-sm font-semibold text-stone-100 transition hover:border-amber-200 hover:bg-amber-100/10"
                >
                  <.icon name="hero-map" class="mr-2 size-4" /> Карта мира
                </.link>
              </div>
            </div>
          </header>

          <section
            :if={@combat_state.turn}
            id={"combat-turn-#{@combat_state.turn.id}"}
            class="rounded-[1.75rem] border border-stone-700/80 bg-stone-900/80 p-5 shadow-xl sm:p-6"
          >
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">
                  Текущий ход
                </p>
                <h2 class="mt-1 font-serif text-2xl text-stone-50">
                  Ход {@combat_state.turn.number}
                </h2>
              </div>
              <div class="rounded-2xl border border-amber-500/20 bg-stone-950/70 px-4 py-3 text-right">
                <p class="text-xs font-semibold uppercase tracking-[0.16em] text-stone-500">
                  Предел хода
                </p>
                <p id="combat-deadline" class="mt-1 font-mono text-sm text-amber-200">
                  {deadline_label(@combat_state.deadline_at, @combat_state.resolving?)}
                </p>
              </div>
            </div>

            <div class="mt-5 grid gap-4 md:grid-cols-2">
              <article
                :for={side <- @combat_state.sides}
                id={"combat-side-#{side.id}"}
                class="rounded-2xl border border-stone-700 bg-stone-950/55 p-4"
              >
                <div class="flex items-center justify-between gap-3">
                  <h3 class="font-serif text-xl text-stone-100">{side.label}</h3>
                  <span class="font-mono text-sm text-amber-200">
                    {side.shared_hp} / {side.max_shared_hp}
                  </span>
                </div>
                <div class="mt-3 h-2 overflow-hidden rounded-full bg-stone-800">
                  <div
                    class="h-full rounded-full bg-gradient-to-r from-amber-600 to-amber-300 transition-[width] duration-500"
                    style={"width:#{hp_percent(side.shared_hp, side.max_shared_hp)}%"}
                  >
                  </div>
                </div>
                <ul class="mt-4 space-y-2 text-sm text-stone-300">
                  <li
                    :for={participant <- participants_on_side(@combat_state, side.id)}
                    id={"combat-target-#{participant.id}"}
                    class="flex items-center justify-between gap-3 rounded-xl bg-stone-900/70 px-3 py-2"
                  >
                    <span>{participant.display_name}</span>
                    <span class={participant_status_class(participant.status)}>
                      {participant_status_label(participant.status)}
                    </span>
                  </li>
                </ul>
              </article>
            </div>
          </section>

          <section
            :if={@combat_state.turn && @combat_state.turn.narration}
            id={"combat-narration-#{@combat_state.turn.id}"}
            class="rounded-[1.75rem] border border-indigo-300/20 bg-indigo-950/30 px-5 py-5 shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-indigo-200/75">
              Последнее разрешение
            </p>
            <p class="mt-2 font-serif text-lg leading-7 text-indigo-50">
              {@combat_state.turn.narration}
            </p>
          </section>

          <section
            :if={@combat_state.spectator?}
            id="combat-spectator"
            class="rounded-[1.75rem] border border-violet-300/20 bg-violet-950/25 p-6 shadow-lg"
          >
            <div class="flex items-start gap-4">
              <span class="mt-0.5 inline-flex size-10 shrink-0 items-center justify-center rounded-full border border-violet-200/25 bg-violet-200/10 text-violet-100">
                <.icon name="hero-eye" class="size-5" />
              </span>
              <div>
                <h2 class="font-serif text-2xl text-violet-50">Вы наблюдаете за боем</h2>
                <p class="mt-2 text-sm leading-6 text-violet-100/75">
                  Этот круг проходит у вас на глазах. Хроника и итог доступны, но выбирать
                  действия могут только его участники.
                </p>
              </div>
            </div>
          </section>

          <section
            :if={@combat_state.combat.status == :finished}
            id="combat-outcome"
            class="rounded-[1.75rem] border border-amber-300/30 bg-amber-950/25 p-6 text-center shadow-xl"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.22em] text-amber-200/80">
              Бой завершён
            </p>
            <h2 class="mt-2 font-serif text-3xl text-amber-100">
              Победа стороны {winner_label(@combat_state)}
            </h2>
            <p class="mx-auto mt-3 max-w-2xl text-sm leading-6 text-stone-300">
              Итог сохранён. Связанные последствия боя будут применены его доменным контекстом.
            </p>
            <.link
              :if={dungeon_combat?(@combat_state.combat)}
              id="combat-outcome-dungeon"
              navigate={~p"/dungeon"}
              class="mt-5 inline-flex min-h-11 items-center justify-center rounded-xl bg-amber-300 px-5 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-200"
            >
              Вернуться в экспедицию
            </.link>
            <.link
              :if={not dungeon_combat?(@combat_state.combat)}
              id="combat-outcome-map"
              navigate={~p"/map"}
              class="mt-5 inline-flex min-h-11 items-center justify-center rounded-xl bg-amber-300 px-5 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-200"
            >
              Вернуться к карте
            </.link>
          </section>

          <section
            :if={@combat_state.resolving? and @combat_state.combat.status != :finished}
            id="combat-resolving"
            class="rounded-[1.75rem] border border-sky-300/20 bg-sky-950/25 p-6 shadow-lg"
          >
            <div class="flex items-start gap-4">
              <span class="mt-0.5 inline-flex size-10 shrink-0 items-center justify-center rounded-full border border-sky-200/25 bg-sky-200/10 text-sky-100">
                <.icon name="hero-arrow-path" class="size-5 animate-spin" />
              </span>
              <div>
                <h2 class="font-serif text-2xl text-sky-50">Печати собраны</h2>
                <p class="mt-2 text-sm leading-6 text-sky-100/75">
                  Сервер разрешает ход по сохранённым снимкам действий. Экран обновится, когда
                  результат будет записан.
                </p>
              </div>
            </div>
          </section>

          <section
            :if={@combat_state.awaiting? and not @combat_state.resolving?}
            id="combat-awaiting"
            class="rounded-[1.75rem] border border-emerald-300/20 bg-emerald-950/25 p-6 shadow-lg"
          >
            <div class="flex items-start gap-4">
              <span class="mt-0.5 inline-flex size-10 shrink-0 items-center justify-center rounded-full border border-emerald-200/25 bg-emerald-200/10 text-emerald-100">
                <.icon name="hero-check" class="size-5" />
              </span>
              <div>
                <h2 class="font-serif text-2xl text-emerald-50">Ваше действие запечатано</h2>
                <p class="mt-2 text-sm leading-6 text-emerald-100/75">
                  Ожидаем остальные стороны или окончание отсчёта. Для отсутствующих участников
                  система запишет ожидание, затем разрешит этот же ход.
                </p>
              </div>
            </div>
          </section>

          <section
            :if={@combat_state.action_open? and is_nil(@combat_state.own_action)}
            class="rounded-[1.75rem] border border-amber-300/25 bg-[#ece0bd] p-5 text-stone-950 shadow-xl sm:p-7"
          >
            <div class="mb-6 border-b border-amber-950/15 pb-5">
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-amber-900/70">
                Ваше решение
              </p>
              <h2 class="mt-2 font-serif text-2xl font-semibold">Выберите и запечатайте действие</h2>
              <p class="mt-2 max-w-3xl text-sm leading-6 text-stone-700">
                Заклинание должно быть в активном гримуаре, предмет — в вашем инвентаре. Цели и
                цена сверяются ещё раз в момент печати.
              </p>
              <p
                :if={channeling?(@combat_state.participant)}
                id="combat-channeling-hint"
                class="mt-3 rounded-xl border border-violet-900/20 bg-violet-950/8 px-4 py-3 text-sm leading-6 text-violet-950"
              >
                Вы поддерживаете эффект. Выберите «Прервать канал», чтобы закончить его
                добровольно; полученный урон прервёт канал автоматически.
              </p>
            </div>

            <.form
              for={@action_form}
              id="combat-action-form"
              phx-submit="submit_action"
              class="space-y-1"
            >
              <.input
                field={@action_form[:action_type]}
                id="combat-action-kind"
                type="select"
                label="Тип действия"
                options={action_type_options(@combat_state.participant)}
                required
              />

              <div class="grid gap-x-5 md:grid-cols-2">
                <div>
                  <.input
                    field={@action_form[:spell_id]}
                    id="combat-cast-spell"
                    type="select"
                    label="Заклинание"
                    options={spell_options(@combat_state.prepared_spells)}
                    prompt="Выберите запись гримуара"
                  />
                  <.input
                    field={@action_form[:incantation]}
                    id="combat-incantation"
                    type="text"
                    label="Формула"
                    autocomplete="off"
                  />
                </div>
                <div>
                  <.input
                    field={@action_form[:inventory_item_id]}
                    id="combat-tool-item"
                    type="select"
                    label="Предмет"
                    options={item_options(@combat_state.items)}
                    prompt="Выберите предмет"
                  />
                  <.input
                    field={@action_form[:tool_action]}
                    id="combat-tool-action"
                    type="select"
                    label="Приём предмета"
                    options={item_action_options(@combat_state.items)}
                    prompt="Выберите приём"
                  />
                </div>
              </div>

              <div class="grid gap-x-5 md:grid-cols-2">
                <.input
                  field={@action_form[:target_side]}
                  id="combat-target-side"
                  type="select"
                  label="Сторона цели"
                  options={target_side_options(@combat_state)}
                />
                <.input
                  field={@action_form[:target_participant_id]}
                  id="combat-target-selector"
                  type="select"
                  label="Участник цели"
                  options={target_options(@combat_state)}
                />
              </div>

              <p
                :if={@action_error}
                id="combat-action-error"
                class="rounded-xl border border-rose-500/30 bg-rose-950/10 px-4 py-3 text-sm leading-6 text-rose-800"
              >
                {@action_error}
              </p>

              <button
                id="combat-seal"
                type="submit"
                phx-disable-with="Печать накладывается…"
                class="mt-4 inline-flex min-h-12 w-full items-center justify-center rounded-xl bg-amber-800 px-5 py-3 text-sm font-semibold text-amber-50 shadow-sm transition hover:-translate-y-0.5 hover:bg-amber-900 focus:outline-none focus:ring-2 focus:ring-amber-800 focus:ring-offset-2 focus:ring-offset-[#ece0bd]"
              >
                <.icon name="hero-lock-closed" class="mr-2 size-5" /> Запечатать действие
              </button>

              <button
                :if={@combat_state.can_flee?}
                id="combat-flee"
                type="button"
                phx-click="flee"
                class="mt-3 inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-rose-900/35 px-5 py-3 text-sm font-semibold text-rose-900 transition hover:border-rose-900 hover:bg-rose-950/10"
              >
                <.icon name="hero-arrow-uturn-left" class="mr-2 size-5" />
                Отступить и отдать этот круг
              </button>
            </.form>
          </section>

          <section
            id="combat-events"
            class="rounded-[1.75rem] border border-stone-700/80 bg-stone-900/80 p-5 shadow-lg sm:p-6"
          >
            <div class="flex items-end justify-between gap-4">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">Хроника</p>
                <h2 class="mt-1 font-serif text-2xl text-stone-100">Последние события</h2>
              </div>
              <span class="text-sm text-stone-500">
                {@combat_state.submitted_action_count} печатей в ходе
              </span>
            </div>

            <p
              :if={@combat_state.events == []}
              id="combat-events-empty"
              class="mt-4 text-sm text-stone-500"
            >
              Хроника появится после первого разрешённого хода.
            </p>
            <ol :if={@combat_state.events != []} class="mt-4 space-y-2">
              <li
                :for={event <- @combat_state.events}
                id={"combat-event-#{event.id}"}
                class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl bg-stone-950/70 px-4 py-3 text-sm"
              >
                <span class="font-mono text-amber-300">Ход {event.turn_number}</span>
                <span class="text-stone-600">·</span>
                <span class="text-stone-300">{event_label(event.event_type)}</span>
              </li>
            </ol>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_combat_state(character, combat_id) when is_binary(combat_id),
    do: Play.combat_state(character, combat_id)

  defp load_combat_state(character, _combat_id), do: Play.active_combat_state(character)

  defp assign_combat_state(socket, state, opts \\ []) do
    preserve_form? = Keyword.get(opts, :preserve_form?, false)

    socket =
      socket
      |> assign(:combat_state, state)
      |> assign(:character, state.character)
      |> assign(:atmosphere, state.atmosphere)

    if preserve_form? do
      socket
    else
      form = if state.spectator?, do: to_form(%{}, as: :combat_action), else: action_form(state)
      assign(socket, :action_form, form)
    end
  end

  defp schedule_refresh(socket) do
    if connected?(socket) and active_combat?(socket.assigns.combat_state.combat) do
      Process.send_after(self(), :refresh_combat, @refresh_interval)
    end

    socket
  end

  defp active_combat?(combat), do: combat.status in [:active_turn, :locked, :resolving]

  defp action_form(state, attrs \\ nil) do
    params = attrs || default_action_params(state)
    to_form(params, as: :combat_action)
  end

  defp default_action_params(state) do
    spell = List.first(state.prepared_spells)
    item = List.first(state.items)
    item_action = item && List.first(item.actions)
    target = List.first(opponents(state))

    action_type =
      if channeling?(state.participant),
        do: "wait",
        else: if(spell, do: "cast_spell", else: "wait")

    %{
      "action_type" => action_type,
      "spell_id" => spell && spell.id,
      "incantation" => spell && spell.formula,
      "inventory_item_id" => item && item.id,
      "tool_action" => item_action && item_action.key,
      "target_side" => target && target.side,
      "target_participant_id" => target && target.id
    }
  end

  defp opponents(state) do
    Enum.filter(
      state.combat.participants,
      &(&1.side != state.participant.side and &1.status == :ready)
    )
  end

  defp participants_on_side(state, side_id) do
    state.combat.participants
    |> Enum.filter(&(&1.side == side_id))
    |> Enum.sort_by(& &1.position)
  end

  defp action_type_options(participant) do
    [
      {"Заклинание", "cast_spell"},
      {"Предмет", "use_item"},
      {if(channeling?(participant), do: "Прервать канал", else: "Выждать"), "wait"}
    ]
  end

  defp channeling?(%{active_states: active_states}) do
    Enum.any?(List.wrap(active_states), &(Map.get(&1, "state") == "channeling"))
  end

  defp channeling?(_participant), do: false

  defp spell_options(spells),
    do: Enum.map(spells, &{"#{&1.name} · усталость #{&1.fatigue_cost}", &1.id})

  defp item_options(items),
    do: Enum.map(items, &{"#{&1.name} · доступно #{&1.available_quantity}", &1.id})

  defp item_action_options(items) do
    Enum.flat_map(items, fn item ->
      Enum.map(item.actions, fn action ->
        {"#{item.name} · #{item_action_label(action.kind)}", action.key}
      end)
    end)
  end

  defp target_side_options(state) do
    state.combat.participants
    |> Enum.map(& &1.side)
    |> Enum.uniq()
    |> Enum.map(fn side_id -> {side_label(state, side_id), side_id} end)
  end

  defp target_options(state) do
    state.combat.participants
    |> Enum.filter(&(&1.status == :ready))
    |> Enum.sort_by(&{&1.side, &1.position})
    |> Enum.map(&{"#{&1.display_name} · #{side_label(state, &1.side)}", &1.id})
  end

  defp side_label(state, side_id) do
    state.sides
    |> Enum.find(&(&1.id == side_id))
    |> case do
      nil -> side_id
      side -> side.label
    end
  end

  defp hp_percent(_hp, max_hp) when max_hp <= 0, do: 0

  defp hp_percent(hp, max_hp) do
    hp
    |> Kernel./(max_hp)
    |> Kernel.*(100)
    |> min(100)
    |> max(0)
    |> round()
  end

  defp deadline_label(_deadline_at, true), do: "ход разрешается"
  defp deadline_label(nil, _resolving?), do: "время уточняется"

  defp deadline_label(deadline_at, _resolving?),
    do: Calendar.strftime(deadline_at, "%H:%M:%S UTC")

  defp combat_kind_label(:duel), do: "Дуэль"
  defp combat_kind_label(:dungeon_encounter), do: "Схватка в подземелье"
  defp combat_kind_label(:overworld_encounter), do: "Столкновение в пути"
  defp combat_kind_label(kind), do: kind |> to_string() |> String.capitalize()

  defp dungeon_combat?(%{kind: :dungeon_encounter}), do: true
  defp dungeon_combat?(_combat), do: false

  defp combat_status_label(:active_turn), do: "ход открыт"
  defp combat_status_label(:locked), do: "печати собраны"
  defp combat_status_label(:resolving), do: "разрешение"
  defp combat_status_label(:finished), do: "завершён"
  defp combat_status_label(status), do: status |> to_string() |> String.capitalize()

  defp participant_status_label(:ready), do: "готов"
  defp participant_status_label(:defeated), do: "повержен"
  defp participant_status_label(:fled), do: "отступил"
  defp participant_status_label(status), do: status |> to_string() |> String.capitalize()

  defp participant_status_class(:ready), do: "text-xs font-semibold text-emerald-300"
  defp participant_status_class(:defeated), do: "text-xs font-semibold text-rose-300"
  defp participant_status_class(:fled), do: "text-xs font-semibold text-stone-500"
  defp participant_status_class(_status), do: "text-xs font-semibold text-stone-400"

  defp winner_label(state) do
    case Enum.find(state.sides, &(&1.id == state.combat.winner_side)) do
      nil -> "не определена"
      side -> side.label
    end
  end

  defp item_action_label(:strike), do: "удар"
  defp item_action_label(:sweep), do: "взмах"
  defp item_action_label(:raise_shield), do: "щит"
  defp item_action_label(:throw), do: "бросок"
  defp item_action_label(:deploy), do: "развернуть"
  defp item_action_label(:repair), do: "починка"
  defp item_action_label(kind), do: kind |> to_string() |> String.capitalize()

  defp event_label("spell_cast"), do: "заклинание сработало"
  defp event_label("tool_action"), do: "предмет применён"
  defp event_label("action_blocked"), do: "действие сорвалось"
  defp event_label("state_tick"), do: "состояние изменило поле боя"
  defp event_label("environment_hazard_tick"), do: "опасная среда наносит урон"
  defp event_label("channeling_stopped"), do: "канал добровольно прерван"
  defp event_label("wait"), do: "сторона выжидает"
  defp event_label("fled"), do: "участник отступил"
  defp event_label(event_type), do: event_type |> to_string() |> String.replace("_", " ")

  defp combat_error_message(:no_active_combat), do: "У вас нет активного боя."
  defp combat_error_message(:combat_not_found), do: "Этот бой вам недоступен."
  defp combat_error_message(:turn_not_open), do: "Этот ход уже запечатан или завершён."
  defp combat_error_message(:turn_locked), do: "Печати уже собраны; действие нельзя изменить."
  defp combat_error_message(:turn_deadline_elapsed), do: "Время хода истекло."
  defp combat_error_message(:flee_unavailable), do: "Слишком тяжёлый груз не даёт отступить."
  defp combat_error_message(:spectator), do: "Наблюдатель не может запечатывать действия."

  defp combat_error_message(:spell_not_prepared),
    do: "Это заклинание не внесено в боевой гримуар."

  defp combat_error_message(:spell_not_owned), do: "Нельзя использовать чужое заклинание."
  defp combat_error_message(:invalid_target), do: "Выберите допустимую цель."
  defp combat_error_message(:item_not_owned), do: "Этот предмет вам не принадлежит."
  defp combat_error_message(:item_unavailable), do: "Предмет уже недоступен для этого хода."
  defp combat_error_message(:invalid_item_action), do: "Этот приём недоступен предмету."

  defp combat_error_message(:invalid_incantation),
    do: "Формула должна состоять из допустимых слов."

  defp combat_error_message(:invalid_action), do: "Не удалось прочитать действие."
  defp combat_error_message(_reason), do: "Мир отклонил это действие. Попробуйте обновить бой."
end
