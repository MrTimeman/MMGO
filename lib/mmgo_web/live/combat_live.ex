defmodule MMGOWeb.CombatLive do
  @moduledoc """
  Combat — the emotional peak (GDD §3). A single engine drives duels and
  dungeon fights: shared party HP per side, simultaneous sealed turns, and
  an AI narration region that is the only thing players see of resolution.

  This is a **design-pass** screen: all state is hardcoded demo data and a
  short scripted arc that advances each time the caster submits an
  incantation. No backend, no DB — `# TODO: wire` marks the seams where the
  real combat engine, Spell AI, and turn timer will attach.
  """
  use MMGOWeb, :live_view

  # ── Status-effect primitives (GDD §2.3.3) → glyph, Russian label, colour
  # class. A fixed set the engine can resolve; here they only decorate the
  # member chips. Glyphs are dingbats (no emoji, per the design brief).
  @status %{
    burning: {"❂", "Горит", "burn"},
    frozen: {"❄", "Скован льдом", "freeze"},
    shielded: {"◈", "Под щитом", "shield"},
    exposed: {"◎", "Уязвим", "expose"},
    staggered: {"≀", "Оглушён", "stagger"},
    trapped: {"⊠", "В ловушке", "trap"},
    silenced: {"⊘", "Немота", "silence"},
    regenerating: {"✚", "Исцеляется", "regen"},
    empowered: {"✦", "Усилен", "power"}
  }

  # The six Latin incantation slots (GDD §2.2.2), in canonical order. The
  # action bar lights one tick per word the caster has written.
  @slot_ticks [
    {"A", "Actio"},
    {"F", "Forma"},
    {"V", "Vis"},
    {"T", "Tempus"},
    {"M", "Mutatio"},
    {"P", "Pretium"}
  ]

  # A write-once grimoire of ~10 demo base spells (GDD §7.2). The caster
  # picks one as the Fundamen the incantation builds upon.
  @grimoire [
    %{id: "ignis-prima", name: "Ignis Prima", ru: "Первый огонь", school: :fire, cd: 0},
    %{id: "ictus-flammae", name: "Ictus Flammae", ru: "Удар пламени", school: :fire, cd: 1},
    %{id: "scintilla", name: "Scintilla", ru: "Искра", school: :fire, cd: 0},
    %{id: "murus-ignis", name: "Murus Ignis", ru: "Огненная стена", school: :fire, cd: 3},
    %{id: "sphaera-solis", name: "Sphaera Solis", ru: "Солнечная сфера", school: :fire, cd: 2},
    %{id: "ultima-flamma", name: "Ultima Flamma", ru: "Последнее пламя", school: :fire, cd: 4},
    %{id: "chaos-vortex", name: "Chaos Vortex", ru: "Вихрь хаоса", school: :chaos, cd: 2},
    %{id: "fractura", name: "Fractura", ru: "Разлом", school: :chaos, cd: 2},
    %{
      id: "velum-cinereum",
      name: "Velum Cinereum",
      ru: "Пепельная завеса",
      school: :chaos,
      cd: 1
    },
    %{id: "sanguis-ardens", name: "Sanguis Ardens", ru: "Горящая кровь", school: :chaos, cd: 3}
  ]

  # Tool-user inventory (GDD §3.3.2): deterministic items, each offering a
  # fixed set of actions. No AI — values come from item tables.
  @inventory [
    %{id: "sword", name: "Стальной клинок", weight: "3.0", actions: ["Ударить", "Метнуть"]},
    %{id: "shield", name: "Тяжёлый щит", weight: "5.5", actions: ["Снарядить", "Блок"]},
    %{id: "fire-vial", name: "Склянка огня", weight: "0.4", actions: ["Метнуть"]},
    %{id: "ice-vial", name: "Склянка стужи", weight: "0.4", actions: ["Метнуть"]},
    %{id: "smoke-vial", name: "Дымовая склянка", weight: "0.3", actions: ["Метнуть"]},
    %{id: "net", name: "Сеть ловчего", weight: "1.2", actions: ["Расставить", "Метнуть"]},
    %{id: "repair", name: "Ремонтный набор", weight: "1.0", actions: ["Починить"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — real combat_id, participants, and shared-HP state from the
    # Combat context; scripted demo data stands in for the resolution engine.
    {:ok, load_scenario(socket, :duel), temporary_assigns: []}
  end

  # ── Demo controls ──────────────────────────────────────────────────────
  @impl true
  def handle_event("toggle_mode", %{"mode" => mode}, socket) do
    {:noreply, load_scenario(socket, String.to_existing_atom(mode))}
  end

  # ── Action bar ─────────────────────────────────────────────────────────
  @impl true
  def handle_event("type_incantation", %{"incantation" => text}, socket) do
    {:noreply, assign(socket, :incantation, text)}
  end

  @impl true
  def handle_event("open_drawer", %{"drawer" => drawer}, socket) do
    {:noreply, assign(socket, :drawer, String.to_existing_atom(drawer))}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer, nil)}
  end

  @impl true
  def handle_event("select_spell", %{"id" => id}, socket) do
    spell = Enum.find(@grimoire, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_spell, spell && %{name: spell.name, ru: spell.ru, tool: false})
     |> assign(:drawer, nil)}
  end

  @impl true
  def handle_event("tool_action", %{"item" => item, "action" => action}, socket) do
    name = Enum.find(@inventory, &(&1.id == item))[:name]

    {:noreply,
     socket
     |> assign(:selected_spell, %{name: "#{action}: #{name}", ru: "приём мастера", tool: true})
     |> assign(:incantation, "")
     |> assign(:drawer, nil)}
  end

  # ── Sealing a turn (GDD §3.2: simultaneous, then locked) ────────────────
  @impl true
  def handle_event("cast", params, socket) do
    if socket.assigns.phase == :awaiting and socket.assigns.script != [] do
      spoken =
        cond do
          socket.assigns.selected_spell && socket.assigns.selected_spell.tool ->
            socket.assigns.selected_spell.name

          true ->
            (params["incantation"] || socket.assigns.incantation || "")
            |> String.trim()
            |> case do
              "" -> "Ictus"
              text -> text
            end
        end

      # TODO: wire — push the sealed action to the engine; the turn timer and
      # "waiting for others" resolve when every side has locked in.
      Process.send_after(self(), :resolve_seal, 1400)

      {:noreply,
       socket
       |> assign(:phase, :sealed)
       |> assign(:spoken, spoken)
       |> assign(:drawer, nil)}
    else
      {:noreply, socket}
    end
  end

  # ── Fleeing (GDD §3.5; §10.5 in the dungeon) ───────────────────────────
  @impl true
  def handle_event("flee", _params, socket) do
    {:noreply, assign(socket, :flee_confirm, true)}
  end

  @impl true
  def handle_event("flee_cancel", _params, socket) do
    {:noreply, assign(socket, :flee_confirm, false)}
  end

  @impl true
  def handle_event("flee_confirm", _params, socket) do
    # A forfeited duel costs only the wager → back to the world map. Falling
    # in the dungeon triggers Roguelike's Sacrifice → the revival screen.
    case socket.assigns.mode do
      :dungeon -> {:noreply, push_navigate(socket, to: ~p"/defeat")}
      _ -> {:noreply, push_navigate(socket, to: ~p"/map")}
    end
  end

  # ── Resolution sequence ────────────────────────────────────────────────
  @impl true
  def handle_info(:resolve_seal, socket) do
    Process.send_after(self(), :apply_turn, 850)
    {:noreply, assign(socket, :phase, :resolving)}
  end

  @impl true
  def handle_info(:apply_turn, socket) do
    case socket.assigns.script do
      [] ->
        {:noreply, assign(socket, :phase, :awaiting)}

      [turn | rest] ->
        block = %{
          kind: :turn,
          label: turn.label,
          spoken: socket.assigns.spoken,
          paras: turn.paras,
          env: turn[:env],
          tone: turn[:tone] || :normal
        }

        socket =
          socket
          |> update(:log, &(&1 ++ [block]))
          |> assign(:script, rest)
          |> assign(:sides, %{
            ally: put_side(socket.assigns.sides.ally, turn.ally_hp, turn.ally_chips),
            enemy: put_side(socket.assigns.sides.enemy, turn.enemy_hp, turn.enemy_chips)
          })
          |> assign(:turn, socket.assigns.turn + 1)
          |> assign(:incantation, "")
          |> assign(:spoken, nil)
          |> assign(:selected_spell, nil)
          |> assign(:outcome, turn[:outcome])
          |> assign(:phase, if(turn[:outcome], do: :over, else: :awaiting))
          |> push_event("combat_reveal", %{})

        {:noreply, socket}
    end
  end

  defp put_side(side, hp, chips) do
    members =
      case chips do
        nil -> side.members
        list -> apply_chips(side.members, list)
      end

    %{side | hp: hp, members: members}
  end

  # chips is a list matching members by index; nil means "leave unchanged".
  defp apply_chips(members, chips) do
    members
    |> Enum.zip(chips ++ List.duplicate(nil, max(0, length(members) - length(chips))))
    |> Enum.map(fn
      {member, nil} -> member
      {member, list} -> %{member | chips: list}
    end)
  end

  # =========================================================================
  # Render
  # =========================================================================
  @impl true
  def render(assigns) do
    ~H"""
    <div class={["cbt-arena", "cbt-arena--#{@mode}", @outcome && "cbt-arena--over"]}>
      <div class="cbt-vignette"></div>

      <%!-- ── Combatants: shared HP, member chips, turn + timer ── --%>
      <header class="cbt-top">
        <div class="cbt-topbar">
          <button
            type="button"
            class="cbt-flee-btn"
            phx-click={if @phase in [:awaiting, :over], do: "flee"}
            disabled={@phase not in [:awaiting, :over]}
          >
            <span aria-hidden="true">‹</span> Бежать
          </button>

          <div class="cbt-mode-toggle" role="group" aria-label="Режим боя (демо)">
            <button
              type="button"
              class={["cbt-mode", @mode == :duel && "cbt-mode--on"]}
              phx-click="toggle_mode"
              phx-value-mode="duel"
            >
              Дуэль
            </button>
            <button
              type="button"
              class={["cbt-mode", @mode == :dungeon && "cbt-mode--on"]}
              phx-click="toggle_mode"
              phx-value-mode="dungeon"
            >
              Подземелье
            </button>
          </div>
        </div>

        <.side_panel side={@sides.enemy} align="enemy" />

        <div class="cbt-turnrow">
          <span class="cbt-turn-line"></span>
          <div class="cbt-turnring" id={"cbt-turnring-#{@turn}-#{@phase}"}>
            <svg viewBox="0 0 44 44" class="cbt-turnring__svg" aria-hidden="true">
              <circle class="cbt-turnring__track" cx="22" cy="22" r="19" />
              <circle
                class={["cbt-turnring__sweep", @phase != :awaiting && "is-held"]}
                cx="22"
                cy="22"
                r="19"
              />
            </svg>
            <span class="cbt-turnring__label">
              <em>ход</em>{roman(@turn)}
            </span>
          </div>
          <span class="cbt-turn-line"></span>
        </div>

        <.side_panel side={@sides.ally} align="ally" />

        <%= if @stakes do %>
          <p class="cbt-stakes"><span class="cbt-stakes__mark">❧</span> {@stakes}</p>
        <% end %>
      </header>

      <%!-- ── THE NARRATION: the only window into resolution ── --%>
      <main
        class="cbt-log"
        id={"cbt-log-#{@mode}"}
        phx-hook="CombatLog"
        phx-update="stream"
        role="log"
        aria-live="polite"
      >
        <%= for {block, i} <- Enum.with_index(@log) do %>
          <article
            class={[
              "cbt-turn",
              "cbt-turn--#{block.kind}",
              block[:tone] == :danger && "cbt-turn--danger"
            ]}
            id={"cbt-block-#{i}"}
          >
            <%= if block.kind == :prologue do %>
              <p class="cbt-turn__prologue">{block.paras |> hd()}</p>
            <% else %>
              <div class="cbt-turn__sep">
                <span class="cbt-turn__label">{block.label}</span>
                <%= if block[:spoken] do %>
                  <span class="cbt-turn__spoken">«{block.spoken}»</span>
                <% end %>
              </div>
              <%= for para <- block.paras do %>
                <p class="cbt-turn__para">{para}</p>
              <% end %>
              <%= if block[:env] do %>
                <aside class="cbt-env">
                  <span class="cbt-env__tag">Среда</span>
                  <span class="cbt-env__text">{block.env}</span>
                </aside>
              <% end %>
            <% end %>
          </article>
        <% end %>

        <%= if @outcome do %>
          <div class={["cbt-outcome", "cbt-outcome--#{@outcome}"]} id="cbt-outcome">
            <span class="cbt-outcome__seal">{if @outcome == :victory, do: "✦", else: "☒"}</span>
            <p class="cbt-outcome__title">{outcome_title(@outcome)}</p>
            <p class="cbt-outcome__sub">{@outcome_note}</p>
            <a href={~p"/map"} class="cbt-outcome__btn">Покинуть арену</a>
          </div>
        <% end %>
      </main>

      <%!-- ── Caster action bar ── --%>
      <footer class={["cbt-actbar", @phase in [:sealed, :resolving] && "cbt-actbar--sealed"]}>
        <%= if @phase in [:sealed, :resolving] do %>
          <div class="cbt-seal">
            <span class="cbt-seal__wax" aria-hidden="true">
              <span class="cbt-seal__rune">ᛟ</span>
            </span>
            <div class="cbt-seal__copy">
              <p class="cbt-seal__title">Действие запечатано</p>
              <p class="cbt-seal__sub">
                {if @phase == :sealed, do: "Ждём остальных…", else: "Круг разрешается…"}
              </p>
            </div>
          </div>
        <% else %>
          <%= if @outcome do %>
            <div class="cbt-actbar__done">Поединок окончен.</div>
          <% else %>
            <div class="cbt-slots">
              <%= for {tick, idx} <- Enum.with_index(slot_ticks()) do %>
                <span
                  class={["cbt-slot", idx < word_count(@incantation) && "cbt-slot--lit"]}
                  title={"#{elem(tick, 1)}"}
                >
                  {elem(tick, 0)}
                </span>
              <% end %>
              <span class="cbt-slots__count">{word_count(@incantation)}/6</span>
            </div>

            <form class="cbt-form" phx-change="type_incantation" phx-submit="cast">
              <%= if @selected_spell do %>
                <div class={["cbt-basechip", @selected_spell.tool && "cbt-basechip--tool"]}>
                  <span class="cbt-basechip__mark">
                    {if @selected_spell.tool, do: "⚒", else: "✦"}
                  </span>
                  <span class="cbt-basechip__name">{@selected_spell.name}</span>
                  <span class="cbt-basechip__ru">{@selected_spell.ru}</span>
                </div>
              <% end %>

              <div class="cbt-castrow">
                <input
                  type="text"
                  name="incantation"
                  value={@incantation}
                  class="cbt-input"
                  placeholder="Произнесите заклинание…"
                  autocomplete="off"
                  spellcheck="false"
                  phx-debounce="120"
                />
                <button type="submit" class="cbt-cast">
                  <span class="cbt-cast__label">Сотворить</span>
                </button>
              </div>

              <div class="cbt-drawer-btns">
                <button
                  type="button"
                  class="cbt-dbtn"
                  phx-click="open_drawer"
                  phx-value-drawer="grimoire"
                >
                  <span class="cbt-dbtn__glyph">❦</span> Гримуар
                </button>
                <button
                  type="button"
                  class="cbt-dbtn"
                  phx-click="open_drawer"
                  phx-value-drawer="inventory"
                >
                  <span class="cbt-dbtn__glyph">⚔</span> Инвентарь
                </button>
              </div>
            </form>
          <% end %>
        <% end %>
      </footer>

      <%!-- ── Slide-up drawers ── --%>
      <%= if @drawer do %>
        <div class="cbt-scrim" phx-click="close_drawer"></div>
        <div class={["cbt-sheet", "cbt-sheet--#{@drawer}"]}>
          <div class="cbt-sheet__grip"></div>
          <%= if @drawer == :grimoire do %>
            <h2 class="cbt-sheet__title">Гримуар «Искра»</h2>
            <p class="cbt-sheet__hint">Выберите основу — на неё ляжет заклинание.</p>
            <ul class="cbt-splist">
              <%= for spell <- grimoire() do %>
                <li>
                  <button
                    type="button"
                    class="cbt-spell"
                    phx-click="select_spell"
                    phx-value-id={spell.id}
                  >
                    <span class={["cbt-spell__dot", "cbt-spell__dot--#{spell.school}"]}></span>
                    <span class="cbt-spell__names">
                      <span class="cbt-spell__lat">{spell.name}</span>
                      <span class="cbt-spell__ru">{spell.ru}</span>
                    </span>
                    <span class="cbt-spell__cd">
                      {if spell.cd == 0, do: "готово", else: "откат #{spell.cd}"}
                    </span>
                  </button>
                </li>
              <% end %>
            </ul>
          <% else %>
            <h2 class="cbt-sheet__title">Инвентарь</h2>
            <p class="cbt-sheet__hint">Приёмы мастера — точный расчёт, без магии.</p>
            <ul class="cbt-itemlist">
              <%= for item <- inventory() do %>
                <li class="cbt-item">
                  <div class="cbt-item__head">
                    <span class="cbt-item__name">{item.name}</span>
                    <span class="cbt-item__weight">{item.weight} фнт</span>
                  </div>
                  <div class="cbt-item__actions">
                    <%= for action <- item.actions do %>
                      <button
                        type="button"
                        class="cbt-iact"
                        phx-click="tool_action"
                        phx-value-item={item.id}
                        phx-value-action={action}
                      >
                        {action}
                      </button>
                    <% end %>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      <% end %>

      <%!-- ── Flee confirmation ── --%>
      <%= if @flee_confirm do %>
        <div class="cbt-scrim" phx-click="flee_cancel"></div>
        <div class="cbt-flee-modal">
          <p class="cbt-flee-modal__title">Покинуть бой?</p>
          <p class="cbt-flee-modal__body">{@flee_warning}</p>
          <div class="cbt-flee-modal__row">
            <button type="button" class="cbt-flee-modal__stay" phx-click="flee_cancel">
              Остаться
            </button>
            <button type="button" class="cbt-flee-modal__go" phx-click="flee_confirm">
              {if @mode == :dungeon, do: "Пасть", else: "Сдаться"}
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Side panel (shared HP + member chips) ──────────────────────────────
  attr :side, :map, required: true
  attr :align, :string, required: true

  defp side_panel(assigns) do
    ~H"""
    <section class={["cbt-side", "cbt-side--#{@align}"]}>
      <div class="cbt-side__head">
        <span class="cbt-side__name">{@side.name}</span>
        <span class="cbt-side__hpnum">{@side.hp} / {@side.max}</span>
      </div>
      <div class="cbt-hp">
        <div
          class={["cbt-hp__fill", low_class(@side.hp, @side.max)]}
          style={"width: #{pct(@side.hp, @side.max)}%"}
        >
        </div>
      </div>
      <div class="cbt-chips">
        <%= for m <- @side.members do %>
          <div class="cbt-chip">
            <span class="cbt-chip__token">{m.short}</span>
            <span class="cbt-chip__name">{m.name}</span>
            <span class="cbt-chip__status">
              <%= for chip <- m.chips do %>
                <% {glyph, label, mod} = status_meta(chip) %>
                <span class={["cbt-glyph", "cbt-glyph--#{mod}"]} title={label}>{glyph}</span>
              <% end %>
            </span>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  # =========================================================================
  # Scenario data
  # =========================================================================
  defp load_scenario(socket, :duel) do
    socket
    |> assign(:page_title, "Поединок")
    |> assign(:mode, :duel)
    |> assign(:phase, :awaiting)
    |> assign(:turn, 1)
    |> assign(:incantation, "")
    |> assign(:spoken, nil)
    |> assign(:selected_spell, nil)
    |> assign(:drawer, nil)
    |> assign(:flee_confirm, false)
    |> assign(:outcome, nil)
    |> assign(:outcome_note, "Ставка ваша: 200 монет переходят победителю.")
    |> assign(:stakes, nil)
    |> assign(
      :flee_warning,
      "Сдача поединка отдаёт весь заклад противнику. Чести это не прибавит."
    )
    |> assign(:sides, %{
      enemy: %{
        name: "Кассиан Волхв",
        hp: 120,
        max: 120,
        members: [%{short: "К", name: "Кассиан", chips: []}]
      },
      ally: %{
        name: "Ваша сторона",
        hp: 120,
        max: 120,
        members: [%{short: "А", name: "Альберт Северин", chips: []}]
      }
    })
    |> reset_log(:duel)
    |> assign(:script, duel_script())
  end

  defp load_scenario(socket, :dungeon) do
    socket
    |> assign(:page_title, "Схватка в подземелье")
    |> assign(:mode, :dungeon)
    |> assign(:phase, :awaiting)
    |> assign(:turn, 1)
    |> assign(:incantation, "")
    |> assign(:spoken, nil)
    |> assign(:selected_spell, nil)
    |> assign(:drawer, nil)
    |> assign(:flee_confirm, false)
    |> assign(:outcome, nil)
    |> assign(:outcome_note, "")
    |> assign(:stakes, "На кону всё, что несёт отряд: добыча, гримуары, монеты.")
    |> assign(
      :flee_warning,
      "Отступить с этого яруса нельзя. Пасть — значит призвать Жертву Роглайка: вы вернётесь к Башне ни с чем."
    )
    |> assign(:sides, %{
      enemy: %{
        name: "Выводок пепельных тварей",
        hp: 260,
        max: 260,
        members: [
          %{short: "✳", name: "Матка", chips: []},
          %{short: "•", name: "Порождение", chips: []},
          %{short: "•", name: "Порождение", chips: []}
        ]
      },
      ally: %{
        name: "Отряд «Три искры»",
        hp: 96,
        max: 210,
        members: [
          %{short: "А", name: "Альберт", chips: []},
          %{short: "М", name: "Мара Тенёк", chips: []},
          %{short: "Г", name: "Гортан", chips: []}
        ]
      }
    })
    |> reset_log(:dungeon)
    |> assign(:script, dungeon_script())
  end

  defp reset_log(socket, :duel) do
    assign(socket, :log, [
      %{
        kind: :prologue,
        paras: [
          "Вершина Башни открыта ветру. Дуэльный круг — кольцо чёрного оплавленного стекла, в котором дрожат отражения звёзд. Кассиан Волхв склоняет голову; на его пальцах уже вьётся сизый дым Хаоса. Вы отвечаете поклоном. Круг запечатан — отступить нельзя."
        ]
      }
    ])
  end

  defp reset_log(socket, :dungeon) do
    assign(socket, :log, [
      %{
        kind: :prologue,
        paras: [
          "Третий ярус дышит золой. В темноте тлеют угли чужих глаз — выводок пепельных тварей смыкает вокруг отряда полукольцо. Гортан вскидывает щит перед вами и Марой; коридор за спиной уже осыпался. Драться придётся здесь."
        ]
      }
    ])
  end

  # ── The duel arc: opening → burning ground → near-death → rally ────────
  defp duel_script do
    [
      %{
        label: "Ход I",
        ally_hp: 108,
        enemy_hp: 96,
        ally_chips: nil,
        enemy_chips: [[:shielded]],
        paras: [
          "Первое слово срывается с ваших губ — и воздух перед Кассианом вспыхивает жаром. Он не уклоняется: сизая пелена сворачивается щитом, и пламя растекается по ней, не найдя плоти. Но жар всё же лизнул его руку — Волхв морщится, впервые за вечер, и отвечает росчерком хаоса, что царапает вам плечо."
        ]
      },
      %{
        label: "Ход II",
        ally_hp: 108,
        enemy_hp: 70,
        ally_chips: nil,
        enemy_chips: [[:burning]],
        env:
          "Пылающая земля. Пол круга занялся огнём — всякий, кто стоит в пламени, тлеет с каждым ходом.",
        paras: [
          "Вы чертите дугу, и капли огня, сорвавшись с ладони, впиваются в стеклянный пол. Чёрное зеркало круга занимается: между вами разгорается полоса пылающей земли. Кассиан отступает к самому краю, но подол его мантии уже тлеет — щит хорош против пламени в лоб, но не против пола под ногами."
        ]
      },
      %{
        label: "Ход III",
        tone: :danger,
        ally_hp: 22,
        enemy_hp: 64,
        ally_chips: [[:burning, :exposed]],
        enemy_chips: [[]],
        paras: [
          "Кассиан не гасит огонь — он принимает его. Вскинув руки, Волхв вплетает пламя круга в собственное заклинание, и полоса пылающей земли вздыбливается стеной, что катится на вас. Вы вскидываете щит слишком поздно. Жар выбивает дыхание, стекло под ногами трескается, и мир на миг становится белым. Вы держитесь на ногах — едва."
        ]
      },
      %{
        label: "Ход IV",
        outcome: :victory,
        ally_hp: 22,
        enemy_hp: 0,
        ally_chips: [[]],
        enemy_chips: [[]],
        paras: [
          "Из последних сил вы перестаёте бороться с огнём — и делаете его своим. Хаос откликается охотно: стена пламени замирает, разворачивается и обрушивается назад, на того, кто её призвал. Сизый щит Кассиана лопается со звоном треснувшего стекла. Волхв опускается на колено в гаснущем круге и поднимает раскрытую ладонь. Довольно."
        ]
      }
    ]
  end

  # ── The dungeon arc: ends on a knife-edge — flee → Roguelike's Sacrifice ─
  defp dungeon_script do
    [
      %{
        label: "Ход I",
        ally_hp: 96,
        enemy_hp: 198,
        ally_chips: [[], [], [:shielded]],
        enemy_chips: [[:burning], [], []],
        paras: [
          "Вы бросаете искру в самую гущу — и передний ряд твари вспыхивает, визжа на языке, которого нет у людей. Мара швыряет склянку стужи, и лапы порождений схватывает наледью. Гортан держит строй, приняв удар на щит; за его спиной вы успеваете вдохнуть."
        ]
      },
      %{
        label: "Ход II",
        tone: :danger,
        ally_hp: 41,
        enemy_hp: 150,
        ally_chips: [[:burning], [], [:staggered]],
        enemy_chips: [[], [], []],
        env:
          "Пепельный смерч. Твари вздымают золу — воздух густеет, и каждый вдох в этом облаке жжёт изнутри.",
        paras: [
          "Матка выводка раскрывает хребет, и ярус наполняется золой. Смерч пепла глушит огонь и режет глаза. Гортан оступается под тяжестью щита, тварь достаёт Мару, и общий запас сил отряда стремительно тает. Вы кашляете кровью и пеплом."
        ]
      },
      %{
        label: "Ход III",
        tone: :danger,
        ally_hp: 12,
        enemy_hp: 132,
        ally_chips: [[:burning, :exposed], [:silenced], [:staggered]],
        enemy_chips: [[], [], []],
        paras: [
          "Вы бьёте вихрем хаоса, и матка отшатывается — но выводок бесконечен. Из темноты выступают новые силуэты. Мара уже не может говорить, Гортан едва стоит. Отряд держится на последнем дыхании, и коридор к спасению завален. Решение нужно принять сейчас."
        ]
      }
    ]
  end

  # =========================================================================
  # Helpers
  # =========================================================================
  defp slot_ticks, do: @slot_ticks
  defp grimoire, do: @grimoire
  defp inventory, do: @inventory

  defp status_meta(id), do: Map.fetch!(@status, id)

  defp word_count(nil), do: 0

  defp word_count(text) do
    text |> String.split(~r/\s+/, trim: true) |> length() |> min(6)
  end

  defp pct(hp, max) when max > 0, do: Float.round(hp / max * 100, 1)
  defp pct(_, _), do: 0

  defp low_class(hp, max) do
    cond do
      max <= 0 -> nil
      hp / max <= 0.2 -> "cbt-hp__fill--critical"
      hp / max <= 0.45 -> "cbt-hp__fill--low"
      true -> nil
    end
  end

  defp outcome_title(:victory), do: "Победа"
  defp outcome_title(_), do: "Поражение"

  @roman ~w(0 I II III IV V VI VII VIII IX X XI XII)
  defp roman(n) when n in 0..12, do: Enum.at(@roman, n)
  defp roman(n), do: Integer.to_string(n)
end
