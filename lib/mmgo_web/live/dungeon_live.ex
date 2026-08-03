defmodule MMGOWeb.DungeonLive do
  @moduledoc """
  Scoped browser surface for an active party expedition beneath the Tower.

  Every action is delegated to `MMGO.Play`, which re-resolves the current
  expedition, node, encounter, loot, and resource from persisted state.
  """
  use MMGOWeb, :live_view

  alias MMGO.{Dungeons, Play}

  @graph_width 340
  @graph_padding_x 52
  @graph_padding_y 58
  @graph_row_pitch 104

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Подземелье")
     |> assign(:error, nil)
     |> assign(:level, parse_level(params["level"]))
     |> assign(:level_view, nil)
     |> assign(:confirm_move, nil)
     |> assign(:legend_open, false)
     |> refresh_dungeon()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :level ->
        level = parse_level(params["level"])

        {:noreply,
         socket
         |> assign(:page_title, "Карта яруса #{level}")
         |> assign(:level, level)
         |> assign(:confirm_move, nil)
         |> assign(:legend_open, false)
         |> assign_level_view()}

      _depths ->
        {:noreply,
         socket
         |> assign(:page_title, "Подземелье")
         |> assign(:confirm_move, nil)
         |> assign(:legend_open, false)
         |> assign(:level_view, nil)}
    end
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
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:confirm_move, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("preview_move", %{"node-id" => node_id}, socket) do
    case Enum.find(socket.assigns.state.reachable_nodes, &(&1.node.id == node_id)) do
      nil ->
        {:noreply, assign(socket, :error, error_message(:dungeon_node_unavailable))}

      %{node: node, travel_cost: travel_cost} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:legend_open, false)
         |> assign(:confirm_move, %{
           id: node.id,
           name: node.name,
           kind: node_kind_label(node.kind),
           travel_cost: travel_cost
         })}
    end
  end

  @impl true
  def handle_event("cancel_move", _params, socket) do
    {:noreply, assign(socket, :confirm_move, nil)}
  end

  @impl true
  def handle_event("toggle_legend", _params, socket) do
    {:noreply,
     socket
     |> assign(:confirm_move, nil)
     |> assign(:legend_open, not socket.assigns.legend_open)}
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
  def render(%{live_action: :level} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main
        id="dungeon-level-screen"
        class={[
          "dng-screen",
          "dng-screen--graph",
          @level > 1 && "dng-screen--deep"
        ]}
      >
        <div class="dng-graph-grain"></div>

        <header class="dng-lvl-head">
          <.link id="dungeon-level-back" navigate={~p"/dungeon"} class="dng-exit">
            ← к вратам
          </.link>
          <div class="dng-lvl-title">
            <span class="dng-lvl-kicker">экспедиционная карта</span>
            <h1 class="dng-lvl-name">
              Ярус {@level}
              <%= if @level_view && @level_view.floor do %>
                · {@level_view.floor.name}
              <% end %>
            </h1>
          </div>
          <button
            id="dungeon-toggle-legend"
            type="button"
            class="dng-legend-btn"
            phx-click="toggle_legend"
          >
            {if @legend_open, do: "закрыть", else: "условные знаки"}
          </button>
        </header>

        <div :if={@error} id="dungeon-error" class="dng-live-error dng-level-error">
          <span>☒</span> {@error}
        </div>

        <section
          :if={is_nil(@state.run)}
          id="dungeon-level-sealed"
          class="dng-map-sealed"
        >
          <span class="dng-map-sealed__seal">⌄</span>
          <p class="dng-live-kicker">полевая карта не начата</p>
          <h2>Сначала войдите в Подземелье</h2>
          <p>
            Чистый лист получает настоящие узлы и проходы только после начала экспедиции.
          </p>
          <.link navigate={~p"/dungeon"} class="dng-btn dng-btn--go">
            Вернуться к вратам
          </.link>
        </section>

        <section
          :if={@state.run && (is_nil(@level_view) || is_nil(@level_view.floor))}
          id="dungeon-level-unknown"
          class="dng-map-sealed"
        >
          <span class="dng-map-sealed__seal">?</span>
          <p class="dng-live-kicker">лист без отметок</p>
          <h2>Этот ярус не найден</h2>
          <p>
            В журнале текущего Подземелья нет яруса с таким номером.
          </p>
          <.link navigate={~p"/dungeon"} class="dng-btn dng-btn--ghost">
            Свериться у врат
          </.link>
        </section>

        <%= if @state.run && @level_view && @level_view.floor do %>
          <aside id="dungeon-level-field-note" class="dng-field-note">
            <div>
              <span>отряд</span>
              <strong>{@state.party.name}</strong>
            </div>
            <div>
              <span>шагов</span>
              <strong>{@state.run.steps_taken}</strong>
            </div>
            <div>
              <span>положение</span>
              <strong id="dungeon-level-current-node">
                {if @level_view.party,
                  do: @state.current_node.name,
                  else: "на другом ярусе"}
              </strong>
            </div>
          </aside>

          <section id="dungeon-level-map" class="dng-chart-sheet">
            <div class="dng-chart-sheet__pin dng-chart-sheet__pin--left"></div>
            <div class="dng-chart-sheet__pin dng-chart-sheet__pin--right"></div>
            <p class="dng-chart-sheet__caption">
              Снято с текущего состояния похода · пунктир уходит в неразведанную темноту
            </p>

            <div
              :if={@level_view.nodes == []}
              id="dungeon-level-empty-map"
              class="dng-chart-sheet__empty"
            >
              На этом листе пока нет разведанных отметок.
            </div>

            <div :if={@level_view.nodes != []} class="dng-graph-scroll">
              <svg
                class="dng-graph"
                viewBox={"0 0 #{@level_view.width} #{@level_view.height}"}
                preserveAspectRatio="xMidYMin meet"
                role="img"
                aria-label={"Разведанная карта яруса #{@level}"}
              >
                <defs>
                  <filter id="dng-live-ink" x="-20%" y="-20%" width="140%" height="140%">
                    <feTurbulence
                      type="fractalNoise"
                      baseFrequency="0.018"
                      numOctaves="2"
                      seed="7"
                      result="noise"
                    />
                    <feDisplacementMap in="SourceGraphic" in2="noise" scale="3" />
                  </filter>
                </defs>

                <g class="dng-edges" filter="url(#dng-live-ink)">
                  <line
                    :for={edge <- @level_view.edges}
                    id={"dungeon-edge-#{edge.id}"}
                    x1={edge.x1}
                    y1={edge.y1}
                    x2={edge.x2}
                    y2={edge.y2}
                    class={[
                      "dng-edge",
                      "dng-edge--#{edge.kind}",
                      edge.reachable? && "dng-edge--reachable"
                    ]}
                  />
                </g>

                <g class="dng-nodes">
                  <g
                    :for={node <- @level_view.nodes}
                    id={"dungeon-graph-node-#{node.id}"}
                    class={[
                      "dng-node",
                      "dng-node--#{node.state}",
                      "dng-node--t-#{node_type_slug(node.kind)}"
                    ]}
                    transform={"translate(#{node.x} #{node.y})"}
                  >
                    <title>
                      {node.name} · {node_kind_label(node.kind)}
                    </title>
                    <circle class="dng-node__disc" r="18" />
                    <circle
                      :if={node.state == :reachable}
                      class="dng-node__ring"
                      r="24"
                    />
                    <text class="dng-node__glyph" text-anchor="middle" dy="0.36em">
                      {node_glyph(node.kind)}
                    </text>
                    <text class="dng-node__label" text-anchor="middle" y="33">
                      {map_node_label(node.name)}
                    </text>
                    <circle
                      :if={node.state == :reachable}
                      id={"dungeon-graph-move-#{node.id}"}
                      class="dng-node__hit"
                      r="29"
                      role="button"
                      tabindex="0"
                      aria-label={"Наметить переход: #{node.name}"}
                      phx-click="preview_move"
                      phx-value-node-id={node.id}
                    />
                  </g>
                </g>

                <g
                  :if={@level_view.party}
                  id="dungeon-party-marker"
                  class="dng-party"
                  transform={"translate(#{@level_view.party.x} #{@level_view.party.y})"}
                >
                  <circle class="dng-party__pulse" r="18" />
                  <circle class="dng-party__core" r="9" />
                  <text class="dng-party__sigil" text-anchor="middle" dy="0.34em">✦</text>
                </g>
              </svg>
            </div>

            <p class="dng-chart-sheet__signature">
              отметки нанесены углём и железными чернилами
            </p>
          </section>

          <footer class="dng-lvl-foot">
            <span class="dng-foot-ctx">
              {length(@level_view.nodes)} отметок · {length(@level_view.edges)} проходов
            </span>
            <button
              id="dungeon-refresh-map"
              type="button"
              class="dng-breathe-btn"
              phx-click="refresh"
            >
              сверить смещение ходов
            </button>
          </footer>
        <% end %>

        <%= if @confirm_move do %>
          <div
            id="dungeon-move-scrim"
            class="dng-sheet-scrim"
            phx-click="cancel_move"
          >
          </div>
          <section
            id="dungeon-move-sheet"
            class="dng-sheet"
            role="dialog"
            aria-modal="true"
            aria-labelledby="dungeon-move-sheet-title"
          >
            <p class="dng-sheet__eyebrow">маршрутная приписка</p>
            <h2 id="dungeon-move-sheet-title" class="dng-sheet__name">
              {@confirm_move.name}
            </h2>
            <p class="dng-sheet__hint">
              {node_kind_label(@confirm_move.kind)} · цена перехода {@confirm_move.travel_cost}
            </p>
            <p class="dng-sheet__warning">
              Переход изменит настоящее состояние похода и расход припасов.
            </p>
            <div class="dng-sheet__acts">
              <button
                id="dungeon-cancel-move"
                type="button"
                class="dng-btn dng-btn--ghost"
                phx-click="cancel_move"
              >
                Остаться
              </button>
              <button
                id="dungeon-confirm-move"
                type="button"
                class="dng-btn dng-btn--go"
                phx-click="move"
                phx-value-node-id={@confirm_move.id}
              >
                Идти
              </button>
            </div>
          </section>
        <% end %>

        <%= if @legend_open do %>
          <div
            id="dungeon-legend-scrim"
            class="dng-sheet-scrim"
            phx-click="toggle_legend"
          >
          </div>
          <section
            id="dungeon-legend"
            class="dng-legend"
            role="dialog"
            aria-modal="true"
            aria-labelledby="dungeon-legend-title"
          >
            <p class="dng-sheet__eyebrow">полевая памятка</p>
            <h2 id="dungeon-legend-title" class="dng-legend__title">
              Условные знаки
            </h2>
            <ul class="dng-legend__list">
              <li
                :for={{kind, glyph, meaning} <- legend_entries()}
                class="dng-legend__row"
              >
                <span class={[
                  "dng-legend__glyph",
                  "dng-node--t-#{node_type_slug(kind)}"
                ]}>
                  {glyph}
                </span>
                <span class="dng-legend__meaning">{meaning}</span>
              </li>
            </ul>
            <div class="dng-legend__states">
              <span><i class="dng-swatch dng-swatch--visited"></i> пройдено</span>
              <span><i class="dng-swatch dng-swatch--reachable"></i> доступно сейчас</span>
              <span><i class="dng-swatch dng-swatch--known"></i> замечено</span>
              <span><i class="dng-swatch dng-swatch--fog"></i> уходит во тьму</span>
              <span><i class="dng-swatch dng-swatch--blocked"></i> ход закрыт</span>
            </div>
            <button
              id="dungeon-close-legend"
              type="button"
              class="dng-btn dng-btn--ghost dng-legend__close"
              phx-click="toggle_legend"
            >
              Свернуть памятку
            </button>
          </section>
        <% end %>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main id="dungeon-screen" class="dng-screen dng-screen--depths dng-screen--live">
        <div class="dng-depths-grain"></div>
        <div class="dng-live-shell">
          <nav class="dng-live-nav" aria-label="Навигация экспедиции">
            <.link
              id="dungeon-back-to-party"
              navigate={~p"/party"}
              class="dng-exit dng-exit--live"
            >
              ← Отряд
            </.link>
            <button
              id="dungeon-refresh"
              type="button"
              phx-click="refresh"
              class="dng-refresh"
            >
              ↻ перечитать карту
            </button>
          </nav>

          <header class="dng-head dng-head--live">
            <div class="dng-live-gate" aria-hidden="true">
              <span class="dng-live-gate__torch"></span>
              <span class="dng-live-gate__arch"></span>
              <span class="dng-live-gate__stairs"></span>
            </div>
            <div class="dng-head__frame">
              <p class="dng-head__kicker">
                экспедиция · подземелье
              </p>
              <h1 class="dng-head__title">{dungeon_title(@state)}</h1>
              <p class="dng-head__sub">{dungeon_subtitle(@state)}</p>
            </div>
          </header>

          <div
            :if={@error}
            id="dungeon-error"
            class="dng-live-error"
          >
            <span>☒</span> {@error}
          </div>

          <section
            :if={is_nil(@state.expedition)}
            id="dungeon-no-expedition"
            class="dng-live-empty"
          >
            <span class="dng-live-empty__glyph">⌂</span>
            <h2>Сначала соберите экспедицию</h2>
            <p>
              В Подземелье входит активный отряд, собранный у врат Башни.
            </p>
            <.link
              id="dungeon-form-party"
              navigate={~p"/party"}
              class="dng-btn dng-btn--go"
            >
              Открыть отряд
            </.link>
          </section>

          <section
            :if={@state.expedition}
            id="dungeon-expedition"
            class="dng-manifest"
          >
            <article class="dng-manifest__party">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="dng-live-kicker">состав экспедиции</p>
                  <h2 class="dng-live-title">{@state.party.name}</h2>
                </div>
                <span
                  id="dungeon-run-status"
                  class="dng-badge dng-badge--seen"
                >
                  {run_status(@state.run)}
                </span>
              </div>
              <ul id="dungeon-members" class="dng-manifest__members">
                <li
                  :for={member <- @state.members}
                  id={"dungeon-member-#{member.character_id}"}
                  class="dng-manifest__member"
                >
                  <span>{member.character.name}</span>
                  <span>ур. {member.character.level}</span>
                </li>
              </ul>
              <div
                id="dungeon-loot-policy"
                class="dng-policy-note"
              >
                <p class="dng-live-kicker">делёж добычи</p>
                <p id="dungeon-loot-policy-value" class="dng-policy-note__value">
                  {loot_policy_label(@state.loot_policy)}
                </p>
                <p id="dungeon-loot-policy-note" class="dng-policy-note__copy">
                  Это договорённость отряда: доступный трофей технически может взять любой участник.
                </p>
              </div>
            </article>

            <article
              id="dungeon-supplies"
              class="dng-supply-ledger"
            >
              <p class="dng-live-kicker">припасы</p>
              <%= if @state.survival do %>
                <p id="dungeon-survival-food" class="dng-supply-ledger__value">
                  {@state.survival.food_units_remaining}
                </p>
                <p class="dng-supply-ledger__line">
                  ед. еды из {@state.survival.food_units_initial} на старте · расход {@state.survival.food_units_consumed}
                </p>
                <p id="dungeon-survival-carry" class="dng-supply-ledger__weight">
                  Вес: {@state.survival.carried_weight} / {@state.survival.carry_capacity}
                </p>
                <p
                  :if={@state.survival.encumbered?}
                  id="dungeon-overloaded"
                  class="dng-warning"
                >
                  Перегруз удваивает стоимость каждого перехода.
                </p>
                <p
                  :if={
                    @state.survival.food_units_remaining == 0 and
                      @state.survival.foodless_game_days == 0
                  }
                  id="dungeon-starvation-risk"
                  class="dng-warning"
                >
                  Рационы закончились: следующий переход займёт больше времени.
                </p>
                <p
                  :if={@state.survival.foodless_game_days > 0}
                  id="dungeon-starvation-risk"
                  class="dng-warning dng-warning--danger"
                >
                  <%= if @state.survival.shared_hp_drain > 0 do %>
                    Без еды уже {@state.survival.foodless_game_days} игровых дней: перед следующим боем отряд потеряет {@state.survival.shared_hp_drain} общего здоровья.
                  <% else %>
                    Без еды уже {@state.survival.foodless_game_days} игровых дней: следующий переход усилит истощение.
                  <% end %>
                </p>
              <% else %>
                <p class="dng-supply-ledger__value">
                  {@state.supply.total_food_units}
                </p>
                <p class="dng-supply-ledger__line">
                  ед. еды · около {@state.supply.projected_days} игровых дней
                </p>
                <p class="dng-supply-ledger__weight">
                  Вес: {@state.supply.total_carried_weight} / {@state.supply.total_carry_capacity}
                </p>
              <% end %>
            </article>

            <article
              :if={is_map(@state.route_plan)}
              id="dungeon-route-plan"
              class="dng-route-folio"
            >
              <p class="dng-live-kicker">маршрутный план</p>
              <p id="dungeon-route-plan-status" class="dng-live-title">
                {route_plan_status(@state.route_plan)}
              </p>
              <p class="dng-route-folio__copy">
                {route_plan_description(@state.route_plan)}
              </p>
            </article>
          </section>

          <section
            :if={@state.expedition && is_nil(@state.run)}
            id="dungeon-entry"
            class="dng-entry-gate"
          >
            <span class="dng-entry-gate__mark">⌄</span>
            <h2>Врата</h2>
            <p>
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
              class="dng-btn dng-btn--go"
            >
              Войти в Подземелье
            </button>
            <p
              :if={@state.entry_dungeon && not @state.can_enter?}
              id="dungeon-entry-waiting"
              class="dng-entry-gate__waiting"
            >
              Вход открывает лидер отряда.
            </p>
          </section>

          <section :if={@state.run} id="dungeon-run" class="dng-live-run">
            <article
              id="dungeon-current-node"
              class="dng-node-chamber"
            >
              <div class="dng-node-chamber__head">
                <span class="dng-node-chamber__sigil">
                  {node_glyph(@state.current_node.kind)}
                </span>
                <div>
                  <p class="dng-live-kicker">текущий узел</p>
                  <h2>{@state.current_node.name}</h2>
                  <p class="dng-node-chamber__meta">
                    {node_kind_label(@state.current_node.kind)} · шагов в походе: {@state.run.steps_taken}
                  </p>
                </div>
              </div>

              <div
                :if={@state.current_encounter}
                id="dungeon-encounter"
                class="dng-chamber-case dng-chamber-case--danger"
              >
                <p class="dng-live-kicker">встреча</p>
                <h3>
                  {encounter_label(@state.current_encounter)}
                </h3>
                <p>
                  Угроза: {@state.current_encounter.threat_level} · {encounter_status(
                    @state.current_encounter.status
                  )}
                </p>
                <div class="dng-chamber-actions">
                  <button
                    :if={@state.can_start_combat?}
                    id="dungeon-start-combat"
                    type="button"
                    phx-click="start_combat"
                    class="dng-btn dng-btn--danger"
                  >
                    Начать бой
                  </button>
                  <button
                    :if={@state.can_avoid_encounter?}
                    id="dungeon-avoid-encounter"
                    type="button"
                    phx-click="avoid"
                    class="dng-btn dng-btn--ghost"
                  >
                    Обойти встречу
                  </button>
                  <.link
                    :if={@state.active_combat && @state.active_combat.status != :finished}
                    id="dungeon-open-combat"
                    navigate={~p"/combat/#{@state.active_combat.id}"}
                    class="dng-btn dng-btn--danger"
                  >
                    Вернуться к бою
                  </.link>
                  <button
                    :if={@state.active_combat && @state.active_combat.status == :finished}
                    id="dungeon-sync-combat"
                    type="button"
                    phx-click="sync_combat"
                    class="dng-btn dng-btn--go"
                  >
                    Применить итог боя
                  </button>
                </div>
              </div>

              <div
                :if={@state.available_resources != []}
                id="dungeon-resources"
                class="dng-chamber-case dng-chamber-case--resource"
              >
                <h3>Ресурсы узла</h3>
                <p id="dungeon-scavenging-time">
                  Осмотр каждого ресурса занимает 1 игровой день и даёт до 3 опыта каждому участнику отряда.
                </p>
                <article
                  :for={resource <- @state.available_resources}
                  id={"dungeon-resource-#{resource.id}"}
                  class="dng-find-row"
                >
                  <span>{resource_label(resource)} · осталось {resource.quantity_remaining}</span>
                  <button
                    id={"dungeon-harvest-#{resource.id}"}
                    type="button"
                    phx-click="harvest"
                    phx-value-resource-id={resource.id}
                    class="dng-btn dng-btn--ghost"
                  >
                    Собрать 1 · 1 игровой день
                  </button>
                </article>
              </div>

              <div
                :if={@state.available_loot != []}
                id="dungeon-loot"
                class="dng-chamber-case dng-chamber-case--loot"
              >
                <h3>Добыча</h3>
                <article
                  :for={loot <- @state.available_loot}
                  id={"dungeon-loot-#{loot.id}"}
                  class="dng-find-row"
                >
                  <span>{loot_label(loot)} · ×{loot.amount}</span>
                  <button
                    id={"dungeon-claim-#{loot.id}"}
                    type="button"
                    phx-click="claim_loot"
                    phx-value-loot-drop-id={loot.id}
                    class="dng-btn dng-btn--ghost"
                  >
                    Взять
                  </button>
                </article>
              </div>

              <div
                id="dungeon-return-ritual-readiness"
                class="dng-chamber-case dng-chamber-case--ritual"
              >
                <p class="dng-live-kicker">
                  ритуал возвращения
                </p>
                <%= cond do %>
                  <% not @state.return_ritual.wizardry_specialist? -> %>
                    <p>
                      Нужна активная специализация волшебника.
                    </p>
                  <% not @state.return_ritual.active_grimoire? -> %>
                    <p>
                      Нужен активный гримуар с подготовленной формулой возвращения.
                    </p>
                  <% @state.return_ritual.prepared? -> %>
                    <p
                      id="dungeon-return-ritual-prepared"
                      class="dng-ritual-ready"
                    >
                      Подготовлена формула: {@state.return_ritual.prepared_spell_name}.
                    </p>
                  <% true -> %>
                    <p>
                      В активном гримуаре нет подготовленного Ритуала возвращения.
                    </p>
                <% end %>
              </div>

              <div class="dng-chamber-actions dng-chamber-actions--exit">
                <button
                  :if={@state.can_extract?}
                  id="dungeon-extract"
                  type="button"
                  phx-click="extract"
                  class="dng-btn dng-btn--go"
                >
                  Подняться к Башне
                </button>
                <button
                  :if={@state.can_return_ritual?}
                  id="dungeon-return-ritual"
                  type="button"
                  phx-click="return_ritual"
                  class="dng-btn dng-btn--ghost"
                >
                  Начать ритуал возвращения
                </button>
                <p
                  :if={@state.active_extraction}
                  id="dungeon-active-extraction"
                  class="dng-ritual-active"
                >
                  Ритуал активен до {format_time(@state.active_extraction.completes_at)}.
                </p>
              </div>
            </article>

            <section
              id="dungeon-map"
              class="dng-live-chart"
            >
              <div class="dng-live-chart__head">
                <div>
                  <p class="dng-live-kicker">разведанная карта</p>
                  <h2>Соседние проходы</h2>
                </div>
                <div class="dng-live-chart__tools">
                  <span>
                    Неизведанное открывается только у текущего узла.
                  </span>
                  <.link
                    id="dungeon-open-level-map"
                    navigate={~p"/dungeon/level/#{current_floor_number(@state)}"}
                    class="dng-chart-unfold"
                  >
                    развернуть карту яруса ↗
                  </.link>
                </div>
              </div>
              <div class="dng-live-chart__nodes">
                <article
                  :for={row <- @state.nodes}
                  id={"dungeon-node-#{row.node.id}"}
                  class={node_card_class(row)}
                >
                  <span class="dng-node-card__glyph">{node_glyph(row.node.kind)}</span>
                  <div class="dng-node-card__copy">
                    <p>{node_kind_label(row.node.kind)}</p>
                    <h3>{row.node.name}</h3>
                    <small>{node_progress_label(row)}</small>
                  </div>
                  <button
                    :if={row.reachable?}
                    id={"dungeon-move-#{row.node.id}"}
                    type="button"
                    phx-click="move"
                    phx-value-node-id={row.node.id}
                    class="dng-node-card__move"
                  >
                    идти ›
                  </button>
                </article>
              </div>
            </section>
          </section>
          <p class="dng-depths-foot">
            Подземелье хранит каждый шаг: припасы, добычу, открытые ходы и цену возвращения.
          </p>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp assign_level_view(%{assigns: %{live_action: :level, state: state, level: level}} = socket) do
    assign(socket, :level_view, build_level_view(state, level))
  end

  defp assign_level_view(socket), do: assign(socket, :level_view, nil)

  defp build_level_view(%{run: nil}, _level), do: nil

  defp build_level_view(state, level) do
    floor = Enum.find(dungeon_floors(state.dungeon), &(&1.number == level))

    if floor do
      floor_nodes = if is_list(floor.nodes), do: floor.nodes, else: []
      node_by_id = Map.new(floor_nodes, &{&1.id, &1})
      positions = graph_positions(floor_nodes)

      rows =
        state.nodes
        |> Enum.filter(&(&1.node.floor_id == floor.id))

      known_ids = rows |> Enum.map(& &1.node.id) |> MapSet.new()

      reachable =
        state.reachable_nodes
        |> Enum.filter(&(&1.node.floor_id == floor.id))
        |> Map.new(&{&1.node.id, &1})

      reachable_ids = reachable |> Map.keys() |> MapSet.new()
      current_id = state.current_node.id

      nodes =
        Enum.map(rows, fn row ->
          position = Map.fetch!(positions, row.node.id)

          node_state =
            cond do
              row.node.id == current_id -> :party
              MapSet.member?(reachable_ids, row.node.id) -> :reachable
              row.node_state -> :visited
              true -> :known
            end

          %{
            id: row.node.id,
            name: row.node.name,
            kind: row.node.kind,
            x: position.x,
            y: position.y,
            state: node_state
          }
        end)

      link_statuses =
        state.dungeon.id
        |> Dungeons.list_link_states()
        |> Map.new(&{&1.link_id, &1.status})

      edges =
        state.dungeon.id
        |> Dungeons.list_links_for_dungeon()
        |> Enum.filter(
          &(Map.has_key?(node_by_id, &1.from_node_id) and
              Map.has_key?(node_by_id, &1.to_node_id))
        )
        |> Enum.map(
          &build_graph_edge(
            &1,
            Map.get(link_statuses, &1.id, :active),
            positions,
            known_ids,
            reachable_ids,
            current_id
          )
        )
        |> Enum.reject(&is_nil/1)

      party =
        if state.current_node.floor_id == floor.id do
          Map.get(positions, state.current_node.id)
        end

      %{
        floor: floor,
        width: @graph_width,
        height: graph_height(floor_nodes),
        nodes: nodes,
        edges: edges,
        party: party
      }
    else
      %{floor: nil, width: @graph_width, height: 260, nodes: [], edges: [], party: nil}
    end
  end

  defp build_graph_edge(
         link,
         status,
         positions,
         known_ids,
         reachable_ids,
         current_id
       ) do
    from_known? = MapSet.member?(known_ids, link.from_node_id)
    to_known? = MapSet.member?(known_ids, link.to_node_id)

    cond do
      not from_known? and not to_known? ->
        nil

      status == :blocked and not (from_known? and to_known?) ->
        nil

      true ->
        from = Map.fetch!(positions, link.from_node_id)
        to = Map.fetch!(positions, link.to_node_id)

        {x1, y1, x2, y2, kind} =
          cond do
            status == :blocked ->
              {from.x, from.y, to.x, to.y, :blocked}

            from_known? and to_known? ->
              {from.x, from.y, to.x, to.y, :solid}

            from_known? ->
              {from.x, from.y, trail_coordinate(from.x, to.x), trail_coordinate(from.y, to.y),
               :trail}

            true ->
              {to.x, to.y, trail_coordinate(to.x, from.x), trail_coordinate(to.y, from.y), :trail}
          end

        %{
          id: link.id,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          kind: kind,
          reachable?:
            status == :active and
              ((link.from_node_id == current_id and
                  MapSet.member?(reachable_ids, link.to_node_id)) or
                 (link.to_node_id == current_id and
                    MapSet.member?(reachable_ids, link.from_node_id)))
        }
    end
  end

  defp trail_coordinate(origin, destination), do: origin + (destination - origin) * 0.58

  defp graph_positions(nodes) do
    x_values = nodes |> Enum.map(& &1.x) |> Enum.uniq() |> Enum.sort()
    y_values = nodes |> Enum.map(& &1.y) |> Enum.uniq() |> Enum.sort()

    x_positions =
      axis_positions(x_values, @graph_padding_x, @graph_width - @graph_padding_x)

    y_positions =
      y_values
      |> Enum.with_index()
      |> Map.new(fn {value, index} -> {value, @graph_padding_y + index * @graph_row_pitch} end)

    Map.new(nodes, fn node ->
      {node.id, %{x: Map.fetch!(x_positions, node.x), y: Map.fetch!(y_positions, node.y)}}
    end)
  end

  defp axis_positions([], _start, _finish), do: %{}

  defp axis_positions([value], start, finish),
    do: %{value => div(start + finish, 2)}

  defp axis_positions(values, start, finish) do
    intervals = length(values) - 1

    values
    |> Enum.with_index()
    |> Map.new(fn {value, index} ->
      {value, start + div((finish - start) * index, intervals)}
    end)
  end

  defp graph_height(nodes) do
    row_count = nodes |> Enum.map(& &1.y) |> Enum.uniq() |> length()
    max(260, @graph_padding_y * 2 + max(row_count - 1, 0) * @graph_row_pitch)
  end

  defp dungeon_floors(%{floors: floors}) when is_list(floors), do: floors
  defp dungeon_floors(_dungeon), do: []

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
      |> assign_level_view()

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
    "Первая победа в этом походе принесёт отряду на #{div(bonus_bps, 100)}% больше опыта."
  end

  defp route_plan_description(%{"status" => "consumed", "xp_awarded" => xp_awarded}) do
    "План уже сработал и добавил #{xp_awarded} опыта к первой победе."
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
  defp encounter_status(_status), do: "состояние неизвестно"

  defp resource_label(resource),
    do: (resource.item_template && resource.item_template.name) || resource.resource_code

  defp loot_label(%{reward_kind: :currency}), do: "Монеты"
  defp loot_label(loot), do: (loot.item_template && loot.item_template.name) || "Трофей"

  defp loot_policy_label("leader"), do: "Решает лидер"
  defp loot_policy_label("free_for_all"), do: "Первый взял"
  defp loot_policy_label(_policy), do: "По кругу"

  defp format_time(nil), do: "неизвестного часа"
  defp format_time(datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp parse_level(nil), do: 1

  defp parse_level(value) do
    case Integer.parse(to_string(value)) do
      {level, ""} when level > 0 -> level
      _other -> 1
    end
  end

  defp current_floor_number(%{current_node: %{floor_id: floor_id}, dungeon: dungeon}) do
    case Enum.find(dungeon_floors(dungeon), &(&1.id == floor_id)) do
      nil -> 1
      floor -> floor.number
    end
  end

  defp current_floor_number(_state), do: 1

  defp map_node_label(name) when is_binary(name) do
    if String.length(name) > 22 do
      String.slice(name, 0, 21) <> "…"
    else
      name
    end
  end

  defp node_type_slug(:entrance), do: "up"
  defp node_type_slug(:room), do: "chamber"
  defp node_type_slug(:rest), do: "rest"
  defp node_type_slug(:hazard), do: "anomaly"
  defp node_type_slug(:boss), do: "fight"
  defp node_type_slug(:stairs_up), do: "up"
  defp node_type_slug(:stairs_down), do: "down"
  defp node_type_slug(:exit), do: "exit"
  defp node_type_slug(_kind), do: "unknown"

  defp legend_entries do
    [
      {:entrance, "↑", "вход или постоянный подъём"},
      {:room, "◇", "зал или переходная камера"},
      {:rest, "▲", "привал — место передышки"},
      {:hazard, "✳", "аномалия или опасный участок"},
      {:boss, "⚔", "логово сильной твари"},
      {:stairs_down, "↓", "спуск на следующий ярус"},
      {:exit, "⌂", "иной выход из Подземелья"}
    ]
  end

  defp node_card_class(%{current?: true}), do: "dng-node-card dng-node-card--current"
  defp node_card_class(%{reachable?: true}), do: "dng-node-card dng-node-card--reachable"
  defp node_card_class(_row), do: "dng-node-card dng-node-card--known"

  defp node_progress_label(%{current?: true}), do: "вы здесь"
  defp node_progress_label(%{reachable?: true}), do: "доступный проход"
  defp node_progress_label(%{node_state: nil}), do: "виден издалека"

  defp node_progress_label(%{node_state: state}),
    do:
      "#{node_state_status_label(state.status)} · встреча: #{encounter_status(state.encounter_status)}"

  defp node_state_status_label(:current), do: "текущий узел"
  defp node_state_status_label(:visited), do: "посещён"
  defp node_state_status_label(:cleared), do: "зачищен"
  defp node_state_status_label(:blocked), do: "перекрыт"
  defp node_state_status_label(_status), do: "состояние неизвестно"

  defp node_glyph(:entrance), do: "↑"
  defp node_glyph(:room), do: "◇"
  defp node_glyph(:rest), do: "▲"
  defp node_glyph(:hazard), do: "✳"
  defp node_glyph(:boss), do: "⚔"
  defp node_glyph(:stairs_up), do: "↑"
  defp node_glyph(:stairs_down), do: "↓"
  defp node_glyph(:exit), do: "⌂"
  defp node_glyph(_kind), do: "?"

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
