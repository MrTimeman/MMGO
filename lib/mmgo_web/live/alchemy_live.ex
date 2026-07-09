defmodule MMGOWeb.AlchemyLive do
  @moduledoc """
  The alchemist's bench — the ritual sibling of the spell circle
  (`spellbook_live.ex` + `spell-circle.js`). Same ceremony arc — fill →
  charge → dim → work → reveal — in a different medium: glass and vapor
  instead of ink and runes. Where the caster picks constrained Latin
  slots, the alchemist tags freeform inventory ingredients and writes a
  plain-language intent.

  Design pass: hardcoded demo data, no backend wiring. Ingredient set is
  kept consistent with `/inventory` (клык теневого волка, пепел саламандры…).
  GDD §8 — alchemy requires a workshop at the player's base.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # Ingredients the player carries — a superset of the alchemy items shown
  # on /inventory, plies a few more so the bench feels stocked.
  @ingredients [
    %{id: "fang", name: "Клык теневого волка", note: "стойкость к порче"},
    %{id: "ash", name: "Пепел саламандры", note: "огонь, что не гаснет"},
    %{id: "herb", name: "Болотная трава", note: "горькая зелень топей"},
    %{id: "dew", name: "Чистая роса", note: "собрана до рассвета"},
    %{id: "root", name: "Корень мандрагоры", note: "кричит, если вырвать"},
    %{id: "moon", name: "Толчёный лунный камень", note: "холодное серебро"}
  ]

  @brew_ms 2600

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load carried ingredients, workshop tier, fatigue budget.
    {:ok,
     socket
     |> assign(:page_title, "Алхимия")
     |> assign(:ingredients, @ingredients)
     |> assign(:tagged, [])
     |> assign(:intent, "")
     |> assign(:phase, :idle)
     |> assign(:result, nil)}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    tagged = socket.assigns.tagged

    tagged =
      if id in tagged, do: List.delete(tagged, id), else: tagged ++ [id]

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
  def handle_event("brew", _params, socket) do
    if ready?(socket.assigns) do
      # Speak-the-incantation moment: the room goes dark now and holds
      # through the brew (a fake ~2.6s round-trip via Process.send_after),
      # exactly like the spell circle holds its blackout until the AI answers.
      Process.send_after(self(), :brew_done, @brew_ms)
      {:noreply, assign(socket, :phase, :brewing)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, phase: :idle, result: nil)}
  end

  @impl true
  def handle_info(:brew_done, socket) do
    result = brew_result(socket.assigns.tagged)
    {:noreply, assign(socket, phase: :result, result: result)}
  end

  @impl true
  def render(assigns) do
    count = length(assigns.tagged)

    assigns =
      assigns
      |> assign(:count, count)
      |> assign(:ready, ready?(assigns))
      |> assign(:fill, min(count, 4) / 4 * 100)
      |> assign(:tagged_items, Enum.map(assigns.tagged, &find_ing(&1)))

    ~H"""
    <div class="game-screen alc-screen">
      <div class={["alc-root", @phase != :idle && "alc-root--dim"]}>
        <a href={~p"/map"} class="alc-exit">&larr; выйти на карту</a>

        <.art_slot
          kind="scene"
          variant="dark"
          label="Алхимический стол — реторты и горелка"
          class="alc-art"
        />

        <header class="alc-head">
          <h1 class="alc-title">Алхимический стол</h1>
          <p class="alc-sub">Альберт Северин · мастерская во Вратах Зари</p>
        </header>

        <div class={["alc-vessel", @ready && "alc-vessel--ready", @count > 0 && "alc-vessel--live"]}>
          <div class="alc-vessel__flask">
            <div class="alc-vessel__brew" style={"--fill:#{@fill}%"}>
              <span class="alc-bubble alc-bubble--1"></span>
              <span class="alc-bubble alc-bubble--2"></span>
              <span class="alc-bubble alc-bubble--3"></span>
            </div>
            <span class="alc-vessel__count">{@count}</span>
          </div>
          <span class="alc-vessel__flame"></span>
        </div>

        <section class="alc-table">
          <p class="alc-label">На столе</p>
          <div class="alc-table__row">
            <p :if={@tagged_items == []} class="alc-hint">
              Ничего не выбрано. Коснитесь ингредиента, чтобы положить его на стол.
            </p>
            <button
              :for={it <- @tagged_items}
              type="button"
              class="alc-chip"
              phx-click="untag"
              phx-value-id={it.id}
            >
              {it.name}<span class="alc-chip__x">×</span>
            </button>
          </div>
        </section>

        <section class="alc-shelf">
          <p class="alc-label">Ингредиенты в котомке</p>
          <div class="alc-strip">
            <button
              :for={it <- @ingredients}
              type="button"
              class={["alc-ing", it.id in @tagged && "alc-ing--on"]}
              phx-click="toggle"
              phx-value-id={it.id}
            >
              <span class="alc-ing__glyph">❧</span>
              <span class="alc-ing__name">{it.name}</span>
              <span class="alc-ing__note">{it.note}</span>
            </button>
          </div>
        </section>

        <section class="alc-intent-box">
          <p class="alc-label">Замысел</p>
          <form phx-change="intent">
            <textarea
              name="intent"
              class="alc-intent"
              rows="3"
              phx-debounce="150"
              placeholder="хочу зелье, что согреет в стужу и прибавит сил…"
            >{@intent}</textarea>
          </form>
        </section>

        <button
          type="button"
          class={["alc-brew", @ready && "alc-brew--ready"]}
          phx-click="brew"
          disabled={!@ready}
        >
          Варить
        </button>

        <div class="alc-notes">
          <p class="alc-note">Утомление · 4 &nbsp;•&nbsp; время варки · 2 часа</p>
          <p class="alc-note alc-note--req">
            ◆ Требуется алхимическая мастерская при вашей базе (§8)
          </p>
        </div>
      </div>

      <%= if @phase == :brewing do %>
        <div class="alc-ritual">
          <div class="alc-ritual__orb">
            <span class="alc-ritual__bubble"></span>
            <span class="alc-ritual__bubble"></span>
            <span class="alc-ritual__bubble"></span>
          </div>
          <p class="alc-ritual__caption">Варится…</p>
        </div>
      <% end %>

      <%= if @phase == :result and @result do %>
        <div class="alc-reveal" phx-click="reset">
          <div class={["alc-potion", (@result.ok && "alc-potion--ok") || "alc-potion--fail"]}>
            <p class="alc-potion__eyebrow">
              {if @result.ok, do: "рецепт записан в книгу", else: "неудача"}
            </p>
            <h2 class="alc-potion__latin">{@result.latin}</h2>
            <p class="alc-potion__name">«{@result.name}»</p>
            <p class="alc-potion__desc">{@result.desc}</p>

            <ul class="alc-potion__fx">
              <li :for={fx <- @result.effects} class="alc-potion__fx-item">{fx}</li>
            </ul>

            <button type="button" class="alc-potion__again" phx-click="reset">
              ← вернуться к столу
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- helpers -------------------------------------------------------------

  defp ready?(assigns) do
    length(assigns.tagged) >= 1 and String.trim(assigns.intent) != ""
  end

  defp find_ing(id), do: Enum.find(@ingredients, &(&1.id == id))

  # Demo outcome logic: a single ingredient can't hold a brew together, so
  # it curdles — the failure state the brief asks us to show. Two or more
  # settle into a proper potion.
  defp brew_result(tagged) when length(tagged) == 1 do
    %{
      ok: false,
      latin: "Coagulatum",
      name: "Зелье свернулось",
      desc:
        "Один ингредиент не держит варки — смесь помутнела, свернулась и осела " <>
          "бурым сгустком. Из реторты тянет едким дымом.",
      effects: ["◦ реагенты потрачены впустую", "◦ котелок придётся отчищать"]
    }
  end

  defp brew_result(_tagged) do
    %{
      ok: true,
      latin: "Potio Ignis Tepidi",
      name: "Зелье тёплого огня",
      desc:
        "Густой янтарный настой, что дышит теплом даже в лютую стужу. " <>
          "Пьётся горько, но по жилам растекается ровный жар и новая сила.",
      effects: [
        "◦ согревает в стужу · 3 хода",
        "◦ + выносливость · малое",
        "◦ стойкость к холоду · пока действует"
      ]
    }
  end
end
