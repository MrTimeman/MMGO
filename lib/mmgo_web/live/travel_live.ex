defmodule MMGOWeb.TravelLive do
  @moduledoc """
  Design-pass screen — a journey in progress (GDD §5.2, §14).

  Врата Зари → Башня, rendered as a vertical road of waypoints with the
  party's current position, supplies burning down at 1 unit/day/head,
  a danger strip for the PvP wilderness, and a running travel log.

  Reviewable demo states via the "походный дневник" control at the bottom:
  en route, low on food (§14.1 penalties), an ambush teaser that links to
  /combat, and arrival that links to /event. See docs/UI_DESIGN_BRIEF.md.
  """
  use MMGOWeb, :live_view

  @waypoints [
    %{name: "Врата Зари", note: "выход из городских ворот", region: "город"},
    %{name: "Брод Тихой реки", note: "переправа вброд, вода по колено", region: "тракт"},
    %{name: "Старый мост", note: "заброшенная застава у моста", region: "тракт"},
    %{name: "Развилка у кургана", note: "здесь тракт уходит в пустошь", region: "рубеж"},
    %{name: "Волчья пустошь", note: "открытая земля, разбойные тропы", region: "глушь"},
    %{name: "Подножие гор", note: "каменистый подъём к утёсам", region: "горы"},
    %{name: "Башня", note: "цель пути", region: "башня"}
  ]

  @party ["Альберт", "Гром", "Лисса", "Одо"]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — hydrate from the character's active Travel.Journey and party.
    {:ok,
     socket
     |> assign(:page_title, "В пути")
     |> assign(:view, :enroute)
     |> assign(:wp_index, 3)
     |> assign(:day, 3)
     |> assign(:total_days, 6)
     |> assign(:food, 20)
     |> assign(:food_per_day, length(@party))
     |> assign(:carry, 38)
     |> assign(:carry_max, 60)
     |> assign(:log, initial_log())}
  end

  @impl true
  def handle_event("advance", _params, socket) do
    # TODO: wire — this is the client-side echo of a server travel tick.
    idx = min(socket.assigns.wp_index + 1, length(@waypoints) - 1)
    wp = Enum.at(@waypoints, idx)
    day = socket.assigns.day + 1
    food = max(socket.assigns.food - socket.assigns.food_per_day, 0)

    socket =
      socket
      |> assign(:wp_index, idx)
      |> assign(:day, day)
      |> assign(:food, food)
      |> log_entry("День #{day} — вышли к точке «#{wp.name}».")

    socket = if idx == length(@waypoints) - 1, do: assign(socket, :view, :arrival), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_event("scavenge", _params, socket) do
    socket =
      socket
      |> assign(:food, min(socket.assigns.food + 3, 40))
      |> log_entry(
        "День #{socket.assigns.day} — привал в перелеске. Лисса набрала кореньев и грибов (+3 ед.)."
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_view", %{"view" => view}, socket) do
    view = String.to_existing_atom(view)

    socket =
      case view do
        # A dramatised "supplies ran out" snapshot for review of the §14.1 warning.
        :starving -> assign(socket, food: 2)
        :enroute -> assign(socket, food: 20)
        _ -> socket
      end

    {:noreply, assign(socket, :view, view)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:waypoints, @waypoints)
      |> assign(:party, @party)
      |> assign(:days_left, max(assigns.total_days - assigns.day, 0))
      |> assign(:food_days, food_days(assigns.food, assigns.food_per_day))
      |> assign(
        :food_low?,
        assigns.view == :starving or
          food_days(assigns.food, assigns.food_per_day) < assigns.total_days - assigns.day
      )

    ~H"""
    <div class="trv-scene">
      <div class="trv-shell">
        <a href={~p"/map"} class="trv-exit">← На карту</a>

        <header class="trv-head">
          <p class="trv-eyebrow">Переход · караван</p>
          <h1 class="trv-route">
            Врата Зари <span class="trv-route__arrow">→</span> Башня
          </h1>
          <div class="trv-stats">
            <div class="trv-stat">
              <span class="trv-stat__num">{@day}</span>
              <span class="trv-stat__cap">день в пути</span>
            </div>
            <div class="trv-stat">
              <span class="trv-stat__num">{@days_left}</span>
              <span class="trv-stat__cap">осталось дней</span>
            </div>
            <div class="trv-stat">
              <span class="trv-stat__num">~40м</span>
              <span class="trv-stat__cap">до прибытия</span>
            </div>
          </div>
        </header>

        <%= if @view == :arrival do %>
          <div class="trv-arrival">
            <p class="trv-arrival__kicker">✦ конец пути ✦</p>
            <h2 class="trv-arrival__title">Вы прибыли к Башне</h2>
            <p class="trv-arrival__text">
              Утёсы расступаются, и чёрный шпиль встаёт над морем. Дорога позади,
              впереди — распахнутые врата и запах магии в стылом воздухе.
            </p>
            <.link navigate={~p"/event"} class="trv-btn trv-btn--gold">Войти в локацию</.link>
          </div>
        <% else %>
          <section class="trv-path" aria-label="Маршрут">
            <ol class="trv-wp">
              <li
                :for={{wp, i} <- Enum.with_index(@waypoints)}
                class={[
                  "trv-wp__row",
                  i < @wp_index && "is-done",
                  i == @wp_index && "is-here",
                  i > @wp_index && "is-ahead"
                ]}
              >
                <span class="trv-wp__mark"></span>
                <div class="trv-wp__info">
                  <span class="trv-wp__name">
                    {wp.name}
                    <span :if={i == @wp_index} class="trv-wp__you">вы здесь</span>
                  </span>
                  <span class="trv-wp__note">{wp.note}</span>
                </div>
              </li>
            </ol>
          </section>

          <section class="trv-panel">
            <div class="trv-panel__head">
              <h2 class="trv-panel__title">Провизия</h2>
              <span class="trv-panel__meta">{@food} ед. · расход {@food_per_day} ед./день</span>
            </div>
            <div class="trv-bar">
              <div
                class={["trv-bar__fill", @food_low? && "trv-bar__fill--warn"]}
                style={"width:#{bar_pct(@food, 24)}%"}
              >
              </div>
            </div>
            <p class="trv-panel__sub">
              Хватит на {@food_days} дн. из {@days_left} оставшихся.
            </p>

            <%= if @food_low? do %>
              <div class="trv-warn">
                <span class="trv-warn__glyph">⚠</span>
                <p>
                  <strong>Припасы на исходе.</strong>
                  Первый день без еды — отряд идёт медленнее; со второго дня голод точит
                  общий котёл здоровья (§14.1). Пополните запас или сверните к привалу.
                </p>
              </div>
            <% end %>

            <div class="trv-carry">
              <div class="trv-carry__head">
                <span>Груз каравана</span>
                <span class={["trv-carry__num", @carry > @carry_max && "is-over"]}>
                  {@carry} / {@carry_max}
                </span>
              </div>
              <div class="trv-bar trv-bar--slim">
                <div
                  class="trv-bar__fill trv-bar__fill--stone"
                  style={"width:#{bar_pct(@carry, @carry_max)}%"}
                >
                </div>
              </div>
            </div>
          </section>

          <section class="trv-danger">
            <div class="trv-danger__head">
              <span class="trv-danger__pip"></span>
              <span class="trv-danger__label">Зона PvP · Волчья пустошь</span>
            </div>
            <p class="trv-danger__text">
              Магия в глуши мертва — только сталь и потроны. По тропам ходят разбойники;
              гружёный добычей караван — лакомая цель.
            </p>
            <div class="trv-chips">
              <span :for={p <- @party} class="trv-chip">{p}</span>
            </div>

            <%= if @view == :ambush do %>
              <div class="trv-ambush">
                <p class="trv-ambush__text">
                  На гребне холма мелькнули силуэты. Свистнула тетива — засада!
                </p>
                <.link navigate={~p"/combat"} class="trv-btn trv-btn--danger">К бою →</.link>
              </div>
            <% end %>
          </section>

          <section class="trv-panel">
            <div class="trv-panel__head">
              <h2 class="trv-panel__title">Дорожный журнал</h2>
            </div>
            <ul class="trv-log">
              <li :for={e <- @log} class="trv-log__row">
                <span class="trv-log__dot"></span>
                <span class="trv-log__text">{e}</span>
              </li>
            </ul>
          </section>

          <div class="trv-acts">
            <button type="button" class="trv-btn" phx-click="scavenge">
              Разбить привал · искать припасы
            </button>
            <button type="button" class="trv-btn trv-btn--gold" phx-click="advance">
              Продолжить путь →
            </button>
          </div>
        <% end %>

        <div class="trv-review">
          <span class="trv-review__label">☞ походный дневник · состояния</span>
          <div class="trv-review__chips">
            <button
              type="button"
              class={"trv-rchip#{if @view == :enroute, do: " is-on"}"}
              phx-click="set_view"
              phx-value-view="enroute"
            >
              В пути
            </button>
            <button
              type="button"
              class={"trv-rchip#{if @view == :starving, do: " is-on"}"}
              phx-click="set_view"
              phx-value-view="starving"
            >
              Мало еды
            </button>
            <button
              type="button"
              class={"trv-rchip#{if @view == :ambush, do: " is-on"}"}
              phx-click="set_view"
              phx-value-view="ambush"
            >
              Засада
            </button>
            <button
              type="button"
              class={"trv-rchip#{if @view == :arrival, do: " is-on"}"}
              phx-click="set_view"
              phx-value-view="arrival"
            >
              Прибытие
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp initial_log do
    [
      "День 3 — прошли брод Тихой реки, обувь ещё сохнет у седла.",
      "День 2 — заночевали у Старого моста, Гром стоял в дозоре.",
      "День 1 — вышли из Врат Зари на рассвете, полны провизии."
    ]
  end

  defp log_entry(socket, text), do: assign(socket, :log, [text | socket.assigns.log])

  defp food_days(food, per_day) when per_day > 0, do: div(food, per_day)
  defp food_days(_food, _per_day), do: 0

  defp bar_pct(_value, max) when max <= 0, do: 0

  defp bar_pct(value, max),
    do: value |> Kernel./(max) |> Kernel.*(100) |> min(100) |> max(0) |> round()
end
