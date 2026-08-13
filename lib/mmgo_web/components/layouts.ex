defmodule MMGOWeb.Layouts do
  @moduledoc """
  Shared layouts and layout helpers.
  """

  use MMGOWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :atmosphere, :map,
    default: nil,
    doc: "optional server-derived semantic audio state for an in-world screen"

  attr :public, :boolean,
    default: false,
    doc: "renders the immersive public shell instead of the authenticated game chrome"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      :if={@public}
      id="public-shell"
      class="public-shell"
    >
      <header class="public-header">
        <div class="public-header__rail">
          <.link
            navigate={~p"/"}
            id="public-brand"
            class="public-brand"
          >
            <span class="public-brand__seal">M</span>
            <span class="public-brand__copy">
              <small>Министерство Магии Онлайн</small>
              <strong>MMGO</strong>
            </span>
          </.link>

          <div class="public-header__actions">
            <span class="public-alpha-tag">закрытая альфа</span>
            <a
              id="public-bot-link"
              href="https://t.me/mmgo_bot?start=play"
              target="_blank"
              rel="noreferrer"
              class="public-bot-button"
            >
              <.icon name="hero-paper-airplane" />
              <span>Открыть бота</span>
            </a>
          </div>
        </div>
      </header>

      <main id="public-content" class="public-content">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>

    <div
      :if={not @public and not is_nil(@current_scope)}
      id="game-shell"
      class="game-shell"
    >
      <%!-- The Arena header carries its own #arena-switch-mode link, and this
            floating pill would sit on top of it. --%>
      <nav
        :if={@current_scope[:game_mode] != :arena}
        id="game-mode-switcher"
        aria-label="Режим игры"
      >
        <.link
          id="open-game-mode-picker"
          navigate={~p"/mode"}
          class="fixed right-[calc(var(--safe-right)+0.75rem)] top-[calc(var(--safe-top)+0.75rem)] z-[90] flex min-h-9 items-center gap-1.5 rounded-full border border-amber-200/25 bg-stone-950/75 px-3 font-sans text-xs font-semibold text-amber-50/90 shadow-lg shadow-black/25 backdrop-blur transition hover:-translate-y-0.5 hover:border-amber-200/50 hover:bg-stone-900/90"
        >
          <.icon name="hero-arrows-right-left" class="size-4 text-amber-300" /> Сменить режим
        </.link>
      </nav>

      <main id="game-content" class="game-content">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
      <.atmosphere_audio
        :if={@atmosphere && Map.get(@atmosphere, :available?, false)}
        cue={@atmosphere}
      />
    </div>

    <div
      :if={not @public and is_nil(@current_scope)}
      class="anonymous-shell"
    >
      <main>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :cue, :map, required: true

  defp atmosphere_audio(assigns) do
    ~H"""
    <aside
      id="atmosphere-audio"
      phx-hook="AtmosphereAudio"
      data-ambient-cue={@cue.ambient_cue}
      data-ambient-source={@cue.ambient_source}
      data-major-event-cue={@cue.major_event_cue}
      data-event-source={@cue.event_source}
      data-active-cue={@cue.active_cue}
      data-active-source={@cue.active_source}
      data-loop={to_string(@cue.loop?)}
      data-label={@cue.label}
      class="atmo-control"
      aria-label="Звуковая атмосфера мира"
    >
      <audio id="atmosphere-audio-player" preload="none" aria-hidden="true"></audio>
      <button
        id="atmosphere-audio-toggle"
        type="button"
        data-atmosphere-toggle
        disabled={not @cue.available?}
        aria-pressed="false"
        aria-describedby="atmosphere-audio-description"
        class="atmo-control__button"
      >
        <.icon name="hero-speaker-wave" class="atmo-control__icon" />
        <span data-atmosphere-status>
          <%= if @cue.available? do %>
            Звук мира: выкл.
          <% else %>
            Звук: запись не подключена
          <% end %>
        </span>
      </button>
      <p id="atmosphere-audio-description" class="sr-only" aria-live="polite">
        Семантическая сцена: {@cue.label}.
        <%= if @cue.major_event_cue do %>
          Событие: {@cue.major_event_cue}.
        <% end %>
        <%= if not @cue.available? do %>
          Запись для этой сцены пока не настроена.
        <% end %>
      </p>
    </aside>
    """
  end

  # ---------------------------------------------------------------------------
  # Game layout — full-screen shell used by all in-game LiveViews.
  # Usage: <Layouts.game flash={@flash}>...</Layouts.game>
  # ---------------------------------------------------------------------------

  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def game(assigns) do
    ~H"""
    <div id="game-root" class="game-root">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="game-flash-stack"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Связь с миром потеряна"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Пытаемся восстановить связь
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Мир временно не отвечает"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Пытаемся восстановить связь
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
