defmodule MMGOWeb.BaseLive do
  use MMGOWeb, :live_view

  alias MMGOWeb.GameLiveHelpers

  @items [
    %{
      id: "i1",
      name: "Руна огня",
      icon: "🜂",
      color: "#e05030",
      count: 3,
      weight: 0.1,
      type: "материал"
    },
    %{
      id: "i2",
      name: "Зелье восстановления",
      icon: "⚗",
      color: "#a060e0",
      count: 2,
      weight: 0.3,
      type: "зелье"
    },
    %{
      id: "i3",
      name: "Осколок кристалла",
      icon: "◆",
      color: "#60a060",
      count: 7,
      weight: 0.2,
      type: "материал"
    },
    %{
      id: "i4",
      name: "Провиант",
      icon: "🌾",
      color: "#c8a44a",
      count: 12,
      weight: 0.5,
      type: "еда"
    },
    %{
      id: "i5",
      name: "Малый Красный",
      icon: "📖",
      color: "#b03820",
      count: 1,
      weight: 1.2,
      type: "гримуар"
    },
    %{
      id: "i6",
      name: "Огненная соль",
      icon: "🜂",
      color: "#e05030",
      count: 4,
      weight: 0.1,
      type: "ингредиент"
    },
    %{
      id: "i7",
      name: "Прах Хаоса",
      icon: "⊗",
      color: "#9030b0",
      count: 2,
      weight: 0.2,
      type: "ингредиент"
    }
  ]

  @impl true
  def mount(_params, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)

    {:ok,
     assign(socket,
       page_title: "База",
       tab: "inventory",
       selected_item_id: nil,
       items: @items
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ~w(inventory stats storage craft) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("select_item", %{"id" => id}, socket) do
    selected = if socket.assigns.selected_item_id == id, do: nil, else: id
    {:noreply, assign(socket, :selected_item_id, selected)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :selected_item,
        Enum.find(assigns.items, &(&1.id == assigns.selected_item_id))
      )

    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="base-screen" class="zip-screen">
        <.zip_header
          title="База"
          subtitle={"#{@current_character.name} · Ур. #{@current_character.level}"}
        />

        <section class="zip-content base-content">
          <nav class="zip-tabs">
            <button
              id="base-inventory-tab"
              class={["zip-tab", @tab == "inventory" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="inventory"
            >
              Инвентарь
            </button>
            <button
              id="base-stats-tab"
              class={["zip-tab", @tab == "stats" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="stats"
            >
              Статус
            </button>
            <button
              id="base-storage-tab"
              class={["zip-tab", @tab == "storage" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="storage"
            >
              Хранилище
            </button>
            <button
              id="base-craft-tab"
              class={["zip-tab", @tab == "craft" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="craft"
            >
              Мастерская
            </button>
          </nav>

          <%= if @tab == "inventory" do %>
            <div id="base-inventory" class="base-inventory">
              <div class="base-weight">
                <span>НАГРУЗКА: 9.4 / 30 кг</span>
                <div><span style="width: 31%"></span></div>
              </div>

              <div class="base-grid">
                <button
                  :for={item <- @items}
                  id={"base-item-#{item.id}"}
                  type="button"
                  class={["base-item", @selected_item_id == item.id && "is-selected"]}
                  style={"--item-color: #{item.color}"}
                  phx-click="select_item"
                  phx-value-id={item.id}
                >
                  <span class="base-item__icon">{item.icon}</span>
                  <span class="base-item__name">{item.name}</span>
                  <span class="base-item__count">{item.count}</span>
                </button>
                <div :for={i <- 1..5} class="base-empty-slot" id={"base-empty-#{i}"}></div>
              </div>

              <div :if={@selected_item} id="base-item-detail" class="zip-card">
                <h2>{@selected_item.name}</h2>
                <p>Вес: {@selected_item.weight} кг/шт · Тип: {@selected_item.type}</p>
              </div>
            </div>
          <% end %>

          <%= if @tab == "stats" do %>
            <div id="base-stats" class="base-stats">
              <div class="base-avatar">✦</div>
              <h2>{@current_character.name}</h2>
              <p>Маг · Уровень {@current_character.level}</p>
              <div class="base-school-tags">
                <span style="--school-color:#e05030">🜂 Огонь</span><span style="--school-color:#9030b0">⊗ Хаос</span>
              </div>
              <div class="zip-card">
                <.bar label="Здоровье" value={74} max={90} color="#60a060" />
                <.bar label="Усталость" value={35} max={100} color="#c8a44a" />
                <.bar label="Опыт" value={4400} max={8000} color="#8a6830" />
              </div>
              <div class="base-stat-row">
                <div><strong>1240</strong><span>монет</span></div>
                <div><strong>10</strong><span>заклинаний</span></div>
                <div><strong>3</strong><span>гримуара</span></div>
              </div>
            </div>
          <% end %>

          <%= if @tab == "storage" do %>
            <div id="base-storage" class="base-storage">
              <p class="zip-note">Хранилище защищено. Можно хранить до 200 кг.</p>
              <div :for={row <- 1..3} class="base-storage-row">
                <div
                  :for={col <- 1..4}
                  class={["base-storage-cell", row == 1 && col in [1, 2] && "is-filled"]}
                >
                  <%= cond do %>
                    <% row == 1 and col == 1 -> %>
                      Руны ×3
                    <% row == 1 and col == 2 -> %>
                      Зелья ×4
                    <% true -> %>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @tab == "craft" do %>
            <div id="base-craft" class="zip-panel-list">
              <div class="zip-card">
                <h2>Алхимическая мастерская</h2>
                <p>Для доступа необходимо завершить трек Алхимии в Академии.</p>
              </div>
              <div class="zip-card">
                <h2>Мастерская инструментов</h2>
                <p>Для доступа необходимо завершить трек Мастерства в Академии.</p>
              </div>
            </div>
          <% end %>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp zip_header(assigns) do
    ~H"""
    <header class="zip-telegram-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
    </header>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :color, :string, required: true

  defp bar(assigns) do
    assigns = assign(assigns, :pct, min(100, max(0, round(assigns.value / assigns.max * 100))))

    ~H"""
    <div class="zip-hp base-bar">
      <div><span>{@label}</span><span>{@value}/{@max}</span></div>
      <div class="zip-hp__track">
        <span style={"width: #{@pct}%; background: #{@color}; box-shadow: 0 0 6px #{@color}99"}>
        </span>
      </div>
    </div>
    """
  end
end
