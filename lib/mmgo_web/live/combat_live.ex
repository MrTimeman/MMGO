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
  alias MMGO.Spells.Incantation

  @refresh_interval 1_000
  @incantation_slot_order ~w(actio forma vis tempus mutatio pretium)

  @impl true
  def mount(params, _session, socket) do
    character = socket.assigns.current_scope.character

    case load_combat_state(character, params["id"]) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(:page_title, "Бой")
         |> assign(:action_error, nil)
         |> assign(:flee_confirm?, false)
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
  def handle_event("change_action", %{"combat_action" => attrs}, socket) when is_map(attrs) do
    {:noreply,
     socket
     |> assign(:action_form, action_form(socket.assigns.combat_state, attrs))
     |> assign(:action_error, nil)}
  end

  @impl true
  def handle_event("flee", _params, socket) do
    {:noreply, assign(socket, :flee_confirm?, true)}
  end

  @impl true
  def handle_event("cancel_flee", _params, socket) do
    {:noreply, assign(socket, :flee_confirm?, false)}
  end

  @impl true
  def handle_event("confirm_flee", _params, socket) do
    state = socket.assigns.combat_state

    case Play.flee_combat(socket.assigns.current_scope.character, state.combat.id) do
      {:ok, updated_state} ->
        {:noreply,
         socket
         |> assign_combat_state(updated_state)
         |> assign(:flee_confirm?, false)
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
    {enemy_side, ally_side} = arena_sides(assigns.combat_state)

    assigns =
      assigns
      |> assign(:enemy_side, enemy_side)
      |> assign(:ally_side, ally_side)
      |> assign(
        :lit_incantation_slots,
        lit_incantation_slots(assigns.action_form, assigns.combat_state.prepared_spells)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      atmosphere={@atmosphere}
    >
      <main
        id="combat-screen"
        class={[
          "cbt-arena",
          "cbt-arena--#{@combat_state.combat.kind}",
          @combat_state.combat.status == :finished && "cbt-arena--over"
        ]}
      >
        <div class="cbt-vignette"></div>

        <header class="cbt-top">
          <div class="cbt-topbar">
            <.link id="combat-back-to-map" navigate={~p"/map"} class="cbt-flee-btn">
              <span aria-hidden="true">‹</span> Карта мира
            </.link>
            <span id="combat-status" class="cbt-status">
              {combat_kind_label(@combat_state.combat.kind)} · {combat_status_label(
                @combat_state.combat.status
              )}
            </span>
          </div>

          <.combat_side_panel
            :if={@enemy_side}
            side={@enemy_side}
            state={@combat_state}
            align="enemy"
          />

          <section
            :if={@combat_state.turn}
            id={"combat-turn-#{@combat_state.turn.id}"}
            class="cbt-turnrow"
          >
            <span class="cbt-turn-line"></span>
            <div class="cbt-turnring">
              <svg viewBox="0 0 44 44" class="cbt-turnring__svg" aria-hidden="true">
                <circle class="cbt-turnring__track" cx="22" cy="22" r="19" />
                <circle
                  class={[
                    "cbt-turnring__sweep",
                    (@combat_state.resolving? || @combat_state.awaiting?) && "is-held"
                  ]}
                  cx="22"
                  cy="22"
                  r="19"
                />
              </svg>
              <span class="cbt-turnring__label">
                <em>ход</em>{@combat_state.turn.number}
              </span>
            </div>
            <div class="cbt-deadline">
              <em>до печати</em>
              <span id="combat-deadline">
                {deadline_label(@combat_state.deadline_at, @combat_state.resolving?)}
              </span>
            </div>
            <span class="cbt-turn-line"></span>
          </section>

          <.combat_side_panel
            :if={@ally_side}
            side={@ally_side}
            state={@combat_state}
            align="ally"
          />
        </header>

        <section class="cbt-log" role="log" aria-live="polite">
          <article class="cbt-turn cbt-turn--prologue">
            <p class="cbt-turn__prologue">
              {combat_opening(@combat_state.combat.kind)}
            </p>
          </article>

          <article
            :if={@combat_state.turn && @combat_state.turn.narration}
            id={"combat-narration-#{@combat_state.turn.id}"}
            class="cbt-turn cbt-turn--focus"
          >
            <div class="cbt-turn__sep">
              <span class="cbt-turn__label">Последнее разрешение</span>
            </div>
            <p class="cbt-turn__para">{@combat_state.turn.narration}</p>
          </article>

          <section :if={@combat_state.spectator?} id="combat-spectator" class="cbt-observer">
            <span class="cbt-observer__glyph"><.icon name="hero-eye" class="size-5" /></span>
            <div>
              <h2>Вы наблюдаете за кругом</h2>
              <p>Хроника открыта, но печать действия принадлежит только участникам.</p>
            </div>
          </section>

          <section
            :if={@combat_state.combat.status == :finished}
            id="combat-outcome"
            class={[
              "cbt-outcome",
              outcome_class(@combat_state) == :defeat && "cbt-outcome--defeat"
            ]}
          >
            <span class="cbt-outcome__seal">
              {if outcome_class(@combat_state) == :defeat, do: "☒", else: "✦"}
            </span>
            <h2 class="cbt-outcome__title">Победа стороны {winner_label(@combat_state)}</h2>
            <p class="cbt-outcome__sub">Исход вписан в хронику мира.</p>
            <.link
              :if={dungeon_combat?(@combat_state.combat)}
              id="combat-outcome-dungeon"
              navigate={~p"/dungeon"}
              class="cbt-outcome__btn"
            >
              Вернуться в экспедицию
            </.link>
            <.link
              :if={not dungeon_combat?(@combat_state.combat)}
              id="combat-outcome-map"
              navigate={~p"/map"}
              class="cbt-outcome__btn"
            >
              Покинуть круг
            </.link>
          </section>

          <section
            :if={@combat_state.resolving? and @combat_state.combat.status != :finished}
            id="combat-resolving"
            class="cbt-seal cbt-seal--state"
          >
            <span class="cbt-seal__wax" aria-hidden="true">
              <span class="cbt-seal__rune">ᛟ</span>
            </span>
            <div class="cbt-seal__copy">
              <h2 class="cbt-seal__title">Печати собраны</h2>
              <p class="cbt-seal__sub">Круг разрешает сохранённые действия…</p>
            </div>
          </section>

          <section
            :if={@combat_state.awaiting? and not @combat_state.resolving?}
            id="combat-awaiting"
            class="cbt-seal cbt-seal--state"
          >
            <span class="cbt-seal__wax" aria-hidden="true">
              <span class="cbt-seal__rune">ᛟ</span>
            </span>
            <div class="cbt-seal__copy">
              <h2 class="cbt-seal__title">Ваше действие запечатано</h2>
              <p class="cbt-seal__sub">Ожидаем остальные стороны или окончание отсчёта.</p>
            </div>
          </section>

          <section
            :if={@combat_state.action_open? and is_nil(@combat_state.own_action)}
            class="cbt-action-ledger"
          >
            <div class="cbt-action-ledger__head">
              <span class="cbt-action-ledger__rune">❧</span>
              <div>
                <p>Ваше решение</p>
                <h2>Начертите действие и наложите печать</h2>
              </div>
            </div>

            <p
              :if={channeling?(@combat_state.participant)}
              id="combat-channeling-hint"
              class="cbt-env"
            >
              Вы поддерживаете эффект. «Прервать канал» закончит его добровольно; полученный
              урон оборвёт канал автоматически.
            </p>

            <.form
              for={@action_form}
              id="combat-action-form"
              phx-change="change_action"
              phx-submit="submit_action"
              class="cbt-action-form"
            >
              <div
                id="combat-incantation-slots"
                class="cbt-slots"
                aria-label="Строение формулы"
              >
                <span
                  :for={{key, mark, title} <- incantation_slots()}
                  class={[
                    "cbt-slot",
                    MapSet.member?(@lit_incantation_slots, key) && "cbt-slot--lit"
                  ]}
                  title={title}
                >
                  {mark}
                </span>
                <span class="cbt-slots__count">{MapSet.size(@lit_incantation_slots)}/6</span>
              </div>

              <fieldset class="cbt-action-case">
                <legend>I · Намерение</legend>
                <.input
                  field={@action_form[:action_type]}
                  id="combat-action-kind"
                  type="select"
                  label="Тип действия"
                  options={action_type_options(@combat_state.participant)}
                  required
                />
              </fieldset>

              <div class="cbt-action-grid">
                <fieldset class="cbt-action-case">
                  <legend>II · Гримуар</legend>
                  <.input
                    field={@action_form[:spell_id]}
                    id="combat-cast-spell"
                    type="select"
                    label="Основа"
                    options={spell_options(@combat_state.prepared_spells)}
                    prompt="Выберите запись"
                  />
                  <.input
                    field={@action_form[:incantation]}
                    id="combat-incantation"
                    type="text"
                    label="Формула"
                    autocomplete="off"
                  />
                </fieldset>

                <fieldset class="cbt-action-case">
                  <legend>III · Инструмент</legend>
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
                    label="Приём"
                    options={item_action_options(@combat_state.items)}
                    prompt="Выберите приём"
                  />
                </fieldset>
              </div>

              <fieldset class="cbt-action-case">
                <legend>IV · Цель</legend>
                <div class="cbt-action-grid">
                  <.input
                    field={@action_form[:target_side]}
                    id="combat-target-side"
                    type="select"
                    label="Сторона"
                    options={target_side_options(@combat_state)}
                  />
                  <.input
                    field={@action_form[:target_participant_id]}
                    id="combat-target-selector"
                    type="select"
                    label="Участник"
                    options={target_options(@combat_state)}
                  />
                </div>
              </fieldset>

              <p :if={@action_error} id="combat-action-error" class="cbt-action-error">
                {@action_error}
              </p>

              <button
                id="combat-seal"
                type="submit"
                phx-disable-with="Печать накладывается…"
                class="cbt-action-submit"
              >
                <span class="cbt-action-submit__wax">ᛟ</span>
                <span>Запечатать действие</span>
              </button>

              <button
                :if={@combat_state.can_flee?}
                id="combat-flee"
                type="button"
                phx-click="flee"
                class="cbt-action-flee"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Отступить и отдать этот круг
              </button>
            </.form>
          </section>

          <section
            :if={@flee_confirm?}
            id="combat-flee-confirmation"
            class="cbt-flee-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="combat-flee-title"
          >
            <h2 id="combat-flee-title" class="cbt-flee-modal__title">Отдать круг противнику?</h2>
            <p class="cbt-flee-modal__body">
              Отступление немедленно запечатает поражение вашей стороны. Отменить его после
              подтверждения нельзя.
            </p>
            <div class="cbt-flee-modal__row">
              <button type="button" phx-click="cancel_flee" class="cbt-flee-modal__stay">
                Остаться в бою
              </button>
              <button
                id="combat-flee-confirm"
                type="button"
                phx-click="confirm_flee"
                class="cbt-flee-modal__go"
              >
                Подтвердить отступление
              </button>
            </div>
          </section>

          <section id="combat-events" class="cbt-chronicle">
            <div class="cbt-turn__sep">
              <span class="cbt-turn__label">Хроника</span>
              <span class="cbt-turn__spoken">
                {@combat_state.submitted_action_count} печатей в ходе
              </span>
            </div>
            <p
              :if={@combat_state.events == []}
              id="combat-events-empty"
              class="cbt-chronicle__empty"
            >
              Пергамент ещё чист. Первая запись появится после разрешённого хода.
            </p>
            <ol :if={@combat_state.events != []} class="cbt-chronicle__list">
              <li
                :for={event <- @combat_state.events}
                id={"combat-event-#{event.id}"}
                class="cbt-chronicle__entry"
              >
                <span>Ход {event.turn_number}</span>
                <strong>{event_label(event.event_type)}</strong>
              </li>
            </ol>
          </section>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :side, :map, required: true
  attr :state, :map, required: true
  attr :align, :string, required: true

  defp combat_side_panel(assigns) do
    ~H"""
    <section id={"combat-side-#{@side.id}"} class={["cbt-side", "cbt-side--#{@align}"]}>
      <div class="cbt-side__head">
        <span class="cbt-side__name">{side_display_label(@side.label)}</span>
        <span class="cbt-side__hpnum">{@side.shared_hp} / {@side.max_shared_hp}</span>
      </div>
      <div class="cbt-hp">
        <div
          class={[
            "cbt-hp__fill",
            combat_hp_class(@side.shared_hp, @side.max_shared_hp)
          ]}
          style={"width: #{hp_percent(@side.shared_hp, @side.max_shared_hp)}%"}
        >
        </div>
      </div>
      <div class="cbt-chips">
        <div
          :for={participant <- participants_on_side(@state, @side.id)}
          id={"combat-target-#{participant.id}"}
          class="cbt-chip"
        >
          <span class="cbt-chip__token">{participant_initial(participant.display_name)}</span>
          <span class="cbt-chip__name">{participant.display_name}</span>
          <span class={[
            "cbt-participant-state",
            "cbt-participant-state--#{participant.status}"
          ]}>
            {participant_status_label(participant.status)}
          </span>
        </div>
      </div>
    </section>
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
      side -> side_display_label(side.label)
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

  defp combat_hp_class(hp, max_hp) when max_hp > 0 do
    cond do
      hp / max_hp <= 0.2 -> "cbt-hp__fill--critical"
      hp / max_hp <= 0.45 -> "cbt-hp__fill--low"
      true -> nil
    end
  end

  defp combat_hp_class(_hp, _max_hp), do: nil

  defp arena_sides(%{spectator?: true, sides: sides}) do
    {List.first(sides), Enum.at(sides, 1)}
  end

  defp arena_sides(%{participant: participant, sides: sides}) do
    ally_side = participant && Enum.find(sides, &(&1.id == participant.side))

    enemy_side =
      Enum.find(sides, fn side -> is_nil(ally_side) or side.id != ally_side.id end)

    {enemy_side || List.first(sides), ally_side || Enum.at(sides, 1)}
  end

  defp participant_initial(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      initial -> initial
    end
  end

  defp combat_opening(:duel),
    do:
      "Круг замкнут. Противники читают друг друга в свете печатей; каждое решение войдёт в мир одновременно."

  defp combat_opening(:dungeon_encounter),
    do:
      "Тьма сомкнулась вокруг отряда. Здесь одна чаша здоровья на всех, а отступление может стоить всей добычи."

  defp combat_opening(:overworld_encounter),
    do:
      "Дорога стала полем боя. Железо, припасы и выдержка решат то, что магия вдали от Башни решить не может."

  defp combat_opening(_kind),
    do: "Круг решения открыт. Стороны накладывают печати, и мир ждёт их общего исхода."

  defp outcome_class(%{spectator?: true}), do: :victory

  defp outcome_class(%{participant: participant, combat: combat}) do
    if participant && participant.side == combat.winner_side, do: :victory, else: :defeat
  end

  defp deadline_label(_deadline_at, true), do: "ход разрешается"
  defp deadline_label(nil, _resolving?), do: "время уточняется"

  defp deadline_label(deadline_at, _resolving?),
    do: Calendar.strftime(deadline_at, "%H:%M:%S UTC")

  defp combat_kind_label(:duel), do: "Дуэль"
  defp combat_kind_label(:dungeon_encounter), do: "Схватка в подземелье"
  defp combat_kind_label(:overworld_encounter), do: "Столкновение в пути"
  defp combat_kind_label(_kind), do: "Бой"

  defp dungeon_combat?(%{kind: :dungeon_encounter}), do: true
  defp dungeon_combat?(_combat), do: false

  defp combat_status_label(:active_turn), do: "ход открыт"
  defp combat_status_label(:locked), do: "печати собраны"
  defp combat_status_label(:resolving), do: "разрешение"
  defp combat_status_label(:finished), do: "завершён"
  defp combat_status_label(_status), do: "состояние уточняется"

  defp participant_status_label(:ready), do: "готов"
  defp participant_status_label(:defeated), do: "повержен"
  defp participant_status_label(:fled), do: "отступил"
  defp participant_status_label(_status), do: "состояние неизвестно"

  defp winner_label(state) do
    case Enum.find(state.sides, &(&1.id == state.combat.winner_side)) do
      nil -> "не определена"
      side -> side_display_label(side.label)
    end
  end

  defp item_action_label(:strike), do: "удар"
  defp item_action_label(:sweep), do: "взмах"
  defp item_action_label(:raise_shield), do: "щит"
  defp item_action_label(:throw), do: "бросок"
  defp item_action_label(:deploy), do: "развернуть"
  defp item_action_label(:repair), do: "починка"
  defp item_action_label(_kind), do: "особый приём"

  defp event_label("spell_cast"), do: "заклинание сработало"
  defp event_label("tool_action"), do: "предмет применён"
  defp event_label("action_blocked"), do: "действие сорвалось"
  defp event_label("state_tick"), do: "состояние изменило поле боя"
  defp event_label("environment_hazard_tick"), do: "опасная среда наносит урон"
  defp event_label("channeling_stopped"), do: "канал добровольно прерван"
  defp event_label("wait"), do: "сторона выжидает"
  defp event_label("fled"), do: "участник отступил"
  defp event_label(_event_type), do: "неизвестное событие"

  defp incantation_slots do
    [
      {"actio", "A", "Actio · действие"},
      {"forma", "F", "Forma · форма"},
      {"vis", "V", "Vis · сила"},
      {"tempus", "T", "Tempus · время"},
      {"mutatio", "M", "Mutatio · изменение"},
      {"pretium", "P", "Pretium · цена"}
    ]
  end

  defp lit_incantation_slots(form, prepared_spells) do
    selected_spell = Enum.find(prepared_spells, &(&1.id == form[:spell_id].value))
    entered_formula = normalized_formula(form[:incantation].value)

    case selected_spell do
      %{formula: formula, incantation_slots: slots}
      when is_map(slots) and map_size(slots) > 0 ->
        if entered_formula == normalized_formula(formula) do
          slots
          |> Map.keys()
          |> Enum.filter(&(&1 in @incantation_slot_order))
          |> MapSet.new()
        else
          positional_incantation_slots(entered_formula)
        end

      _legacy_or_custom_formula ->
        positional_incantation_slots(entered_formula)
    end
  end

  defp positional_incantation_slots(formula) do
    word_count = formula |> String.split(~r/\s+/, trim: true) |> length() |> min(6)

    @incantation_slot_order
    |> Enum.take(word_count)
    |> MapSet.new()
  end

  defp normalized_formula(nil), do: ""

  defp normalized_formula(formula) do
    formula = to_string(formula)

    case Incantation.normalize(formula) do
      {:ok, normalized} ->
        normalized

      {:error, _reason} ->
        formula
        |> String.split(~r/\s+/, trim: true)
        |> Enum.join(" ")
    end
  end

  defp side_display_label(label) when is_binary(label) do
    case String.downcase(String.trim(label)) do
      "party" -> "Отряд"
      "allies" -> "Союзники"
      "encounter" -> "Противники"
      "enemies" -> "Противники"
      "challengers" -> "Вызывающие"
      "defenders" -> "Защитники"
      "attackers" -> "Нападающие"
      _other -> label
    end
  end

  defp side_display_label(_label), do: "Сторона"

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
