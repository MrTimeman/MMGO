defmodule MMGOWeb.BaseLive do
  @moduledoc """
  The player's base interior (GDD §5.3) — the home room where loot is
  stored and where spell composition, alchemy, crafting and rest happen.

  Design pass: hardcoded demo data, no backend wiring. The screen is a
  lived-in room rendered as a world (dark stone) surface; each station is
  a diegetic doorway to its own screen. A demo toggle switches between the
  two ways to own a base (§5.3): a bought city apartment vs. a hut built
  near the Tower — this changes the scene, the flavour and the danger note.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # Two base kinds a player can own (GDD §5.3). Everything that differs
  # between "safe city flat" and "dangerous Tower-side hut" lives here so
  # the demo toggle is a single assign flip.
  @bases %{
    apartment: %{
      name: "Кабинет при свечах",
      kind_label: "Купленная квартира",
      location: "Врата Зари · Княжество Эленвир",
      art_label: "Кабинет заклинателя при свечах — квартира во Вратах Зари",
      upkeep: "12 монет в месяц",
      upkeep_note: "Городская подать за жильё — списывается сама.",
      safe: true,
      danger: "Город под защитой. За этими стенами дуэлей не ведут, разбойники сюда не ходят.",
      distance: "До Башни — восемь дней пути через глушь.",
      storage: %{items: 34, weight: "18.4", capacity: "40.0", value: "2 190"}
    },
    hut: %{
      name: "Хижина под Башней",
      kind_label: "Постройка у стен",
      location: "Отроги Башни · дикие земли",
      art_label: "Хижина чародея под стенами Башни — очаг и грубый стол",
      upkeep: "нет подати",
      upkeep_note: "Землю никто не мерит — но и защиты закона здесь нет.",
      safe: false,
      danger: "Дорога сюда кишит разбойниками, и дуэль могут навязать у самого порога.",
      distance: "До врат Башни — полдня пешком.",
      storage: %{items: 21, weight: "11.2", capacity: "40.0", value: "1 460"}
    }
  }

  # Grimoires kept on the shelf at home; exactly one is "в дороге" — taken
  # into the field, so it is not on the shelf right now (GDD §7.2: one in
  # combat, the rest stored at base).
  @grimoires [
    %{name: "Гримуар Хаоса", seals: 23, hue: 320, status: :carried},
    %{name: "Малый гримуар", seals: 7, hue: 45, status: :shelf},
    %{name: "Старый травник", seals: 10, hue: 140, status: :sealed}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load the character's real base, storage and grimoires.
    {:ok,
     socket
     |> assign(:page_title, "База")
     |> assign(:base_kind, :apartment)
     |> assign(:grimoires, @grimoires)
     |> assign(:resting, false)
     |> assign(:rested, false)}
  end

  @impl true
  def handle_event("set_base", %{"kind" => kind}, socket) do
    kind = String.to_existing_atom(kind)

    {:noreply,
     socket
     |> assign(:base_kind, kind)
     |> assign(:resting, false)
     |> assign(:rested, false)}
  end

  @impl true
  def handle_event("rest", _params, socket) do
    if socket.assigns.resting do
      {:noreply, socket}
    else
      # Fake the passing of a night — the candle dims, then we wake rested.
      Process.send_after(self(), :rested, 2200)
      {:noreply, socket |> assign(:resting, true) |> assign(:rested, false)}
    end
  end

  @impl true
  def handle_event("wake", _params, socket) do
    {:noreply, socket |> assign(:resting, false) |> assign(:rested, false)}
  end

  @impl true
  def handle_info(:rested, socket) do
    {:noreply, socket |> assign(:resting, false) |> assign(:rested, true)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :base, Map.fetch!(@bases, assigns.base_kind))

    ~H"""
    <div class="game-screen">
      <div class={["bse-root", @resting && "bse-root--resting"]}>
        <a href={~p"/map"} class="bse-exit">&larr; выйти на карту</a>

        <header class="bse-hero">
          <.art_slot kind="hero" variant="dark" label={@base.art_label} class="bse-hero__art" />
          <div class="bse-hero__veil"></div>
          <div class="bse-hero__caption">
            <span class="bse-hero__kind">{@base.kind_label}</span>
            <h1 class="bse-hero__name">{@base.name}</h1>
            <p class="bse-hero__where">{@base.location}</p>
          </div>
          <span class="bse-candle" aria-hidden="true"></span>
        </header>

        <div class="bse-toggle" role="group" aria-label="Выбор базы">
          <button
            type="button"
            class={["bse-toggle__opt", @base_kind == :apartment && "bse-toggle__opt--on"]}
            phx-click="set_base"
            phx-value-kind="apartment"
          >
            Квартира в городе
          </button>
          <button
            type="button"
            class={["bse-toggle__opt", @base_kind == :hut && "bse-toggle__opt--on"]}
            phx-click="set_base"
            phx-value-kind="hut"
          >
            Хижина у Башни
          </button>
        </div>

        <section class="bse-status">
          <div class="bse-status__row">
            <span class="bse-status__key">Подать</span>
            <span class="bse-status__val">{@base.upkeep}</span>
          </div>
          <p class="bse-status__note">{@base.upkeep_note}</p>

          <div class={["bse-ward", @base.safe && "bse-ward--safe"]}>
            <span class="bse-ward__sigil">{if @base.safe, do: "❖", else: "⚔"}</span>
            <div>
              <p class="bse-ward__title">
                {if @base.safe,
                  do: "База неприкосновенна",
                  else: "База неприкосновенна — но путь опасен"}
              </p>
              <p class="bse-ward__body">
                Ваши трофеи здесь не отнять: жилище защищено само по себе. {@base.danger}
              </p>
              <p class="bse-ward__dist">{@base.distance}</p>
            </div>
          </div>
        </section>

        <section class="bse-stations">
          <h2 class="bse-sec-title">Комната</h2>

          <.station
            glyph="⊟"
            title="Хранилище"
            desc="Ваши трофеи и припасы под замком."
            href={~p"/inventory"}
          >
            <:meta>{@base.storage.items} предметов</:meta>
            <:meta>вес {@base.storage.weight} / {@base.storage.capacity}</:meta>
            <:meta><span class="bse-coin">◈</span>{@base.storage.value}</:meta>
          </.station>

          <.station
            glyph="✶"
            title="Стол заклинателя"
            desc="Начертить печать, сплести новое заклинание."
            href={~p"/spellbook"}
          >
            <:meta>гримуаров дома: {shelf_count(@grimoires)}</:meta>
          </.station>

          <.station
            glyph="⚗"
            title="Алхимический стол"
            desc="Варить зелья и снадобья из ингредиентов."
            href={~p"/alchemy"}
          >
            <:meta>реторта холодна</:meta>
          </.station>

          <.station
            glyph="⚒"
            title="Верстак"
            desc="Ковать и чинить снаряжение."
            href={~p"/craft"}
          >
            <:meta>инструменты в порядке</:meta>
          </.station>

          <.station
            glyph="❧"
            title="Счётная книга"
            desc="Доходы, траты и подати вашего хозяйства."
            href={~p"/finance"}
          >
            <:meta><span class="bse-coin">◈</span>2 340 в казне</:meta>
          </.station>

          <div class="bse-station bse-station--rest">
            <span class="bse-station__glyph">☾</span>
            <div class="bse-station__body">
              <span class="bse-station__title">Отдых</span>
              <p class="bse-station__desc">
                <%= cond do %>
                  <% @resting -> %>
                    Свеча оплывает, вы засыпаете…
                  <% @rested -> %>
                    Вы отдохнули. Усталость снята, силы восполнены.
                  <% true -> %>
                    Задуть свечу и переждать ночь у очага.
                <% end %>
              </p>
            </div>
            <%= if @rested do %>
              <button type="button" class="bse-station__act" phx-click="wake">Проснуться</button>
            <% else %>
              <button
                type="button"
                class="bse-station__act bse-station__act--rest"
                phx-click="rest"
                disabled={@resting}
              >
                {if @resting, do: "…", else: "Отдохнуть"}
              </button>
            <% end %>
          </div>
        </section>

        <section class="bse-shelf">
          <h2 class="bse-sec-title">Полка гримуаров</h2>
          <div class="bse-shelf__books">
            <div
              :for={g <- @grimoires}
              class={[
                "bse-book",
                g.status == :carried && "bse-book--away",
                g.status == :sealed && "bse-book--sealed"
              ]}
              style={"--book-hue: #{g.hue}"}
            >
              <span class="bse-book__spine">{g.name}</span>
              <span class="bse-book__seals">{g.seals} печатей</span>
              <span :if={g.status == :carried} class="bse-book__tag">в дороге</span>
              <span :if={g.status == :sealed} class="bse-book__tag bse-book__tag--seal">
                запечатан
              </span>
            </div>
          </div>
          <p class="bse-shelf__note">
            «Гримуар Хаоса» взят в дорогу — в бою при вас лишь он. Остальные ждут на полке.
          </p>
          <div class="bse-shelf__plank"></div>
        </section>

        <%= if @resting or @rested do %>
          <div class="bse-veil" aria-hidden="true"></div>
        <% end %>
        <div :if={@rested} class="bse-toast">Вы отдохнули ✦</div>
      </div>
    </div>
    """
  end

  # --- station row --------------------------------------------------------

  attr :glyph, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true
  attr :href, :string, required: true
  slot :meta

  defp station(assigns) do
    ~H"""
    <.link navigate={@href} class="bse-station">
      <span class="bse-station__glyph">{@glyph}</span>
      <div class="bse-station__body">
        <span class="bse-station__title">{@title}</span>
        <p class="bse-station__desc">{@desc}</p>
        <div :if={@meta != []} class="bse-station__meta">
          <span :for={m <- @meta} class="bse-station__chip">{render_slot(m)}</span>
        </div>
      </div>
      <span class="bse-station__arrow">→</span>
    </.link>
    """
  end

  defp shelf_count(grimoires), do: Enum.count(grimoires, &(&1.status != :carried))
end
