defmodule MMGOWeb.FinanceLive do
  @moduledoc """
  Personal ledger book — a diegetic finance screen a character owns.
  Simple view by default (balance, month flow, plain-word entries, charity);
  advanced view flips to a full ledger, category bars, tax paid, and the
  property & shares register (GDD §12.2 tax, §12.5 charity, §17.3 shares).

  Design pass: hardcoded demo data, no backend wiring. Uses the shared
  parchment `.book` chrome from app.css so it reads as a bound ledger.
  """
  use MMGOWeb, :live_view

  @balance 2_340
  @month_in 640
  @month_out 455

  # Recent movements, newest first. Amounts positive = income.
  @entries [
    %{
      date: "14-е Жатвы",
      who: "Лавка Горана",
      cat: "Торговля",
      plain: "Продажа зелья",
      amt: 40,
      tax: 3
    },
    %{
      date: "13-е Жатвы",
      who: "Лавка Горана",
      cat: "Покупки",
      plain: "Покупка гримуара",
      amt: -320,
      tax: 26
    },
    %{
      date: "12-е Жатвы",
      who: "Гильдия Врат",
      cat: "Награды",
      plain: "Награда за задание",
      amt: 150,
      tax: 0
    },
    %{
      date: "11-е Жатвы",
      who: "Академия",
      cat: "Пошлины",
      plain: "Пошлина Академии",
      amt: -80,
      tax: 6
    },
    %{
      date: "10-е Жатвы",
      who: "Некто в капюшоне",
      cat: "Торговля",
      plain: "Продажа клыка",
      amt: 85,
      tax: 0
    },
    %{
      date: "9-е Жатвы",
      who: "Фонд Просвещения",
      cat: "Пожертвования",
      plain: "Взнос в Фонд",
      amt: -100,
      tax: 0
    },
    %{
      date: "8-е Жатвы",
      who: "Караван «Соль»",
      cat: "Награды",
      plain: "Доля с эскорта",
      amt: 210,
      tax: 17
    },
    %{
      date: "7-е Жатвы",
      who: "Лавка алхимика",
      cat: "Покупки",
      plain: "Реагенты для зелий",
      amt: -55,
      tax: 4
    }
  ]

  # Income & expense grouped by category (for the CSS bars).
  @income [{"Торговля", 265}, {"Награды", 360}, {"Прочее", 15}]
  @expense [{"Покупки", 375}, {"Пожертвования", 100}, {"Пошлины", 80}]

  @shares [
    %{name: "Дом у Врат Зари", kind: "ваша база", pct: 100, mine: true},
    %{name: "Торговый дом «Северный путь»", kind: "торговая компания", pct: 15, mine: false},
    %{name: "Гильдия «Пепел»", kind: "боевое братство", pct: 5, mine: false}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load balance, ledger, shares, and charity standing.
    {:ok,
     socket
     |> assign(:page_title, "Счётная книга")
     |> assign(:view, :simple)
     |> assign(:balance, @balance)
     |> assign(:month_in, @month_in)
     |> assign(:month_out, @month_out)
     |> assign(:entries, Enum.take(@entries, 5))
     |> assign(:entries_full, @entries)
     |> assign(:income, @income)
     |> assign(:expense, @expense)
     |> assign(:shares, @shares)}
  end

  @impl true
  def handle_event("view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :view, String.to_existing_atom(view))}
  end

  @impl true
  def handle_event("donate", _params, socket) do
    # TODO: wire — open donation flow to the charity fund.
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:tax_paid, Enum.sum(Enum.map(@entries, & &1.tax)))
      |> assign(:income_max, @income |> Enum.map(&elem(&1, 1)) |> Enum.max())
      |> assign(:expense_max, @expense |> Enum.map(&elem(&1, 1)) |> Enum.max())

    ~H"""
    <div class="scene-desk">
      <div class="book">
        <div class="book__spine"></div>
        <div class="book__page">
          <div class="book__ribbons">
            <button
              type="button"
              class={"book__ribbon#{if @view == :simple, do: " book__ribbon--active"}"}
              phx-click="view"
              phx-value-view="simple"
            >
              Кратко
            </button>
            <button
              type="button"
              class={"book__ribbon#{if @view == :advanced, do: " book__ribbon--active"}"}
              phx-click="view"
              phx-value-view="advanced"
            >
              Подробно
            </button>
          </div>

          <a href={~p"/map"} class="book__back">&larr; закрыть книгу</a>

          <%= case @view do %>
            <% :simple -> %>
              <.simple_leaf
                balance={@balance}
                month_in={@month_in}
                month_out={@month_out}
                entries={@entries}
              />
            <% :advanced -> %>
              <.advanced_leaf
                entries={@entries_full}
                income={@income}
                expense={@expense}
                income_max={@income_max}
                expense_max={@expense_max}
                tax_paid={@tax_paid}
                shares={@shares}
              />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :balance, :integer, required: true
  attr :month_in, :integer, required: true
  attr :month_out, :integer, required: true
  attr :entries, :list, required: true

  defp simple_leaf(assigns) do
    ~H"""
    <div class="book__leaf">
      <h1 class="book__title">Счётная книга</h1>
      <p class="book__subtitle">Альберт Северин, купно с имуществом</p>

      <div class="fin-balance">
        <span class="fin-balance__label">В кошеле и на счету</span>
        <span class="fin-balance__sum">
          <span class="fin-coin">◈</span>{fmt(@balance)}
        </span>
        <span class="fin-balance__unit">монет княжества Эленвир</span>
      </div>

      <div class="fin-flow">
        <div class="fin-flow__col fin-flow__col--in">
          <span class="fin-flow__label">Пришло за месяц</span>
          <span class="fin-flow__amt">+{fmt(@month_in)}</span>
        </div>
        <div class="fin-flow__col fin-flow__col--out">
          <span class="fin-flow__label">Ушло за месяц</span>
          <span class="fin-flow__amt">−{fmt(@month_out)}</span>
        </div>
      </div>

      <h2 class="fin-h">Последние записи</h2>
      <ul class="fin-plain">
        <li :for={e <- @entries} class="fin-plain__row">
          <span class="fin-plain__what">{e.plain}</span>
          <span class={["fin-plain__amt", e.amt >= 0 && "fin-plain__amt--in"]}>
            {sign(e.amt)}{fmt(abs(e.amt))}
          </span>
        </li>
      </ul>

      <div class="fin-charity">
        <p class="fin-charity__note">
          «Ваш взнос учит того, кому нечем платить за науку.»
        </p>
        <button type="button" class="fin-charity__btn" phx-click="donate">
          Пожертвовать в Фонд Просвещения
        </button>
        <p class="fin-charity__hint">Меценаты попадают в открытый список благодетелей.</p>
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :income, :list, required: true
  attr :expense, :list, required: true
  attr :income_max, :integer, required: true
  attr :expense_max, :integer, required: true
  attr :tax_paid, :integer, required: true
  attr :shares, :list, required: true

  defp advanced_leaf(assigns) do
    ~H"""
    <div class="book__leaf">
      <h1 class="book__title">Полная опись</h1>
      <p class="book__subtitle">приход и расход, до последней монеты</p>

      <div class="fin-ledger-wrap">
        <table class="fin-ledger">
          <thead>
            <tr>
              <th>Дата</th>
              <th>С кем</th>
              <th>Статья</th>
              <th class="fin-ledger__num">Налог</th>
              <th class="fin-ledger__num">Сумма</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={e <- @entries}>
              <td class="fin-ledger__date">{e.date}</td>
              <td>{e.who}</td>
              <td><span class="fin-cat">{e.cat}</span></td>
              <td class="fin-ledger__num fin-ledger__tax">{if e.tax > 0, do: e.tax, else: "—"}</td>
              <td class={["fin-ledger__num", e.amt >= 0 && "fin-ledger__num--in"]}>
                {sign(e.amt)}{fmt(abs(e.amt))}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="fin-margin">итожено рукою казначея ✒</p>

      <div class="fin-break">
        <div class="fin-break__col">
          <h2 class="fin-h">Приход</h2>
          <div :for={{cat, sum} <- @income} class="fin-bar">
            <span class="fin-bar__label">{cat}</span>
            <span class="fin-bar__track">
              <span class="fin-bar__fill fin-bar__fill--in" style={"width:#{pct(sum, @income_max)}%"}>
              </span>
            </span>
            <span class="fin-bar__num">{fmt(sum)}</span>
          </div>
        </div>
        <div class="fin-break__col">
          <h2 class="fin-h">Расход</h2>
          <div :for={{cat, sum} <- @expense} class="fin-bar">
            <span class="fin-bar__label">{cat}</span>
            <span class="fin-bar__track">
              <span
                class="fin-bar__fill fin-bar__fill--out"
                style={"width:#{pct(sum, @expense_max)}%"}
              >
              </span>
            </span>
            <span class="fin-bar__num">{fmt(sum)}</span>
          </div>
        </div>
      </div>

      <div class="fin-treasury">
        <span class="fin-treasury__label">Уплачено в казну Эленвира</span>
        <span class="fin-treasury__sum"><span class="fin-coin">◈</span>{fmt(@tax_paid)}</span>
      </div>

      <h2 class="fin-h">Имущество и доли</h2>
      <ul class="fin-shares">
        <li :for={s <- @shares} class="fin-share">
          <div class="fin-share__body">
            <span class="fin-share__name">{s.name}</span>
            <span class="fin-share__kind">{s.kind}</span>
          </div>
          <div class="fin-share__stake">
            <span class="fin-share__ring" style={"--pct:#{s.pct}"}></span>
            <span class="fin-share__pct">{s.pct}%</span>
          </div>
        </li>
      </ul>

      <div class="fin-charity fin-charity--compact">
        <div>
          <span class="fin-charity__label">В Фонд Просвещения внесено</span>
          <span class="fin-charity__sum"><span class="fin-coin">◈</span>200</span>
        </div>
        <span class="fin-charity__title">Меценат Академии</span>
      </div>
    </div>
    """
  end

  # --- helpers -------------------------------------------------------------

  defp pct(_v, 0), do: 0
  defp pct(v, max), do: round(v / max * 100)

  defp sign(n) when n >= 0, do: "+"
  defp sign(_), do: "−"

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
end
