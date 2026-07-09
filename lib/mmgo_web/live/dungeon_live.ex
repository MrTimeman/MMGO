defmodule MMGOWeb.DungeonLive do
  @moduledoc """
  Design-pass screen — the mega-dungeon beneath the Tower (GDD §10).

  One module, two diegetic artifacts consulted by torchlight:

    * `:depths` (/dungeon) — THE DESCENT. A vertical geological
      cross-section of the mega-dungeon: levels stacked downward, upper
      strata warm and lit, deeper ones cold and strange. Known levels
      (visited or map purchased) show their facts; unknown levels are
      sealed fog. The party's current depth and deepest reach are marked.

    * `:level` (/dungeon/level/:n) — THE LEVEL GRAPH. A hand-charted
      expedition map of one floor: a non-linear node graph (§10.1) drawn
      as inline SVG. Visited nodes are solid charted ink; reachable nodes
      glow as current choices; distant known nodes fade; unexplored edges
      trail off into darkness. The party sigil pulses at its position;
      tapping a reachable node opens a confirm sheet, then the marker
      travels the edge and fog recedes. Occasionally the dungeon
      "breathes" — one passage visibly redraws (§10.2).

  No backend wiring — all demo data lives in module attributes. See
  docs/UI_DESIGN_BRIEF.md.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # ── Cross-section (View 1) ────────────────────────────────────────────
  # Seven descending strata (§10.1). `state` is :visited | :map | :fogged.
  # `depth` drives the warm→cold hue shift in CSS.
  @levels [
    %{
      n: 1,
      name: "Верхние галереи",
      epithet: "тихие руины",
      state: :visited,
      danger: "I · низкая",
      village: "Первый привал",
      ascents: 2,
      note: "Самый обжитой ярус — сюда спускаются новички за первой добычей."
    },
    %{
      n: 2,
      name: "Грибные топи",
      epithet: "сырость, споры и болотный свет",
      state: :visited,
      party: true,
      danger: "II · умеренная",
      village: "Мокрый фонарь",
      ascents: 1,
      note: "Отряд стоит здесь. Воздух густой; фонарь гаснет без причины."
    },
    %{
      n: 3,
      name: "Костяные катакомбы",
      epithet: "эхо и старые кости",
      state: :visited,
      deepest: true,
      danger: "III · высокая",
      village: nil,
      ascents: 1,
      note: "Дальше отряд не заходил. Здесь кончается ваша карта, начертанная своей рукой."
    },
    %{
      n: 4,
      name: "Затопленный ярус",
      epithet: "по слухам — вода до самых сводов",
      state: :map,
      danger: "IV · по чужой карте",
      village: nil,
      ascents: 1,
      note: "Карта куплена у гильдии картографов, но отряд здесь не бывал."
    },
    %{n: 5, name: "Неизведано", epithet: nil, state: :fogged, danger: nil},
    %{n: 6, name: "Неизведано", epithet: nil, state: :fogged, danger: nil},
    %{n: 7, name: "Неизведано", epithet: nil, state: :fogged, danger: nil}
  ]

  # ── Level graph (View 2) ──────────────────────────────────────────────
  # Column centres (viewBox 330 wide) and row pitch (viewBox 824 tall).
  @col %{1 => 60, 2 => 165, 3 => 270}
  @row_top 60
  @row_pitch 88

  # Node glyphs + accent role per type.
  @glyphs %{
    "подъём" => "↑",
    "спуск" => "↓",
    "бой" => "⚔",
    "находка" => "◈",
    "стоянка" => "▲",
    "деревня" => "⌂",
    "аномалия" => "✳",
    "?" => "?"
  }

  # Human names per node type, for the confirm sheet.
  @type_dative %{
    "подъём" => "к подъёму",
    "спуск" => "к спуску",
    "бой" => "к логову тварей",
    "находка" => "к тайнику",
    "стоянка" => "к привалу",
    "деревня" => "к деревеньке делверов",
    "аномалия" => "к аномалии",
    "?" => "к неизведанному ходу"
  }

  # Level 1 topology. `reveals` lists node ids the fog gives up on arrival.
  @nodes_l1 [
    %{id: 1, type: "подъём", col: 2, row: 0, name: "Подъём на поверхность", reveals: []},
    %{id: 2, type: "бой", col: 2, row: 1, name: "Крысиные ходы", reveals: []},
    %{id: 3, type: "деревня", col: 1, row: 2, name: "Первый привал", reveals: []},
    %{id: 4, type: "находка", col: 3, row: 2, name: "Осыпь у стены", reveals: []},
    %{id: 5, type: "бой", col: 2, row: 3, name: "Галерея паутин", reveals: []},
    %{id: 14, type: "подъём", col: 3, row: 3, name: "Запасной подъём", reveals: []},
    %{id: 6, type: "аномалия", col: 1, row: 4, name: "Дышащая трещина", reveals: []},
    %{id: 7, type: "стоянка", col: 2, row: 4, name: "Ваш привал", reveals: []},
    %{
      id: 8,
      type: "находка",
      col: 3,
      row: 5,
      name: "Затопленный тайник",
      risk: "низкий",
      hours: 2,
      reveals: [15]
    },
    %{
      id: 9,
      type: "бой",
      col: 1,
      row: 5,
      name: "Гнездо жаб",
      risk: "высокий",
      hours: 1,
      reveals: [12]
    },
    %{
      id: 10,
      type: "аномалия",
      col: 2,
      row: 6,
      name: "Смещённый свод",
      risk: "средний",
      hours: 3,
      reveals: [11, 13]
    },
    %{id: 11, type: "бой", col: 3, row: 7, name: "Костяной страж", reveals: []},
    %{id: 12, type: "стоянка", col: 1, row: 7, name: "Сырой уступ", reveals: []},
    %{id: 13, type: "спуск", col: 2, row: 8, name: "Спуск на 2-й ярус", reveals: []},
    %{id: 15, type: "находка", col: 3, row: 6, name: "Тупик с рудой", reveals: []},
    %{id: 16, type: "?", col: 1, row: 8, name: "Неизведанный ход", reveals: []}
  ]

  @edges_l1 [
    {1, 2},
    {2, 3},
    {2, 4},
    {3, 5},
    {4, 5},
    {4, 14},
    {5, 6},
    {5, 7},
    {6, 7},
    {7, 8},
    {7, 9},
    {8, 10},
    {9, 10},
    {8, 15},
    {10, 11},
    {10, 13},
    {9, 12},
    {12, 16},
    {11, 13}
  ]

  # When the dungeon "breathes" (§10.2): this passage closes…
  @shift_remove {8, 10}
  # …and this shortcut opens between the two forward branches.
  @shift_add {8, 9}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:legend_open, false)
     |> assign(:confirm, nil)
     |> assign(:shifted, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :level ->
        {:noreply, mount_level(socket, params["level"] || "1")}

      _depths ->
        {:noreply,
         socket
         |> assign(:page_title, "Разрез подземелья")
         |> assign(:levels, @levels)}
    end
  end

  # ── Level graph state ─────────────────────────────────────────────────
  defp mount_level(socket, level_str) do
    level = parse_level(level_str)
    deep = level >= 2

    # Party has charted the upper floor down to the mid-map rest spot.
    visited = MapSet.new([1, 2, 3, 4, 5, 6, 14])
    party = 7
    # Revealed = what the torch presently shows: everything visited, the
    # party node, its forward choices, and one known-distant landmark.
    revealed = MapSet.union(visited, MapSet.new([7, 8, 9, 10]))

    socket
    |> assign(:page_title, "Ярус #{level}")
    |> assign(:level, level)
    |> assign(:deep, deep)
    |> assign(:party, party)
    |> assign(:visited, visited)
    |> assign(:revealed, revealed)
    |> assign(:shifted, false)
    |> assign(:confirm, nil)
    |> assign(:legend_open, false)
    |> assign(:breathed, false)
    |> maybe_schedule_breath()
  end

  defp maybe_schedule_breath(socket) do
    if connected?(socket) do
      # The dungeon breathes once, unprompted, a few seconds in (§10.2).
      Process.send_after(self(), :dungeon_breathes, 6500)
    end

    socket
  end

  defp parse_level(str) do
    case Integer.parse(to_string(str)) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  @impl true
  def handle_event("select_node", %{"id" => id}, socket) do
    id = String.to_integer(id)
    node = node_by_id(id)
    reachable = reachable_set(socket.assigns)

    if MapSet.member?(reachable, id) and node do
      {:noreply, assign(socket, :confirm, confirm_for(node))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_move", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  @impl true
  def handle_event("confirm_move", %{"id" => id}, socket) do
    id = String.to_integer(id)
    reachable = reachable_set(socket.assigns)

    if MapSet.member?(reachable, id) do
      {:noreply, move_party(socket, id)}
    else
      {:noreply, assign(socket, :confirm, nil)}
    end
  end

  @impl true
  def handle_event("toggle_legend", _params, socket) do
    {:noreply, assign(socket, :legend_open, not socket.assigns.legend_open)}
  end

  @impl true
  def handle_event("shift_moves", _params, socket) do
    {:noreply, assign(socket, shifted: true, breathed: true)}
  end

  @impl true
  def handle_info(:dungeon_breathes, socket) do
    # Only breathe if the layout is still in its original state.
    if socket.assigns.shifted do
      {:noreply, socket}
    else
      {:noreply, assign(socket, shifted: true, breathed: true)}
    end
  end

  defp move_party(socket, target) do
    %{party: party, visited: visited, revealed: revealed} = socket.assigns
    node = node_by_id(target)

    new_visited = MapSet.put(visited, party)

    new_revealed =
      revealed
      |> MapSet.put(target)
      |> MapSet.union(MapSet.new(neighbors(target, socket.assigns.shifted)))
      |> MapSet.union(MapSet.new(node.reveals))

    socket
    |> assign(:party, target)
    |> assign(:visited, new_visited)
    |> assign(:revealed, new_revealed)
    |> assign(:confirm, nil)
  end

  # ── View derivation ───────────────────────────────────────────────────
  defp reachable_set(%{party: party, visited: visited, revealed: revealed, shifted: shifted}) do
    party
    |> neighbors(shifted)
    |> Enum.filter(fn n ->
      MapSet.member?(revealed, n) and not MapSet.member?(visited, n) and n != party
    end)
    |> MapSet.new()
  end

  defp active_edges(shifted) do
    if shifted do
      @edges_l1
      |> Enum.reject(&same_edge?(&1, @shift_remove))
      |> Kernel.++([@shift_add])
    else
      @edges_l1
    end
  end

  defp same_edge?({a, b}, {c, d}), do: (a == c and b == d) or (a == d and b == c)

  defp neighbors(id, shifted) do
    active_edges(shifted)
    |> Enum.flat_map(fn
      {^id, b} -> [b]
      {a, ^id} -> [a]
      _ -> []
    end)
  end

  defp node_by_id(id), do: Enum.find(@nodes_l1, &(&1.id == id))

  defp col_x(col), do: @col[col]
  defp row_y(row), do: @row_top + row * @row_pitch

  defp confirm_for(node) do
    dative = @type_dative[node.type] || "к ходу"
    hours = Map.get(node, :hours, 2)
    risk = Map.get(node, :risk, "неизвестен")

    %{
      id: node.id,
      title: "Идти #{dative}",
      name: node.name,
      hint: "≈ #{hours} ч пути · риск #{risk}"
    }
  end

  # Builds the annotated node + edge lists the SVG renders from assigns.
  defp build_view(assigns) do
    %{party: party, visited: visited, revealed: revealed, shifted: shifted} = assigns
    reachable = reachable_set(assigns)

    nodes =
      for n <- @nodes_l1, MapSet.member?(revealed, n.id) do
        state =
          cond do
            n.id == party -> :party
            MapSet.member?(reachable, n.id) -> :reachable
            MapSet.member?(visited, n.id) -> :visited
            true -> :known
          end

        n
        |> Map.merge(%{
          x: col_x(n.col),
          y: row_y(n.row),
          glyph: @glyphs[n.type] || "•",
          state: state
        })
      end

    edges =
      for {a, b} <- active_edges(shifted), edge <- [build_edge(a, b, revealed, shifted)], edge do
        edge
      end

    party_node = node_by_id(party)

    %{
      nodes: nodes,
      edges: edges,
      party_x: col_x(party_node.col),
      party_y: row_y(party_node.row)
    }
  end

  defp build_edge(a, b, revealed, shifted) do
    na = node_by_id(a)
    nb = node_by_id(b)
    ax = col_x(na.col)
    ay = row_y(na.row)
    bx = col_x(nb.col)
    by = row_y(nb.row)

    ra = MapSet.member?(revealed, a)
    rb = MapSet.member?(revealed, b)

    shifting? =
      shifted and (same_edge?({a, b}, @shift_add) or same_edge?({a, b}, @shift_remove))

    cond do
      ra and rb ->
        %{x1: ax, y1: ay, x2: bx, y2: by, kind: :solid, shifting: shifting?, id: "#{a}-#{b}"}

      ra ->
        # Trail off toward the fogged node b, stopping short — into darkness.
        %{
          x1: ax,
          y1: ay,
          x2: ax + (bx - ax) * 0.55,
          y2: ay + (by - ay) * 0.55,
          kind: :trail,
          shifting: false,
          id: "#{a}-#{b}"
        }

      rb ->
        %{
          x1: bx,
          y1: by,
          x2: bx + (ax - bx) * 0.55,
          y2: by + (ay - by) * 0.55,
          kind: :trail,
          shifting: false,
          id: "#{a}-#{b}"
        }

      true ->
        nil
    end
  end

  # ── Render ────────────────────────────────────────────────────────────
  @impl true
  def render(%{live_action: :level} = assigns) do
    assigns = assign(assigns, :view, build_view(assigns))

    ~H"""
    <div class={["dng-screen", "dng-screen--graph", @deep && "dng-screen--deep"]}>
      <div class="dng-graph-grain"></div>

      <header class="dng-lvl-head">
        <.link navigate={~p"/dungeon"} class="dng-exit">← к разрезу</.link>
        <div class="dng-lvl-title">
          <span class="dng-lvl-kicker">Экспедиционная карта</span>
          <h1 class="dng-lvl-name">
            Ярус {@level} — {level_title(@level)}
          </h1>
        </div>
        <button type="button" class="dng-legend-btn" phx-click="toggle_legend">
          {if @legend_open, do: "закрыть", else: "легенда"}
        </button>
      </header>

      <%= if @breathed do %>
        <div class="dng-omen" aria-live="polite">
          <span class="dng-omen__mark">✳</span> ходы сместились — подземелье дышит
        </div>
      <% end %>

      <div class="dng-graph-scroll">
        <svg
          class="dng-graph"
          viewBox="0 0 330 824"
          preserveAspectRatio="xMidYMin meet"
          role="img"
          aria-label={"Карта яруса #{@level}"}
        >
          <defs>
            <filter id="dng-ink" x="-20%" y="-20%" width="140%" height="140%">
              <feTurbulence
                type="fractalNoise"
                baseFrequency="0.018"
                numOctaves="2"
                seed="7"
                result="n"
              />
              <feDisplacementMap in="SourceGraphic" in2="n" scale="4" />
            </filter>
          </defs>

          <g class="dng-edges" filter="url(#dng-ink)">
            <line
              :for={e <- @view.edges}
              x1={e.x1}
              y1={e.y1}
              x2={e.x2}
              y2={e.y2}
              class={[
                "dng-edge",
                "dng-edge--#{e.kind}",
                e.shifting && "dng-edge--shifting"
              ]}
            />
          </g>

          <g class="dng-nodes">
            <g
              :for={n <- @view.nodes}
              class={["dng-node", "dng-node--#{n.state}", "dng-node--t-#{node_slug(n.type)}"]}
              transform={"translate(#{n.x} #{n.y})"}
            >
              <circle class="dng-node__disc" r="17" />
              <circle :if={n.state == :reachable} class="dng-node__ring" r="23" />
              <text class="dng-node__glyph" text-anchor="middle" dy="0.36em">{n.glyph}</text>
              <text class="dng-node__label" text-anchor="middle" y="30">{n.name}</text>
              <circle
                :if={n.state == :reachable}
                class="dng-node__hit"
                r="26"
                phx-click="select_node"
                phx-value-id={n.id}
              />
            </g>
          </g>

          <g class="dng-party" transform={"translate(#{@view.party_x} #{@view.party_y})"}>
            <circle class="dng-party__pulse" r="17" />
            <circle class="dng-party__core" r="9" />
            <text class="dng-party__sigil" text-anchor="middle" dy="0.34em">✦</text>
          </g>
        </svg>
      </div>

      <footer class="dng-lvl-foot">
        <span class="dng-foot-ctx">Башня · вход на ярус {@level}</span>
        <button type="button" class="dng-breathe-btn" phx-click="shift_moves" disabled={@shifted}>
          прислушаться к подземелью
        </button>
      </footer>

      <%= if @confirm do %>
        <div class="dng-sheet-scrim" phx-click="cancel_move"></div>
        <div class="dng-sheet" role="dialog" aria-label={@confirm.title}>
          <p class="dng-sheet__title">{@confirm.title}</p>
          <p class="dng-sheet__name">{@confirm.name}</p>
          <p class="dng-sheet__hint">{@confirm.hint}</p>
          <div class="dng-sheet__acts">
            <button type="button" class="dng-btn dng-btn--ghost" phx-click="cancel_move">
              Остаться
            </button>
            <button
              type="button"
              class="dng-btn dng-btn--go"
              phx-click="confirm_move"
              phx-value-id={@confirm.id}
            >
              Идти
            </button>
          </div>
        </div>
      <% end %>

      <%= if @legend_open do %>
        <div class="dng-sheet-scrim" phx-click="toggle_legend"></div>
        <div class="dng-legend" role="dialog" aria-label="Легенда карты">
          <p class="dng-legend__title">Условные знаки</p>
          <ul class="dng-legend__list">
            <li :for={{type, glyph, meaning} <- legend_entries()} class="dng-legend__row">
              <span class={["dng-legend__glyph", "dng-node--t-#{node_slug(type)}"]}>
                {glyph}
              </span>
              <span class="dng-legend__meaning">{meaning}</span>
            </li>
          </ul>
          <div class="dng-legend__states">
            <span><i class="dng-swatch dng-swatch--visited"></i> пройдено</span>
            <span><i class="dng-swatch dng-swatch--reachable"></i> доступно</span>
            <span><i class="dng-swatch dng-swatch--known"></i> известно</span>
            <span><i class="dng-swatch dng-swatch--fog"></i> во тьме</span>
          </div>
          <button
            type="button"
            class="dng-btn dng-btn--ghost dng-legend__close"
            phx-click="toggle_legend"
          >
            Закрыть
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dng-screen dng-screen--depths">
      <div class="dng-depths-grain"></div>

      <header class="dng-head">
        <div class="dng-head__art">
          <.art_slot
            kind="banner"
            label="Врата подземелья — зев Бездны под Башней"
          />
          <div class="dng-head__art-veil"></div>
        </div>
        <.link navigate={~p"/map"} class="dng-exit">← выйти к Башне</.link>
        <div class="dng-head__frame">
          <span class="dng-head__kicker">Врата подземелья · Башня</span>
          <h1 class="dng-head__title">Разрез Бездны</h1>
          <p class="dng-head__sub">
            Мега-подземелье уходит вниз семью ярусами — каждый глубже, темнее и чужероднее.
          </p>
        </div>

        <div class="dng-party-status" role="group" aria-label="Состояние отряда">
          <span class="dng-chip dng-chip--hp">
            <span class="dng-chip__k">Общее HP</span>
            <span class="dng-chip__v">148 / 220</span>
          </span>
          <span class="dng-chip dng-chip--food">
            <span class="dng-chip__k">Припасы</span>
            <span class="dng-chip__v">6 дней</span>
          </span>
          <span class="dng-chip dng-chip--ritual">
            <span class="dng-chip__k">Ритуал Возврата</span>
            <span class="dng-chip__v">готов ·  требует 3 хода</span>
          </span>
        </div>
      </header>

      <div class="dng-strata">
        <div
          :for={lvl <- @levels}
          class={[
            "dng-stratum",
            "dng-stratum--#{lvl.state}",
            Map.get(lvl, :party) && "dng-stratum--here"
          ]}
          style={"--depth: #{lvl.n};"}
        >
          <div class="dng-stratum__rail">
            <span class="dng-stratum__num">{roman(lvl.n)}</span>
            <span :if={Map.get(lvl, :party)} class="dng-stratum__pin dng-stratum__pin--party">
              отряд ✦
            </span>
            <span :if={Map.get(lvl, :deepest)} class="dng-stratum__pin dng-stratum__pin--deep">
              предел ↧
            </span>
          </div>

          <div class="dng-stratum__body">
            <%= if lvl.state == :fogged do %>
              <p class="dng-stratum__fog-name">Уровень {lvl.n} — неизведано</p>
              <p class="dng-stratum__fog-hint">
                купите карту у гильдии картографов или спуститесь и начертите её сами
              </p>
            <% else %>
              <div class="dng-stratum__heading">
                <h2 class="dng-stratum__name">
                  Уровень {lvl.n} — {lvl.name}
                </h2>
                <span :if={lvl.state == :map} class="dng-badge dng-badge--map">
                  карта куплена · не пройдено
                </span>
                <span :if={lvl.state == :visited} class="dng-badge dng-badge--seen">
                  пройдено
                </span>
              </div>
              <p class="dng-stratum__epithet">{lvl.epithet}</p>
              <div class="dng-facts">
                <span class="dng-fact"><i>опасность</i> {lvl.danger}</span>
                <span class="dng-fact">
                  <i>деревня</i> {lvl.village || "нет"}
                </span>
                <span class="dng-fact"><i>подъёмы</i> {lvl.ascents}</span>
              </div>
              <p :if={lvl[:note]} class="dng-stratum__note">{lvl.note}</p>
              <.link navigate={~p"/dungeon/level/#{lvl.n}"} class="dng-stratum__enter">
                открыть карту яруса ›
              </.link>
            <% end %>
          </div>
        </div>
      </div>

      <p class="dng-depths-foot">
        Жизнь в подземелье — это экспедиция: припасы, ремонт снаряжения и хотя бы один
        заклинатель для Ритуала Возврата. Наверх ведут постоянные подъёмы или ритуал.
      </p>
    </div>
    """
  end

  # ── Render helpers ────────────────────────────────────────────────────
  defp level_title(1), do: "Верхние галереи"
  defp level_title(2), do: "Грибные топи"
  defp level_title(n), do: "ярус #{n}"

  defp node_slug("подъём"), do: "up"
  defp node_slug("спуск"), do: "down"
  defp node_slug("бой"), do: "fight"
  defp node_slug("находка"), do: "loot"
  defp node_slug("стоянка"), do: "rest"
  defp node_slug("деревня"), do: "village"
  defp node_slug("аномалия"), do: "anomaly"
  defp node_slug("?"), do: "unknown"

  defp legend_entries do
    [
      {"бой", "⚔", "логово тварей — бой"},
      {"находка", "◈", "тайник — добыча"},
      {"стоянка", "▲", "привал — передышка"},
      {"деревня", "⌂", "деревенька делверов — полубезопасный узел"},
      {"подъём", "↑", "постоянный подъём на поверхность"},
      {"спуск", "↓", "проход на следующий ярус"},
      {"аномалия", "✳", "аномалия — событие подземелья"},
      {"?", "?", "неизведанный ход"}
    ]
  end

  defp roman(1), do: "I"
  defp roman(2), do: "II"
  defp roman(3), do: "III"
  defp roman(4), do: "IV"
  defp roman(5), do: "V"
  defp roman(6), do: "VI"
  defp roman(7), do: "VII"
  defp roman(n), do: to_string(n)
end
