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

  # Flipping a page is not a turn, so it costs nothing and is never sealed.
  def handle_event("turn_to", %{"page" => page}, socket) do
    pages = book_pages(socket.assigns.combat_state)

    page =
      case Integer.parse(to_string(page)) do
        {parsed, _rest} -> parsed |> max(1) |> min(pages)
        :error -> 1
      end

    {:noreply, assign(socket, :book_page, page)}
  end

  def handle_event("submit_command", _params, socket) do
    {:noreply, assign(socket, :action_error, combat_error_message(:invalid_action))}
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

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main id="combat-screen" class="cbt">
        <%!-- What the orchestrator has written. The largest thing on the
              screen, because it is the fight. --%>
        <section id="combat-events" class="cbt-scroll" role="log" aria-live="polite">
          <p class="cbt-scroll__meta">
            <span>Ход {turn_number(@combat_state)}</span>
            <span id="combat-deadline">{countdown_label(@combat_state)}</span>
            <span id="combat-status">{match_label(@combat_state)}</span>
          </p>

          <article
            :for={entry <- @combat_state.chronicle}
            id={"combat-turn-#{entry.number}"}
            class="cbt-scroll__turn"
          >
            <p :for={line <- entry.events} id={"combat-event-#{line.id}"} class="cbt-scroll__line">
              <span aria-hidden="true">▸</span> Ход {entry.number}. {chronicle_sentence(line)}
            </p>

            <p :if={entry.narration} class="cbt-scroll__prose">{entry.narration}</p>
          </article>

          <p :if={@combat_state.chronicle == []} id="combat-events-empty" class="cbt-scroll__prose">
            {combat_opening(@combat_state.combat.kind)}
          </p>

          <p :if={@combat_state.spectator?} id="combat-spectator" class="cbt-scroll__note">
            Вы наблюдаете. Писать в круг могут только участники.
          </p>

          <p :if={@combat_state.resolving?} id="combat-resolving" class="cbt-scroll__note">
            Ход разрешается…
          </p>

          <p
            :if={@combat_state.awaiting? and not @combat_state.resolving?}
            id="combat-awaiting"
            class="cbt-scroll__note"
          >
            Действие принято. Ждём остальных.
          </p>

          <div
            :if={@combat_state.combat.status == :finished}
            id="combat-outcome"
            class="cbt-scroll__outcome"
          >
            <p>{outcome_title(@combat_state)}</p>
            <.link
              id={outcome_link_id(@combat_state)}
              navigate={outcome_path(@combat_state, @current_scope)}
              class="cbt-scroll__out"
            >
              {outcome_link_label(@combat_state)}
            </.link>
          </div>
        </section>

        <%!-- The line. Uncontrolled on purpose: it lives in the browser until
              it is submitted, so nothing the server sends can overwrite a word
              being typed. --%>
        <form
          :if={@combat_state.action_open? and is_nil(@combat_state.own_action)}
          id="combat-command-form"
          phx-submit="submit_command"
          class="cbt-cast"
        >
          <label for="combat-command" class="cbt-cast__label">Каст:</label>
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
            phx-mounted={JS.focus()}
            class="cbt-cast__input"
          />
        </form>

        <p :if={@action_error} id="combat-action-error" class="cbt-cast__error">
          {@action_error}
        </p>

        <div class="cbt-teams">
          <.cbt_team
            :if={@ally_side}
            side={@ally_side}
            state={@combat_state}
            tone="ally"
          />
          <.cbt_team
            :if={@enemy_side}
            side={@enemy_side}
            state={@combat_state}
            tone="enemy"
          />
        </div>

        <%!--
        The open book. Five formulas to a page and no more: a player who can
        see everything at once never learns anything, and flipping is the price
        of not having memorised your own book.
        --%>
        <section :if={not @combat_state.spectator?} id="combat-book" class="cbt-tome">
          <div class="cbt-tome__ribbons">
            <button
              :for={bookmark <- @combat_state.book.bookmarks}
              id={"combat-ribbon-#{bookmark.id}"}
              type="button"
              phx-click="turn_to"
              phx-value-page={bookmark.page}
              class={["cbt-tome__ribbon", @book_page == bookmark.page && "is-open"]}
              style={bookmark.colour && "background: #{bookmark.colour}"}
              title={"#{bookmark.label} · с. #{bookmark.page}"}
            >
              <span :if={bookmark.icon} aria-hidden="true">{bookmark.icon}</span> {bookmark.label}
            </button>
          </div>

          <%!-- Two leaves open at once, the way a book lies. The arrows sit on
                the outer edges, where a thumb already is. --%>
          <div class="cbt-tome__spread">
            <button
              id="combat-page-back"
              type="button"
              phx-click="turn_to"
              phx-value-page={@book_page - 2}
              disabled={@book_page <= 1}
              class="cbt-tome__turn cbt-tome__turn--back"
              aria-label="Предыдущий разворот"
            >
              ‹
            </button>

            <div class="cbt-tome__leaves">
              <div
                :for={leaf <- spread_leaves(@combat_state, @book_page)}
                class="cbt-tome__page"
              >
                <p :if={leaf.number == 1 and @combat_state.book.note} class="cbt-tome__margin">
                  {@combat_state.book.note}
                </p>

                <button
                  :for={spell <- leaf.spells}
                  id={"combat-formula-#{spell.id}"}
                  type="button"
                  phx-click={
                    JS.dispatch("mmgo:write",
                      to: "#combat-command",
                      detail: %{text: spell.formula}
                    )
                  }
                  class={[
                    "cbt-tome__spell",
                    not affordable_spell?(spell, @combat_state.participant) && "is-spent"
                  ]}
                >
                  <span class="cbt-tome__seal" style={"background: #{school_color(spell.school)}"}>
                    {school_glyph(spell.school)}
                  </span>
                  <span class="cbt-tome__text">
                    <span class="cbt-tome__formula">{spell.formula}</span>
                    <span class="cbt-tome__cost">{spell.name} · {spell.fatigue_cost}</span>
                    <span :if={spell.note} class="cbt-tome__note">{spell.note}</span>
                  </span>
                </button>

                <span class="cbt-tome__folio">с. {leaf.number}</span>
              </div>
            </div>

            <button
              id="combat-page-next"
              type="button"
              phx-click="turn_to"
              phx-value-page={@book_page + 2}
              disabled={@book_page + 1 >= book_pages(@combat_state)}
              class="cbt-tome__turn cbt-tome__turn--next"
              aria-label="Следующий разворот"
            >
              ›
            </button>
          </div>

          <div class="cbt-tome__foot">
            <p :if={@combat_state.prepared_spells == []} class="cbt-tome__empty">
              Раскладка пуста.
            </p>

            <.link id="combat-open-grimoire" navigate={grimoire_path(@combat_state)}>
              Гримуар
            </.link>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :side, :map, required: true
  attr :state, :map, required: true
  attr :tone, :string, required: true

  defp cbt_team(assigns) do
    ~H"""
    <section class={["cbt-team", "cbt-team--#{@tone}"]}>
      <p class="cbt-team__label">
        {if @tone == "ally", do: "Отряд", else: "Враги"}
        <span>{@side.shared_hp}/{@side.max_shared_hp}</span>
      </p>

      <div
        :for={fighter <- participants_on_side(@state, @side.id)}
        id={"combat-target-#{fighter.id}"}
        class={[
          "cbt-fighter",
          own_participant?(@state, fighter) && "cbt-fighter--own",
          fighter.status != :ready && "cbt-fighter--down"
        ]}
      >
        <span class="cbt-fighter__face" aria-hidden="true">
          {fighter_initial(@state, fighter)}
        </span>

        <span class="cbt-fighter__bars">
          <span class="cbt-fighter__name">{fighter_name(@state, fighter)}</span>
          <span class="cbt-bar cbt-bar--hp">
            <span style={"width: #{hp_percent(@side.shared_hp, @side.max_shared_hp)}%"} />
          </span>
          <span class="cbt-bar cbt-bar--mana">
            <span style={"width: #{mana_percent(fighter)}%"} />
          </span>
        </span>
      </div>

      <div class="cbt-team__states">
        <span
          :for={state_name <- side_states(@state, @side.id)}
          class="cbt-chip"
          title={state_name}
        >
          {state_name}
        </span>
      </div>
    </section>
    """
  end

  defp turn_number(%{turn: %{number: number}}), do: number
  defp turn_number(_state), do: 1

  # A clock counts down. A timestamp is a thing to work out.
  defp countdown_label(%{resolving?: true}), do: "—"

  defp countdown_label(%{deadline_at: %DateTime{} = deadline_at}) do
    seconds =
      DateTime.utc_now()
      |> DateTime.diff(deadline_at, :second)
      |> Kernel.*(-1)
      |> max(0)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp countdown_label(_state), do: "—"

  # `Дуэль · 3v2` — what this fight is and how the sides stand.
  defp match_label(state) do
    counts =
      state.sides
      |> Enum.map(&length(&1.participants))
      |> Enum.join("v")

    "#{combat_kind_label(state.combat.kind)} · #{counts}"
  end

  defp own_participant?(%{participant: %{id: id}}, %{id: id}), do: true
  defp own_participant?(_state, _fighter), do: false

  defp fighter_name(state, fighter) do
    if own_participant?(state, fighter), do: "Вы", else: fighter.display_name
  end

  # Only what is riding on a fighter right now, named plainly.
  defp fighter_states(%{active_states: active_states}) do
    active_states
    |> List.wrap()
    |> Enum.map(&Map.get(&1, "state"))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp fighter_states(_fighter), do: []

  @doc """
  One event as a sentence.

  The bare event name told the player nothing: "заклинание сработало" is true of
  every cast that ever happened. Who acted, on whom, with what, and for how much
  is what makes a line worth reading.
  """
  def chronicle_sentence(line) do
    [
      line.actor,
      chronicle_verb(line.type),
      line.spell && "«#{line.spell}»",
      line.target && "→ #{line.target}",
      line.damage && "#{line.damage} урона",
      line.state && "(#{line.state})"
    ]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join(" ")
  end

  defp chronicle_verb("spell_cast"), do: "читает"
  defp chronicle_verb("spell_failed"), do: "теряет формулу"
  defp chronicle_verb("spell_partial"), do: "едва удерживает"
  defp chronicle_verb("strike"), do: "бьёт голыми руками"
  defp chronicle_verb("strike_missed"), do: "промахивается"
  defp chronicle_verb("manifestation_strike"), do: "бьёт призванным оружием"
  defp chronicle_verb("manifestation_strike_missed"), do: "промахивается призванным оружием"
  defp chronicle_verb("summon_action"), do: "натравливает союзника"
  defp chronicle_verb("summon_action_missed"), do: "союзник промахивается"
  defp chronicle_verb("summon_destroyed"), do: "теряет призванное"
  defp chronicle_verb("guard_raised"), do: "закрывается"
  defp chronicle_verb("action_blocked"), do: "не может действовать"
  defp chronicle_verb("insufficient_mana"), do: "не находит маны"
  defp chronicle_verb("arena_event"), do: "поле меняется"
  defp chronicle_verb("flee"), do: "выходит из боя"
  defp chronicle_verb(type), do: event_label(type)

  # The eight schools, as a seal and a colour. The book is the one place in a
  # duel allowed to be beautiful: it is the content, not the chrome.
  @school_hues %{
    "fire" => 18,
    "water" => 210,
    "earth" => 80,
    "air" => 190,
    "life" => 140,
    "death" => 270,
    "chaos" => 320,
    "order" => 45
  }

  defp school_color(school) do
    "hsl(#{Map.get(@school_hues, to_string(school), 45)}, 55%, 46%)"
  end

  defp school_glyph(:fire), do: "✦"
  defp school_glyph(:water), do: "≈"
  defp school_glyph(:earth), do: "▲"
  defp school_glyph(:air), do: "≋"
  defp school_glyph(:life), do: "✚"
  defp school_glyph(:death), do: "✖"
  defp school_glyph(:chaos), do: "✧"
  defp school_glyph(:order), do: "◈"
  defp school_glyph(_school), do: "•"

  defp fighter_initial(state, fighter) do
    state
    |> fighter_name(fighter)
    |> String.first()
    |> Kernel.||("?")
    |> String.upcase()
  end

  defp mana_percent(%{mana: mana, max_mana: max_mana})
       when is_integer(mana) and is_integer(max_mana) and max_mana > 0,
       do: mana |> Kernel.*(100) |> div(max_mana) |> min(100) |> max(0)

  defp mana_percent(_participant), do: 0

  # Everything riding on one side of the fight, named once.
  defp side_states(state, side_id) do
    state
    |> participants_on_side(side_id)
    |> Enum.flat_map(&fighter_states/1)
    |> Enum.uniq()
  end

  # Five to a page. The number is the point: it is small enough that a player
  # has to know roughly where their own formulas live.
  @spells_per_page 5

  defp book_pages(state) do
    state.prepared_spells
    |> length()
    |> Kernel./(@spells_per_page)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  defp book_page_spells(state, page) do
    Enum.slice(state.prepared_spells, (page - 1) * @spells_per_page, @spells_per_page)
  end

  # The left leaf is always odd, so a spread opens the way a book does.
  defp spread_leaves(state, page) do
    left = if rem(page, 2) == 1, do: page, else: page - 1
    pages = book_pages(state)

    [left, left + 1]
    |> Enum.filter(&(&1 >= 1 and &1 <= pages))
    |> Enum.map(&%{number: &1, spells: book_page_spells(state, &1)})
  end

  defp grimoire_path(%{arena?: true}), do: ~p"/arena/spellbook/books"
  defp grimoire_path(_state), do: ~p"/spellbook/books"

  defp affordable_spell?(spell, %{mana: mana}) when is_integer(mana),
    do: mana >= spell.fatigue_cost

  defp affordable_spell?(_spell, _participant), do: true

  defp outcome_link_id(%{arena?: true}), do: "combat-outcome-arena"
  defp outcome_link_id(_state), do: "combat-outcome-map"

  defp outcome_link_label(%{arena?: true} = state) do
    if arena_match_id(state), do: "Итог боя", else: "На Арену"
  end

  defp outcome_link_label(_state), do: "Выйти"

  defp outcome_path(%{arena?: true} = state, _scope), do: arena_outcome_path(state)
  defp outcome_path(_state, scope), do: combat_exit_path(scope)

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
      socket
      |> assign_new(:command, fn -> "" end)
      |> assign_new(:book_page, fn -> 1 end)
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

  defp hp_percent(_hp, max_hp) when max_hp <= 0, do: 0

  defp hp_percent(hp, max_hp) do
    hp
    |> Kernel./(max_hp)
    |> Kernel.*(100)
    |> min(100)
    |> max(0)
    |> round()
  end

  defp arena_sides(%{spectator?: true, sides: sides}) do
    {List.first(sides), Enum.at(sides, 1)}
  end

  defp arena_sides(%{participant: participant, sides: sides}) do
    ally_side = participant && Enum.find(sides, &(&1.id == participant.side))

    enemy_side =
      Enum.find(sides, fn side -> is_nil(ally_side) or side.id != ally_side.id end)

    {enemy_side || List.first(sides), ally_side || Enum.at(sides, 1)}
  end

  # A line the parser could not read. These are the only messages that cost
  # nothing: the turn is still open and the player writes again.
  defp command_error_message(:empty_command), do: "Строка пуста."

  defp command_error_message({:unknown_spell, written}),
    do: "«#{written}» нет в боевой раскладке."

  defp command_error_message({:ambiguous_spell, written, names}),
    do: "«#{written}» подходит нескольким формулам: #{Enum.join(names, ", ")}. Уточните."

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

  defp combat_exit_path(%{game_mode: :arena}), do: ~p"/arena"
  defp combat_exit_path(_scope), do: ~p"/map"

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

  defp outcome_title(%{combat: %{winner_side: "draw"}}), do: "Ничья"
  defp outcome_title(state), do: "Победа стороны #{winner_label(state)}"

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

  defp event_label("spell_cast"), do: "заклинание сработало"

  defp event_label("arena_event"), do: "поле Арены изменилось"

  defp event_label("strike"), do: "удар голыми руками"

  defp event_label("strike_missed"), do: "удар прошёл мимо"

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

  defp winner_label(state) do
    case Enum.find(state.sides, &(&1.id == state.combat.winner_side)) do
      nil -> "не определена"
      side -> side_display_label(side.label)
    end
  end
end
