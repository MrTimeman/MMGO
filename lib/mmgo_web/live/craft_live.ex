defmodule MMGOWeb.CraftLive do
  @moduledoc """
  The craftsman's bench — the mundane sibling of the alchemy bench and the
  spell circle. Same ceremony arc — tag materials → charge → dim → forge →
  reveal — but fire and iron instead of glass and vapor. Crucially,
  crafting is NOT AI-driven (GDD §3.3.2): tool stats come from tables, so
  the reveal reads precise (урон · прочность · вес), not mystical.

  Design pass: hardcoded demo data, no backend wiring. GDD §8 — workshops
  are required; the tools row shows owned/missing states.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @materials [
    %{id: "ingot", name: "Железный слиток", note: "кузнечное железо"},
    %{id: "plank", name: "Дубовая доска", note: "выдержанный дуб"},
    %{id: "strap", name: "Кожаный ремень", note: "дублёная кожа"},
    %{id: "whet", name: "Точильный камень", note: "правит кромку"},
    %{id: "rivet", name: "Стальные заклёпки", note: "горсть на рукоять"}
  ]

  # Tools are gear, not consumed materials — the bench requires them present.
  # молот + тиски are owned; напильник is missing (raises quality when owned).
  @tools [
    %{id: "hammer", name: "Молот", owned: true, req: true},
    %{id: "vise", name: "Тиски", owned: true, req: true},
    %{id: "file", name: "Напильник", owned: false, req: false}
  ]

  @forge_ms 2600

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load carried materials, owned tools, workshop tier.
    {:ok,
     socket
     |> assign(:page_title, "Ремесло")
     |> assign(:materials, @materials)
     |> assign(:tools, @tools)
     |> assign(:tagged, [])
     |> assign(:intent, "")
     |> assign(:phase, :idle)
     |> assign(:result, nil)}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    tagged = socket.assigns.tagged
    tagged = if id in tagged, do: List.delete(tagged, id), else: tagged ++ [id]
    {:noreply, assign(socket, :tagged, tagged)}
  end

  @impl true
  def handle_event("untag", %{"id" => id}, socket) do
    {:noreply, assign(socket, :tagged, List.delete(socket.assigns.tagged, id))}
  end

  @impl true
  def handle_event("intent", %{"intent" => intent}, socket) do
    {:noreply, assign(socket, :intent, intent)}
  end

  @impl true
  def handle_event("forge", _params, socket) do
    if ready?(socket.assigns) do
      Process.send_after(self(), :forge_done, @forge_ms)
      {:noreply, assign(socket, :phase, :forging)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, phase: :idle, result: nil)}
  end

  @impl true
  def handle_info(:forge_done, socket) do
    {:noreply, assign(socket, phase: :result, result: forge_result(socket.assigns.tagged))}
  end

  @impl true
  def render(assigns) do
    count = length(assigns.tagged)

    assigns =
      assigns
      |> assign(:count, count)
      |> assign(:ready, ready?(assigns))
      |> assign(:fill, min(count, 4) / 4 * 100)
      |> assign(:tagged_items, Enum.map(assigns.tagged, &find_mat(&1)))

    ~H"""
    <div class="game-screen crf-screen">
      <div class={["crf-root", @phase != :idle && "crf-root--dim"]}>
        <a href={~p"/map"} class="crf-exit">&larr; выйти на карту</a>

        <.art_slot
          kind="scene"
          variant="dark"
          label="Верстак мастера — тиски, молот, заготовки"
          class="crf-art"
        />

        <header class="crf-head">
          <h1 class="crf-title">Верстак мастера</h1>
          <p class="crf-sub">Альберт Северин · кузница во Вратах Зари</p>
        </header>

        <div class={["crf-forge", @ready && "crf-forge--ready", @count > 0 && "crf-forge--live"]}>
          <div class="crf-forge__anvil">
            <div class="crf-forge__ingot" style={"--heat:#{@fill}%"}>
              <span class="crf-spark crf-spark--1"></span>
              <span class="crf-spark crf-spark--2"></span>
              <span class="crf-spark crf-spark--3"></span>
            </div>
            <span class="crf-forge__count">{@count}</span>
          </div>
        </div>

        <section class="crf-tools">
          <p class="crf-label">Инструменты</p>
          <div class="crf-tools__row">
            <span
              :for={t <- @tools}
              class={["crf-tool", (t.owned && "crf-tool--owned") || "crf-tool--missing"]}
            >
              <span class="crf-tool__mark">{if t.owned, do: "✓", else: "✕"}</span>
              {t.name}
              <span :if={not t.owned} class="crf-tool__hint">нет</span>
            </span>
          </div>
        </section>

        <section class="crf-bench">
          <p class="crf-label">На верстаке</p>
          <div class="crf-bench__row">
            <p :if={@tagged_items == []} class="crf-hint">
              Пусто. Коснитесь материала, чтобы положить заготовку на верстак.
            </p>
            <button
              :for={it <- @tagged_items}
              type="button"
              class="crf-chip"
              phx-click="untag"
              phx-value-id={it.id}
            >
              {it.name}<span class="crf-chip__x">×</span>
            </button>
          </div>
        </section>

        <section class="crf-shelf">
          <p class="crf-label">Материалы в котомке</p>
          <div class="crf-strip">
            <button
              :for={it <- @materials}
              type="button"
              class={["crf-mat", it.id in @tagged && "crf-mat--on"]}
              phx-click="toggle"
              phx-value-id={it.id}
            >
              <span class="crf-mat__glyph">◆</span>
              <span class="crf-mat__name">{it.name}</span>
              <span class="crf-mat__note">{it.note}</span>
            </button>
          </div>
        </section>

        <section class="crf-intent-box">
          <p class="crf-label">Замысел</p>
          <form phx-change="intent">
            <textarea
              name="intent"
              class="crf-intent"
              rows="3"
              phx-debounce="150"
              placeholder="короткий клинок под левую руку, лёгкий и цепкий в рукояти…"
            >{@intent}</textarea>
          </form>
        </section>

        <button
          type="button"
          class={["crf-do", @ready && "crf-do--ready"]}
          phx-click="forge"
          disabled={!@ready}
        >
          Ковать
        </button>

        <div class="crf-notes">
          <p class="crf-note">Утомление · 5 &nbsp;•&nbsp; время ковки · 4 часа</p>
          <p class="crf-note crf-note--req">
            ◆ Требуется кузница при вашей базе · молот и тиски (§8)
          </p>
        </div>
      </div>

      <%= if @phase == :forging do %>
        <div class="crf-ritual">
          <div class="crf-ritual__anvil">
            <div class="crf-ritual__bar"></div>
            <span class="crf-ritual__spark"></span>
            <span class="crf-ritual__spark"></span>
            <span class="crf-ritual__spark"></span>
          </div>
          <p class="crf-ritual__caption">Куётся…</p>
        </div>
      <% end %>

      <%= if @phase == :result and @result do %>
        <div class="crf-reveal" phx-click="reset">
          <div class={["crf-item", (@result.ok && "crf-item--ok") || "crf-item--fail"]}>
            <p class="crf-item__eyebrow">
              {if @result.ok, do: "изделие занесено в опись", else: "брак"}
            </p>
            <h2 class="crf-item__name">{@result.name}</h2>
            <p class="crf-item__kind">{@result.kind}</p>
            <p class="crf-item__desc">{@result.desc}</p>

            <dl class="crf-item__stats">
              <div :for={{label, value} <- @result.stats} class="crf-item__stat">
                <dt class="crf-item__stat-k">{label}</dt>
                <dd class="crf-item__stat-v">{value}</dd>
              </div>
            </dl>

            <button type="button" class="crf-item__again" phx-click="reset">
              ← вернуться к верстаку
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- helpers -------------------------------------------------------------

  defp ready?(assigns) do
    tools_ok = Enum.all?(@tools, fn t -> not t.req or t.owned end)
    length(assigns.tagged) >= 1 and String.trim(assigns.intent) != "" and tools_ok
  end

  defp find_mat(id), do: Enum.find(@materials, &(&1.id == id))

  # Deterministic-feeling outcome (no AI): a single material can't be
  # worked into a sound piece — it cracks under the hammer. Two or more
  # yield a finished tool with fixed table stats.
  defp forge_result(tagged) when length(tagged) == 1 do
    %{
      ok: false,
      name: "Треснувшая поковка",
      kind: "брак · не годна в дело",
      desc:
        "Одной заготовки мало — под молотом металл пошёл трещиной по всей длине. " <>
          "В переплавку.",
      stats: [{"Урон", "—"}, {"Прочность", "0 / 0"}, {"Вес", "0.9 ст."}]
    }
  end

  defp forge_result(_tagged) do
    %{
      ok: true,
      name: "Кинжал левой руки",
      kind: "оружие ближнего боя · для тумана",
      desc:
        "Короткий парный клинок под левую руку: узкий, цепкий в хвате, " <>
          "хорош в тесноте, где длинному мечу не размахнуться.",
      stats: [
        {"Урон", "6–9 (укол)"},
        {"Прочность", "48 / 48"},
        {"Вес", "1.1 стоуна"},
        {"Хват", "лёгкий · левая рука"}
      ]
    }
  end
end
