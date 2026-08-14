defmodule MMGOWeb.CombatLive do
  @moduledoc """
  Scoped, server-rendered combat surface.

  The duel is fought by writing: the player types one line, the server reads it
  against the state it already holds, and that becomes the turn. The browser
  supplies only the line. `MMGO.Play` checks that the current scoped character
  belongs to the requested combat, while the combat context locks the exact
  participant, turn, spell, item, and target before sealing anything. Resolution is performed by the durable turn worker,
  never by a client timer or a scripted UI sequence.
  """
  use MMGOWeb, :live_view

  alias MMGO.Combat.Command
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
         |> assign_combat_state(state)
         |> schedule_refresh()}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, combat_error_message(reason))
         |> push_navigate(to: combat_exit_path(socket.assigns.current_scope))}
    end
  end

  @doc """
  One typed line is one decision.

  The line is parsed against the state the server holds, so a name only ever
  points at something the player really has. A line that cannot be read costs
  nothing but the writing of it — the turn is spent by what the engine accepts,
  never by a typo. A line that *is* read is sealed at once: there is no
  confirmation, and a poor choice honestly written is simply a poor choice.
  """
  @impl true
  def handle_event("submit_command", %{"command" => line}, socket) do
    state = socket.assigns.combat_state

    case Command.parse(line, state) do
      {:ok, attrs} ->
        submit_parsed_command(socket, state, attrs, line)

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:command, line)
         |> assign(:action_error, command_error_message(reason))}
    end
  end

  def handle_event("submit_command", _params, socket) do
    {:noreply, assign(socket, :action_error, combat_error_message(:invalid_action))}
  end

  def handle_event("change_command", %{"command" => line}, socket) do
    {:noreply, assign(socket, :command, line)}
  end

  # The reference sheet writes into the line rather than acting on its own, so
  # the player still commits the decision themselves.
  def handle_event("suggest_command", %{"command" => line}, socket) do
    {:noreply, socket |> assign(:command, line) |> assign(:action_error, nil)}
  end

  defp submit_parsed_command(socket, state, attrs, line) do
    case Play.submit_combat_action(socket.assigns.current_scope.character, state.combat.id, attrs) do
      {:ok, updated_state} ->
        {:noreply,
         socket
         |> assign_combat_state(updated_state)
         |> assign(:command, "")
         |> assign(:action_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:command, line)
         |> assign(:action_error, combat_error_message(reason))}
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
         |> push_navigate(to: combat_exit_path(socket.assigns.current_scope))}
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
        lit_incantation_slots(assigns.command, assigns.combat_state.prepared_spells)
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
            <.link
              id={if(@combat_state.arena?, do: "combat-back-to-arena", else: "combat-back-to-map")}
              navigate={combat_exit_path(@current_scope)}
              class="cbt-flee-btn"
            >
              <span aria-hidden="true">‹</span> {combat_exit_label(@combat_state)}
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

        <section
          :if={@combat_state.arena? and @combat_state.arena_event}
          id="arena-active-event"
          data-event-code={@combat_state.arena_event["code"]}
          class={[
            "cbt-arena-event",
            "cbt-arena-event--#{@combat_state.arena_event["accent"]}"
          ]}
        >
          <span class="cbt-arena-event__sigil" aria-hidden="true">✦</span>
          <div class="cbt-arena-event__copy">
            <p>
              Событие поля · {turns_remaining_label(@combat_state.arena_event["remaining_turns"])}
            </p>
            <h2>{@combat_state.arena_event["name"]}</h2>
            <span>{@combat_state.arena_event["description"]}</span>
          </div>
          <div id="arena-environment-tags" class="cbt-arena-event__tags">
            <span :for={tag <- @combat_state.environment_tags}>{environment_tag_label(tag)}</span>
          </div>
        </section>

        <section
          :if={@combat_state.arena?}
          id="arena-event-deck"
          class="cbt-arena-deck"
          aria-label="Возможные события этой арены"
        >
          <span class="cbt-arena-deck__label">Колода событий</span>
          <span
            :for={event <- @combat_state.arena_event_deck}
            id={"arena-deck-event-#{event["code"]}"}
            class={[
              "cbt-arena-deck__chip",
              @combat_state.arena_event &&
                event["code"] == @combat_state.arena_event["code"] &&
                "cbt-arena-deck__chip--active"
            ]}
          >
            {event["name"]}
          </span>
        </section>

        <section
          :if={@combat_state.interaction_hints != []}
          id="arena-interaction-hints"
          class="cbt-interactions"
        >
          <div class="cbt-interactions__title">
            <.icon name="hero-sparkles" class="size-5" /> Поле отвечает на ваши формулы
          </div>
          <div class="cbt-interactions__list">
            <span
              :for={hint <- @combat_state.interaction_hints}
              id={"arena-interaction-#{hint.spell_id}-#{hint.trigger}"}
            >
              <strong>{hint.spell_name}</strong>
              · {interaction_outcome_label(hint)} при теге «{environment_tag_label(hint.trigger)}»
            </span>
          </div>
        </section>

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
              outcome_class(@combat_state) == :defeat && "cbt-outcome--defeat",
              outcome_class(@combat_state) == :draw && "cbt-outcome--draw"
            ]}
          >
            <span class="cbt-outcome__seal">
              {outcome_seal(@combat_state)}
            </span>
            <h2 class="cbt-outcome__title">{outcome_title(@combat_state)}</h2>
            <p class="cbt-outcome__sub">{outcome_subtitle(@combat_state)}</p>
            <.link
              :if={dungeon_combat?(@combat_state.combat)}
              id="combat-outcome-dungeon"
              navigate={~p"/dungeon"}
              class="cbt-outcome__btn"
            >
              Вернуться в экспедицию
            </.link>
            <%!--
            An arena fight ends on its own result screen — rating, season xp,
            any rank change, and the way straight back into the queue — not on
            the hub with nothing said about what just happened.
            --%>
            <.link
              :if={@combat_state.arena?}
              id="combat-outcome-arena"
              navigate={arena_outcome_path(@combat_state)}
              class="cbt-outcome__btn"
            >
              {if arena_match_id(@combat_state), do: "Итог боя", else: "Вернуться на Арену"}
            </.link>
            <.link
              :if={not @combat_state.arena? and not dungeon_combat?(@combat_state.combat)}
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

          <%!--
          The whole interaction. One line, typed, sealed on Enter. What is
          written is what happens: there is no confirmation step and no way to
          take a turn back, so a decision honestly made is a decision kept.
          --%>
          <section
            :if={@combat_state.action_open? and is_nil(@combat_state.own_action)}
            id="combat-console"
            class="cbt-console"
          >
            <div :if={@combat_state.participant} id="combat-mana" class="cbt-mana">
              <span class="cbt-mana__label">Мана</span>
              <div class="cbt-mana__track" aria-hidden="true">
                <span
                  class="cbt-mana__fill"
                  style={"width: #{mana_percent(@combat_state.participant)}%"}
                />
              </div>
              <span class="cbt-mana__value">
                {@combat_state.participant.mana}/{@combat_state.participant.max_mana}
              </span>
            </div>

            <p :if={locked_mana(@combat_state.participant) > 0} class="cbt-console__note">
              Земля удерживает {locked_mana(@combat_state.participant)} маны, пока проявление стоит.
            </p>

            <p
              :if={channeling?(@combat_state.participant)}
              id="combat-channeling-hint"
              class="cbt-console__note"
            >
              Вы поддерживаете эффект. «ждать» оборвёт его добровольно.
            </p>

            <form
              id="combat-command-form"
              phx-submit="submit_command"
              phx-change="change_command"
              class="cbt-command"
            >
              <span class="cbt-command__caret" aria-hidden="true">❧</span>
              <input
                id="combat-command"
                type="text"
                name="command"
                value={@command}
                autocomplete="off"
                autocapitalize="off"
                autocorrect="off"
                spellcheck="false"
                placeholder={command_placeholder(@combat_state)}
                aria-label="Строка действия"
                phx-mounted={JS.focus()}
                class="cbt-command__input"
              />
              <button id="combat-seal" type="submit" class="cbt-command__seal">
                Запечатать
              </button>
            </form>

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

            <p :if={@action_error} id="combat-action-error" class="cbt-command__error">
              {@action_error}
            </p>

            <%!--
            The reference writes into the line instead of acting, so reading it
            is never a shortcut around deciding.
            --%>
            <details id="combat-reference" class="cbt-reference">
              <summary>Что можно написать</summary>

              <div :if={@combat_state.prepared_spells != []} class="cbt-reference__group">
                <p class="cbt-reference__label">Формулы в раскладке</p>
                <button
                  :for={spell <- @combat_state.prepared_spells}
                  id={"combat-formula-#{spell.id}"}
                  type="button"
                  phx-click="suggest_command"
                  phx-value-command={spell.formula}
                  class={[
                    "cbt-reference__chip",
                    not affordable_spell?(spell, @combat_state.participant) && "is-spent"
                  ]}
                >
                  {spell.formula} · {spell.fatigue_cost}
                </button>
              </div>

              <div class="cbt-reference__group">
                <p class="cbt-reference__label">Приказы</p>
                <button
                  :for={{word, gloss} <- command_reference(@combat_state)}
                  id={"combat-verb-#{word}"}
                  type="button"
                  phx-click="suggest_command"
                  phx-value-command={word}
                  class="cbt-reference__chip"
                  title={gloss}
                >
                  {word}
                </button>
              </div>

              <p class="cbt-reference__hint">
                Цель указывается через «по» или «→»: <code>Ignis Prima по Бранд</code>.
                Без цели удар идёт по противной стороне.
              </p>
            </details>
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
          <div
            :if={manifestation_states(participant) != []}
            class="cbt-manifestations"
            aria-label="Призванные сущности"
          >
            <span
              :for={{manifestation, index} <- Enum.with_index(manifestation_states(participant))}
              id={"combat-manifestation-#{participant.id}-#{index}"}
              class={[
                "cbt-manifestation",
                "cbt-manifestation--#{manifestation["state"]}"
              ]}
              title={manifestation_title(manifestation)}
            >
              <span aria-hidden="true">{manifestation_glyph(manifestation["state"])}</span>
              <strong>{manifestation["display_name"] || manifestation_label(manifestation)}</strong>
              <small>{manifestation_stats(manifestation)}</small>
            </span>
          </div>
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

    # The line the player is part-way through writing survives a background
    # refresh; only sealing an action clears it.
    if preserve_form? do
      socket
    else
      assign_new(socket, :command, fn -> "" end)
    end
  end

  defp schedule_refresh(socket) do
    if connected?(socket) and active_combat?(socket.assigns.combat_state.combat) do
      Process.send_after(self(), :refresh_combat, @refresh_interval)
    end

    socket
  end

  defp active_combat?(combat), do: combat.status in [:active_turn, :locked, :resolving]

  defp participants_on_side(state, side_id) do
    state.combat.participants
    |> Enum.filter(&(&1.side == side_id))
    |> Enum.sort_by(& &1.position)
  end

  defp channeling?(%{active_states: active_states}) do
    Enum.any?(List.wrap(active_states), &(Map.get(&1, "state") == "channeling"))
  end

  defp channeling?(_participant), do: false

  defp summoned_weapon?(%{active_states: active_states}) do
    Enum.any?(List.wrap(active_states), &(Map.get(&1, "state") == "summoned_weapon"))
  end

  defp summoned_weapon?(_participant), do: false

  defp manifestation_states(%{active_states: active_states}) do
    Enum.filter(List.wrap(active_states), fn state ->
      Map.get(state, "state") in ["summoned_shield", "summoned_weapon", "summoned_creature"]
    end)
  end

  defp manifestation_states(_participant), do: []

  defp affordable_spell?(spell, %{mana: mana}) when is_integer(mana),
    do: mana >= spell.fatigue_cost

  defp affordable_spell?(_spell, _participant), do: true

  defp arena_outcome_path(state) do
    case arena_match_id(state) do
      nil -> ~p"/arena"
      match_id -> ~p"/arena/result/#{match_id}"
    end
  end

  defp arena_match_id(%{combat: %{metadata: metadata}}) when is_map(metadata) do
    case Map.get(metadata, "arena_match_id") do
      match_id when is_binary(match_id) -> match_id
      _absent -> nil
    end
  end

  defp arena_match_id(_state), do: nil

  defp mana_percent(%{mana: mana, max_mana: max_mana})
       when is_integer(mana) and is_integer(max_mana) and max_mana > 0,
       do: mana |> Kernel./(max_mana) |> Kernel.*(100) |> round() |> min(100) |> max(0)

  defp mana_percent(_participant), do: 0

  defp locked_mana(%{locked_mana: locked}) when is_integer(locked), do: locked
  defp locked_mana(_participant), do: 0

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

  # A line the parser could not read. These are the only messages that cost
  # nothing: the turn is still open and the player writes again.
  defp command_error_message(:empty_command), do: "Строка пуста."

  defp command_error_message({:unknown_spell, written}),
    do: "«#{written}» нет в боевой раскладке."

  defp command_error_message({:ambiguous_spell, written, names}),
    do: "«#{written}» подходит нескольким формулам: #{Enum.join(names, ", ")}. Уточните."

  defp command_error_message(:no_summoned_weapon),
    do: "Призванного оружия в руках нет."

  defp command_error_message({:no_guard, :parry}),
    do: "Парировать нечем: нужно что-то в руках."

  defp command_error_message({:no_guard, _mode}), do: "Защититься нечем."

  defp command_error_message({:unknown_guard, written}),
    do: "«#{written}» — не то, чем можно защититься."

  defp command_error_message(:item_not_named), do: "Назовите предмет."

  defp command_error_message({:unknown_item, written}),
    do: "«#{written}» нет в сумке."

  defp command_error_message({:ambiguous_item, written, names}),
    do: "«#{written}» подходит нескольким предметам: #{Enum.join(names, ", ")}."

  defp command_error_message({:item_has_no_action, name}),
    do: "«#{name}» нечего сделать в бою."

  defp command_error_message(reason), do: combat_error_message(reason)

  defp command_placeholder(%{prepared_spells: [spell | _rest]}),
    do: "#{spell.formula} · ждать · блок"

  defp command_placeholder(_state), do: "ждать · блок · бежать"

  # The verbs worth showing, filtered to the ones this fight actually permits.
  defp command_reference(state) do
    strike =
      if summoned_weapon?(state.participant),
        do: [{"удар", "Удар призванным оружием"}],
        else: []

    item = if state.items == [], do: [], else: [{"предмет", "Использовать предмет из сумки"}]
    flee = if state.flee_available?, do: [{"бежать", "Выйти из боя"}], else: []

    strike ++
      [
        {"блок", "Смягчить следующий удар"},
        {"парировать", "Отвести удар целиком или не отвести вовсе"},
        {"ждать", "Пропустить ход или оборвать канал"}
      ] ++ item ++ flee
  end

  defp combat_exit_path(%{game_mode: :arena}), do: ~p"/arena"
  defp combat_exit_path(_scope), do: ~p"/map"

  defp combat_exit_label(%{arena?: true}), do: "Арена"
  defp combat_exit_label(_state), do: "Карта мира"

  defp turns_remaining_label(1), do: "последний ход"
  defp turns_remaining_label(turns) when is_integer(turns), do: "ещё #{turns} хода"
  defp turns_remaining_label(_turns), do: "длительность уточняется"

  defp environment_tag_label("fire"), do: "огонь"
  defp environment_tag_label("embers"), do: "искры"
  defp environment_tag_label("burning"), do: "пламя"
  defp environment_tag_label("water"), do: "вода"
  defp environment_tag_label("rain"), do: "ливень"
  defp environment_tag_label("wet"), do: "промокшее поле"
  defp environment_tag_label("earth"), do: "земля"
  defp environment_tag_label("life"), do: "жизнь"
  defp environment_tag_label("overgrown"), do: "заросли"
  defp environment_tag_label("death"), do: "смерть"
  defp environment_tag_label("eclipse"), do: "затмение"
  defp environment_tag_label("necrotic"), do: "некроз"
  defp environment_tag_label("air"), do: "воздух"
  defp environment_tag_label("storm"), do: "буря"
  defp environment_tag_label("gale"), do: "шквал"
  defp environment_tag_label("chaos"), do: "хаос"
  defp environment_tag_label("unstable"), do: "нестабильность"
  defp environment_tag_label("wild-magic"), do: "дикая магия"
  defp environment_tag_label("order"), do: "порядок"
  defp environment_tag_label("crystal"), do: "кристалл"
  defp environment_tag_label("warded"), do: "оберег"
  defp environment_tag_label(tag), do: to_string(tag)

  defp interaction_outcome_label(%{outcome: :negate}), do: "гасит эффект"

  defp interaction_outcome_label(%{outcome: :amplify, modifier: modifier})
       when is_integer(modifier),
       do: "усиливается на #{modifier}"

  defp interaction_outcome_label(%{outcome: :replace_environment}),
    do: "преобразует окружение"

  defp interaction_outcome_label(%{outcome: :apply_bonus_state, state: state}),
    do: "создаёт дополнительное состояние «#{state}»"

  defp interaction_outcome_label(_hint), do: "взаимодействует с окружением"

  defp manifestation_glyph("summoned_shield"), do: "◈"
  defp manifestation_glyph("summoned_weapon"), do: "⚔"
  defp manifestation_glyph("summoned_creature"), do: "♞"
  defp manifestation_glyph(_state), do: "✦"

  defp manifestation_label(%{"state" => "summoned_shield"}), do: "Призванный щит"
  defp manifestation_label(%{"state" => "summoned_weapon"}), do: "Призванное оружие"
  defp manifestation_label(%{"state" => "summoned_creature"}), do: "Призванный союзник"
  defp manifestation_label(_state), do: "Призыв"

  defp manifestation_stats(manifestation) do
    [
      if(is_integer(manifestation["hp"]), do: "прочность #{manifestation["hp"]}"),
      if(is_integer(manifestation["power"]), do: "сила #{manifestation["power"]}"),
      if(is_integer(manifestation["remaining_turns"]),
        do: "ходов #{manifestation["remaining_turns"]}"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp manifestation_title(manifestation) do
    "#{manifestation_label(manifestation)} · #{manifestation_stats(manifestation)}"
  end

  defp combat_opening(:arena_match),
    do:
      "Чистый круг открыт. Только выбранные школы, конечный гримуар и то, что вы сумеете сотворить; поле будет меняться само."

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

  defp outcome_class(%{combat: %{winner_side: "draw"}}), do: :draw
  defp outcome_class(%{spectator?: true}), do: :victory

  defp outcome_class(%{participant: participant, combat: combat}) do
    if participant && participant.side == combat.winner_side, do: :victory, else: :defeat
  end

  defp outcome_seal(state) do
    case outcome_class(state) do
      :defeat -> "☒"
      :draw -> "◇"
      :victory -> "✦"
    end
  end

  defp outcome_title(%{combat: %{winner_side: "draw"}}), do: "Ничья"
  defp outcome_title(state), do: "Победа стороны #{winner_label(state)}"

  defp outcome_subtitle(%{combat: %{winner_side: "draw"}, arena?: true}),
    do: "Обе стороны выбыли одновременно; ничья записана в отдельную историю Арены."

  defp outcome_subtitle(%{arena?: true}),
    do: "Результат записан в отдельную историю Арены; мир и его ресурсы не затронуты."

  defp outcome_subtitle(_state), do: "Исход вписан в хронику мира."

  defp lit_incantation_slots(command, prepared_spells) do
    entered_formula = normalized_formula(command)

    selected_spell =
      Enum.find(prepared_spells, fn spell ->
        normalized_formula(spell.formula) == entered_formula
      end)

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
      "team a" -> "Команда A"
      "team b" -> "Команда B"
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
  defp combat_error_message(:items_disabled), do: "На Арене предметы и зелья отключены."

  defp combat_error_message(:manifestation_unavailable),
    do: "Призванное оружие уже рассеялось или недоступно."

  defp combat_error_message(:invalid_item_action), do: "Этот приём недоступен предмету."

  defp combat_error_message(:invalid_incantation),
    do: "Формула должна состоять из допустимых слов."

  defp combat_error_message(:insufficient_mana), do: "Не хватает маны на это действие."

  defp combat_error_message(:spell_rank_too_high),
    do: "Ваш ранг ещё не позволяет владеть этим заклинанием."

  defp combat_error_message(:guard_source_unavailable),
    do: "Этим нельзя защититься: выберите другое."

  defp combat_error_message(:invalid_action), do: "Не удалось прочитать действие."
  defp combat_error_message(_reason), do: "Мир отклонил это действие. Попробуйте обновить бой."

  defp combat_kind_label(:duel), do: "Дуэль"

  defp combat_kind_label(:arena_match), do: "Арена"

  defp combat_kind_label(:dungeon_encounter), do: "Схватка в подземелье"

  defp combat_kind_label(:overworld_encounter), do: "Столкновение в пути"

  defp combat_kind_label(_kind), do: "Бой"

  defp combat_status_label(:active_turn), do: "ход открыт"

  defp combat_status_label(:locked), do: "печати собраны"

  defp combat_status_label(:resolving), do: "разрешение"

  defp combat_status_label(:finished), do: "завершён"

  defp combat_status_label(_status), do: "состояние уточняется"

  defp deadline_label(_deadline_at, true), do: "ход разрешается"

  defp deadline_label(nil, _resolving?), do: "время уточняется"

  defp deadline_label(deadline_at, _resolving?),
    do: Calendar.strftime(deadline_at, "%H:%M:%S UTC")

  defp dungeon_combat?(%{kind: :dungeon_encounter}), do: true

  defp dungeon_combat?(_combat), do: false

  defp event_label("spell_cast"), do: "заклинание сработало"

  defp event_label("arena_event"), do: "поле Арены изменилось"

  defp event_label("manifestation_strike"), do: "призванное оружие нанесло удар"

  defp event_label("manifestation_strike_missed"), do: "призванное оружие промахнулось"

  defp event_label("summon_action"), do: "призванный союзник атаковал"

  defp event_label("summon_action_missed"), do: "призванный союзник промахнулся"

  defp event_label("insufficient_mana"), do: "не хватило маны"

  defp event_label("manifestation_upkeep"), do: "проявления требуют маны"

  defp event_label("guard_raised"), do: "защита выставлена"

  defp event_label("parry_failed"), do: "парирование не удалось"

  defp event_label("summon_destroyed"), do: "призванная сущность рассеялась"

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
end
