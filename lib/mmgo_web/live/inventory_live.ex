defmodule MMGOWeb.InventoryLive do
  @moduledoc """
  Carry inventory — the item counterpart to the spell library. Weight is a
  core mechanic (GDD §14.3); grimoires are items with weight (§7.2).

  Design pass: hardcoded demo data, no backend wiring. Filtering and search
  operate on the in-memory demo list so the screen is explorable. The
  bookmark/tag affordance is deliberately generic — alchemy & crafting will
  reuse it.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @carry_max 50

  @categories ~w(все оружие зелья ингредиенты инструменты провизия гримуары)

  @items [
    %{
      id: "dagger",
      name: "Стальной кинжал",
      cat: "оружие",
      weight: 1.5,
      value: 110,
      qty: 1,
      equipped: true,
      desc: "Клинок работы кузнецов Врат Зари. Держит остроту, не подводит в тесноте."
    },
    %{
      id: "heal",
      name: "Зелье исцеления",
      cat: "зелья",
      weight: 0.5,
      value: 45,
      qty: 3,
      equipped: false,
      desc: "Затягивает раны за один вдох. В подземельях Башни — на вес золота."
    },
    %{
      id: "mana",
      name: "Флакон маны",
      cat: "зелья",
      weight: 0.4,
      value: 60,
      qty: 2,
      equipped: false,
      desc: "Восполняет иссякший запас силы. Горчит, но своё дело знает."
    },
    %{
      id: "fang",
      name: "Клык теневого волка",
      cat: "ингредиенты",
      weight: 0.2,
      value: 85,
      qty: 2,
      equipped: false,
      desc: "Редкая добыча с третьего яруса Башни. Ценится алхимиками за стойкость к порче."
    },
    %{
      id: "ash",
      name: "Пепел саламандры",
      cat: "ингредиенты",
      weight: 0.1,
      value: 40,
      qty: 4,
      equipped: false,
      desc: "Тлеет, не остывая. Основа для зелий огненной школы."
    },
    %{
      id: "grim7",
      name: "Малый гримуар · 7 печатей",
      cat: "гримуары",
      weight: 2.0,
      value: 320,
      qty: 1,
      equipped: false,
      desc: "Лёгкий том на семь заклинаний. Выбор тех, кто идёт за добычей, а не за боем."
    },
    %{
      id: "grimchaos",
      name: "Гримуар Хаоса · 23 печати",
      cat: "гримуары",
      weight: 4.5,
      value: 900,
      qty: 1,
      equipped: true,
      desc: "Тяжёлый фолиант вашей школы Хаоса. Гибкость в бою ценой места под трофеи."
    },
    %{
      id: "bread",
      name: "Дорожные хлебы",
      cat: "провизия",
      weight: 0.5,
      value: 6,
      qty: 5,
      equipped: false,
      desc: "Один хлеб — один день пути. Тяжелеют в котомке быстрее, чем кажется."
    },
    %{
      id: "meat",
      name: "Вяленое мясо",
      cat: "провизия",
      weight: 0.4,
      value: 9,
      qty: 4,
      equipped: false,
      desc: "Сытнее хлеба, дольше хранится. Незаменимо в долгой вылазке."
    },
    %{
      id: "whet",
      name: "Точильный камень",
      cat: "инструменты",
      weight: 0.8,
      value: 25,
      qty: 1,
      equipped: false,
      desc: "Правит кромку клинка на привале. Без него сталь тупеет к третьему бою."
    },
    %{
      id: "picks",
      name: "Отмычки",
      cat: "инструменты",
      weight: 0.3,
      value: 45,
      qty: 1,
      equipped: false,
      desc: "Тонкая работа. Открывают то, что заперто не магией."
    },
    %{
      id: "torch",
      name: "Факел",
      cat: "инструменты",
      weight: 0.3,
      value: 4,
      qty: 3,
      equipped: false,
      desc: "Свет там, где не горит магия. Хватает на несколько часов."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load carried items and carry_max from the character.
    {:ok,
     socket
     |> assign(:page_title, "Котомка")
     |> assign(:categories, @categories)
     |> assign(:filter, "все")
     |> assign(:query, "")
     |> assign(:selected, nil)
     |> assign(:tagged, MapSet.new(["fang", "ash"]))
     |> assign(:carry, carried_weight())
     |> assign(:carry_max, @carry_max)}
  end

  @impl true
  def handle_event("filter", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, :filter, cat)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, :query, q)}
  end

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected, id)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  @impl true
  def handle_event("toggle_tag", %{"id" => id}, socket) do
    tagged =
      if MapSet.member?(socket.assigns.tagged, id),
        do: MapSet.delete(socket.assigns.tagged, id),
        else: MapSet.put(socket.assigns.tagged, id)

    {:noreply, assign(socket, :tagged, tagged)}
  end

  @impl true
  def render(assigns) do
    visible = filter_items(assigns.filter, assigns.query)

    assigns =
      assigns
      |> assign(:visible, visible)
      |> assign(
        :selected_item,
        assigns.selected && Enum.find(@items, &(&1.id == assigns.selected))
      )
      |> assign(:pct, min(100, round(assigns.carry / assigns.carry_max * 100)))

    ~H"""
    <div class="game-screen">
      <div class="inv-root">
        <a href={~p"/map"} class="inv-exit">&larr; на карту</a>

        <header class="inv-head">
          <h1 class="inv-title">Котомка</h1>
          <p class="inv-sub">Альберт Северин · Врата Зари</p>

          <div class={["inv-carry", @pct >= 90 && "inv-carry--heavy"]}>
            <div class="inv-carry__top">
              <span class="inv-carry__label">Вес поклажи</span>
              <span class="inv-carry__num">{fmt_w(@carry)} / {@carry_max} стоуна</span>
            </div>
            <div class="inv-carry__track">
              <div class="inv-carry__fill" style={"width:#{@pct}%"}></div>
            </div>
            <p class="inv-carry__hint">
              {if @pct >= 90, do: "На пределе — из боя не сбежать", else: "Есть ещё место под трофеи"}
            </p>
          </div>
        </header>

        <form phx-change="search" class="inv-search">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Искать в котомке…"
            autocomplete="off"
            class="inv-search__in"
          />
          <span class="inv-search__glass">⌕</span>
        </form>

        <nav class="inv-chips">
          <button
            :for={cat <- @categories}
            type="button"
            class={["inv-chip", @filter == cat && "inv-chip--on"]}
            phx-click="filter"
            phx-value-cat={cat}
          >
            {cat}
          </button>
        </nav>

        <p :if={@visible == []} class="inv-empty">В котомке пусто по этому запросу.</p>

        <ul class="inv-list">
          <li
            :for={it <- @visible}
            class={["inv-item", it.equipped && "inv-item--equipped"]}
            phx-click="open"
            phx-value-id={it.id}
          >
            <.art_slot kind="icon" variant="dark" label={it.name} class="inv-item__icon" />
            <div class="inv-item__body">
              <span class="inv-item__name">
                {it.name}<span :if={it.qty > 1} class="inv-item__qty">×{it.qty}</span>
              </span>
              <div class="inv-item__meta">
                <span class="inv-chip inv-chip--tag">{it.cat}</span>
                <span :if={it.equipped} class="inv-item__eq">экипировано</span>
              </div>
            </div>
            <div class="inv-item__right">
              <button
                type="button"
                class={["inv-mark", MapSet.member?(@tagged, it.id) && "inv-mark--on"]}
                phx-click="toggle_tag"
                phx-value-id={it.id}
                title="отметить для продажи"
              >
                ❦
              </button>
              <span class="inv-item__weight">{fmt_w(it.weight * it.qty)}</span>
              <span class="inv-item__value"><span class="inv-coin">◈</span>{it.value}</span>
            </div>
          </li>
        </ul>

        <%= if @selected_item do %>
          <div class="inv-sheet-scrim" phx-click="close">
            <div class="inv-sheet" phx-click-away="close">
              <div class="inv-sheet__grab"></div>
              <div class="inv-sheet__head">
                <.art_slot
                  kind="scene"
                  variant="dark"
                  label={@selected_item.name}
                  class="inv-sheet__art"
                />
                <div>
                  <h2 class="inv-sheet__name">{@selected_item.name}</h2>
                  <div class="inv-sheet__meta">
                    <span class="inv-chip inv-chip--tag">{@selected_item.cat}</span>
                    <span class="inv-sheet__stat">{fmt_w(@selected_item.weight)} стоуна</span>
                    <span class="inv-sheet__stat">
                      <span class="inv-coin">◈</span>{@selected_item.value} за штуку
                    </span>
                  </div>
                </div>
              </div>

              <p class="inv-sheet__desc">{@selected_item.desc}</p>

              <div class="inv-sheet__actions">
                <button type="button" class="inv-act inv-act--primary">
                  {if @selected_item.equipped, do: "Снять", else: "Экипировать"}
                </button>
                <button
                  type="button"
                  class={["inv-act", MapSet.member?(@tagged, @selected_item.id) && "inv-act--marked"]}
                  phx-click="toggle_tag"
                  phx-value-id={@selected_item.id}
                >
                  ❦ {if MapSet.member?(@tagged, @selected_item.id),
                    do: "Снять отметку",
                    else: "Отметить для продажи"}
                </button>
                <button type="button" class="inv-act inv-act--danger">Выбросить</button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- helpers -------------------------------------------------------------

  defp filter_items(filter, query) do
    q = query |> String.trim() |> String.downcase()

    @items
    |> Enum.filter(fn it -> filter == "все" or it.cat == filter end)
    |> Enum.filter(fn it -> q == "" or String.contains?(String.downcase(it.name), q) end)
  end

  defp carried_weight do
    @items
    |> Enum.map(&(&1.weight * &1.qty))
    |> Enum.sum()
    |> Float.round(1)
  end

  defp fmt_w(w) when is_float(w), do: :erlang.float_to_binary(Float.round(w, 1), decimals: 1)
  defp fmt_w(w), do: to_string(w)
end
