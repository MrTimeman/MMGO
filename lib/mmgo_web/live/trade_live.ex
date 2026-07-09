defmodule MMGOWeb.TradeLive do
  @moduledoc """
  Trade counter — buy & sell at a shop, plus owner price-setting and the
  black-market re-skin (GDD §12.2 taxation, §12.3 illegal P2P).

  Design pass: hardcoded demo data, no backend wiring. See
  docs/UI_DESIGN_BRIEF.md. All state lives in assigns and mutates via
  phx-click so the screen is fully explorable.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @tax_rate 0.08

  # Shop stock — what the merchant sells you (buy mode). Prices are the
  # merchant's ask; tax is shown separately per GDD §12.2.
  @goods [
    %{
      id: "heal",
      name: "Зелье исцеления",
      cat: "зелья",
      weight: 0.5,
      price: 45,
      note: "затягивает раны в бою"
    },
    %{
      id: "mana",
      name: "Флакон маны",
      cat: "зелья",
      weight: 0.4,
      price: 60,
      note: "восполняет запас силы"
    },
    %{
      id: "grim7",
      name: "Малый гримуар · 7 печатей",
      cat: "гримуары",
      weight: 2.0,
      price: 320,
      note: "лёгкий том для вылазок"
    },
    %{
      id: "dagger",
      name: "Стальной кинжал",
      cat: "оружие",
      weight: 1.5,
      price: 110,
      note: "надёжная сталь Врат Зари"
    },
    %{
      id: "bread",
      name: "Дорожные хлебы · 5 шт",
      cat: "провизия",
      weight: 2.5,
      price: 30,
      note: "на пять дней пути"
    },
    %{
      id: "torch",
      name: "Факел · 3 шт",
      cat: "инструменты",
      weight: 1.0,
      price: 12,
      note: "свет в подземельях Башни"
    }
  ]

  # What you can offer the shop (sell mode) — the merchant's buy-back price.
  @wares [
    %{
      id: "fang",
      name: "Клык теневого волка",
      cat: "ингредиенты",
      weight: 0.2,
      price: 85,
      note: "редкая добыча из Башни"
    },
    %{
      id: "ash",
      name: "Пепел саламандры",
      cat: "ингредиенты",
      weight: 0.1,
      price: 40,
      note: "тлеет, не остывая"
    },
    %{
      id: "oldgrim",
      name: "Потёртый гримуар · 5 печатей",
      cat: "гримуары",
      weight: 1.6,
      price: 60,
      note: "первый ваш том"
    },
    %{
      id: "heal_used",
      name: "Зелье исцеления",
      cat: "зелья",
      weight: 0.5,
      price: 22,
      note: "початый флакон"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load shop, stock, and character purse from context.
    {:ok,
     socket
     |> assign(:page_title, "Лавка торговца")
     |> assign(:tax_rate, @tax_rate)
     |> assign(:purse, 2_340)
     |> assign(:mode, :buy)
     |> assign(:owner?, false)
     |> assign(:black?, false)
     |> assign(:confirm?, false)
     |> assign(:cart, %{})
     # owner-set chalk prices, keyed by good id, seeded from base price
     |> assign(:chalk, Map.new(@goods, &{&1.id, &1.price}))}
  end

  @impl true
  def handle_event("mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  @impl true
  def handle_event("toggle_owner", _params, socket) do
    {:noreply, socket |> assign(:owner?, !socket.assigns.owner?) |> assign(:confirm?, false)}
  end

  @impl true
  def handle_event("toggle_black", _params, socket) do
    {:noreply, socket |> assign(:black?, !socket.assigns.black?) |> assign(:confirm?, false)}
  end

  @impl true
  def handle_event("add", %{"id" => id}, socket) do
    cart = Map.update(socket.assigns.cart, id, 1, &(&1 + 1))
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event("drop", %{"id" => id}, socket) do
    cart =
      case Map.get(socket.assigns.cart, id, 0) do
        n when n <= 1 -> Map.delete(socket.assigns.cart, id)
        n -> Map.put(socket.assigns.cart, id, n - 1)
      end

    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event("chalk", %{"id" => id, "value" => value}, socket) do
    price =
      case Integer.parse(value) do
        {n, _} when n >= 0 -> n
        _ -> Map.get(socket.assigns.chalk, id, 0)
      end

    {:noreply, assign(socket, :chalk, Map.put(socket.assigns.chalk, id, price))}
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    {:noreply, assign(socket, :confirm?, true)}
  end

  @impl true
  def handle_event("close_receipt", _params, socket) do
    {:noreply, assign(socket, :confirm?, false)}
  end

  @impl true
  def handle_event("seal_deal", _params, socket) do
    # TODO: wire — post transaction, apply tax to Treasury, move items.
    {:noreply, socket |> assign(:cart, %{}) |> assign(:confirm?, false)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:rows, if(assigns.mode == :buy, do: @goods, else: @wares))
      |> assign(:cart_lines, cart_lines(assigns))

    subtotal = Enum.sum(Enum.map(assigns.cart_lines, & &1.line))
    tax = if assigns.black?, do: 0, else: round(subtotal * @tax_rate)

    assigns =
      assigns
      |> assign(:subtotal, subtotal)
      |> assign(:tax, tax)
      |> assign(:total, subtotal + tax)
      |> assign(:cart_count, Enum.sum(Map.values(assigns.cart)))

    ~H"""
    <div class="game-screen">
      <div class={["trd-root", @black? && "trd-root--black"]}>
        <a href={~p"/map"} class="trd-exit">&larr; на площадь</a>

        <div class="trd-shell">
          <header class="trd-head">
            <.art_slot
              kind="hero"
              variant="dark"
              label={
                if @black?, do: "Задворки · сделка в тени", else: "Лавка торговца во Вратах Зари"
              }
              class="trd-hero"
            />
            <div class="trd-head__bar">
              <div class="trd-head__who">
                <span class="trd-head__shop">
                  {if @black?, do: "Тёмный угол", else: "Лавка торговца"}
                </span>
                <span class="trd-head__keeper">
                  {if @black?, do: "торгует Некто в капюшоне", else: "хозяин — Горан Медовар"}
                </span>
              </div>
              <div class="trd-purse" title="ваш кошель">
                <span class="trd-coin">◈</span>
                <span class="trd-purse__n">{fmt(@purse)}</span>
              </div>
            </div>
          </header>

          <div class="trd-toggles">
            <button
              type="button"
              class={["trd-toggle", @owner? && "trd-toggle--on"]}
              phx-click="toggle_owner"
            >
              <span class="trd-toggle__dot"></span> Вы владелец
            </button>
            <button
              type="button"
              class={["trd-toggle trd-toggle--shady", @black? && "trd-toggle--on"]}
              phx-click="toggle_black"
            >
              <span class="trd-toggle__dot"></span> Тайный стук
            </button>
          </div>

          <%= if @black? do %>
            <p class="trd-warn">⚠ сделка без защиты — вас могут обмануть</p>
          <% end %>

          <%= if @owner? do %>
            <div class="trd-revenue">
              <span class="trd-revenue__label">выручка за день</span>
              <div class="trd-revenue__grid">
                <div><b>1 240</b><span>продано, монет</span></div>
                <div><b>99</b><span>налог казне</span></div>
                <div><b>17</b><span>сделок</span></div>
              </div>
              <p class="trd-revenue__hint">Впиши свою цену мелом в строке товара.</p>
            </div>
          <% end %>

          <nav class="trd-tabs" role="tablist">
            <button
              type="button"
              class={["trd-tab", @mode == :buy && "trd-tab--on"]}
              phx-click="mode"
              phx-value-mode="buy"
            >
              Купить
            </button>
            <button
              type="button"
              class={["trd-tab", @mode == :sell && "trd-tab--on"]}
              phx-click="mode"
              phx-value-mode="sell"
            >
              Продать
            </button>
          </nav>

          <ul class="trd-goods">
            <li :for={row <- @rows} class="trd-good">
              <.art_slot kind="icon" variant="dark" label={row.name} class="trd-good__icon" />
              <div class="trd-good__body">
                <span class="trd-good__name">{row.name}</span>
                <span class="trd-good__note">{row.note}</span>
                <div class="trd-good__meta">
                  <span class="trd-chip">{row.cat}</span>
                  <span class="trd-good__weight">{fmt_w(row.weight)} стоуна</span>
                </div>
              </div>
              <div class="trd-good__deal">
                <%= if @owner? and @mode == :buy do %>
                  <label class="trd-chalk">
                    <input
                      type="text"
                      inputmode="numeric"
                      value={Map.get(@chalk, row.id, row.price)}
                      phx-blur="chalk"
                      phx-value-id={row.id}
                      class="trd-chalk__in"
                    />
                    <span class="trd-chalk__unit">◈</span>
                  </label>
                  <span class="trd-good__tax">фикс. цена</span>
                <% else %>
                  <span class="trd-good__price">
                    <span class="trd-coin">◈</span>{price_of(row, @chalk)}
                  </span>
                  <span class="trd-good__tax">
                    {if @black?,
                      do: "без налога",
                      else: "+ #{round(price_of(row, @chalk) * @tax_rate)} налог"}
                  </span>
                  <button type="button" class="trd-add" phx-click="add" phx-value-id={row.id}>
                    {if @mode == :buy, do: "＋ в корзину", else: "＋ продать"}
                  </button>
                <% end %>
              </div>
            </li>
          </ul>
        </div>

        <%= if @cart_count > 0 and not @owner? do %>
          <div class="trd-cartbar">
            <div class="trd-cartbar__sum">
              <span class="trd-cartbar__n">{@cart_count} поз.</span>
              <span class="trd-cartbar__coin"><span class="trd-coin">◈</span>{fmt(@total)}</span>
            </div>
            <button type="button" class="trd-cartbar__go" phx-click="confirm">
              {if @mode == :buy, do: "Ударить по рукам", else: "Сбыть товар"}
            </button>
          </div>
        <% end %>

        <%= if @confirm? do %>
          <div class="trd-receipt-scrim" phx-click="close_receipt">
            <div
              class={["trd-receipt", @black? && "trd-receipt--black"]}
              phx-click-away="close_receipt"
            >
              <div class="trd-receipt__deckle"></div>
              <h2 class="trd-receipt__title">
                {if @black?, do: "Тайная сделка", else: "Торговая расписка"}
              </h2>
              <p class="trd-receipt__place">Врата Зари · 14-е Месяца Жатвы, 847</p>

              <ul class="trd-receipt__lines">
                <li :for={l <- @cart_lines} class="trd-receipt__line">
                  <span class="trd-receipt__item">{l.name} <em>×{l.qty}</em></span>
                  <span class="trd-receipt__amt">{fmt(l.line)}</span>
                </li>
              </ul>

              <div class="trd-receipt__foot">
                <div class="trd-receipt__row">
                  <span>подытог</span><span>{fmt(@subtotal)}</span>
                </div>
                <%= if @black? do %>
                  <div class="trd-receipt__row trd-receipt__row--muted">
                    <span>без налога</span><span>—</span>
                  </div>
                <% else %>
                  <div class="trd-receipt__row">
                    <span>налог казне 8%</span><span>{fmt(@tax)}</span>
                  </div>
                <% end %>
                <div class="trd-receipt__row trd-receipt__row--total">
                  <span>итого</span><span><span class="trd-coin">◈</span> {fmt(@total)}</span>
                </div>
              </div>

              <div class="trd-receipt__stamp">
                {if @black?, do: "без печати", else: "казна Эленвира"}
              </div>

              <button type="button" class="trd-receipt__seal" phx-click="seal_deal">
                {if @black?, do: "Разойтись по-тихому", else: "Приложить печать"}
              </button>
              <button type="button" class="trd-receipt__cancel" phx-click="close_receipt">
                передумать
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- helpers -------------------------------------------------------------

  defp cart_lines(assigns) do
    rows = if assigns.mode == :buy, do: @goods, else: @wares
    index = Map.new(rows, &{&1.id, &1})

    assigns.cart
    |> Enum.map(fn {id, qty} ->
      case index[id] do
        nil ->
          nil

        row ->
          unit = price_of(row, assigns.chalk)
          %{id: id, name: row.name, qty: qty, unit: unit, line: unit * qty}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp price_of(row, chalk), do: Map.get(chalk, row.id, row.price)

  defp fmt(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map(&Enum.join/1)
    |> Enum.join(" ")
  end

  defp fmt_w(w) when is_float(w), do: :erlang.float_to_binary(w, decimals: 1)
  defp fmt_w(w), do: to_string(w)
end
