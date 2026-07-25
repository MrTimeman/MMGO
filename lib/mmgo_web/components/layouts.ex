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
      class="relative min-h-screen overflow-hidden bg-[#090807] text-stone-100"
    >
      <div
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_18%_8%,rgba(217,169,54,0.16),transparent_28rem),radial-gradient(circle_at_88%_72%,rgba(124,43,34,0.14),transparent_32rem),linear-gradient(145deg,#0b0907_0%,#15100a_52%,#080706_100%)]"
      >
      </div>
      <div
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 opacity-[0.16] [background-image:linear-gradient(rgba(255,255,255,0.035)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.035)_1px,transparent_1px)] [background-size:3rem_3rem] [mask-image:radial-gradient(circle_at_center,black,transparent_78%)]"
      >
      </div>

      <header class="relative z-20 border-b border-white/10 bg-black/20 backdrop-blur-xl">
        <div class="mx-auto flex min-h-18 max-w-7xl items-center justify-between gap-4 px-4 py-3 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/"}
            id="public-brand"
            class="group flex min-w-0 items-center gap-3"
          >
            <div class="relative flex size-11 shrink-0 items-center justify-center rounded-[1rem] border border-amber-300/45 bg-[conic-gradient(from_45deg,#2a1d0b,#9a6a18,#2a1d0b,#d5a72f,#2a1d0b)] p-px shadow-[0_0_2rem_rgba(217,169,54,0.12)] transition duration-300 group-hover:rotate-3 group-hover:scale-105">
              <div class="flex size-full items-center justify-center rounded-[0.94rem] bg-[#120f0b] font-[family-name:var(--font-serif)] text-lg font-black text-amber-200">
                M
              </div>
            </div>
            <div class="min-w-0 leading-none">
              <p class="truncate font-[family-name:var(--font-sans)] text-[0.62rem] font-bold uppercase tracking-[0.28em] text-amber-200/65 sm:text-[0.68rem]">
                Ministry of MaGic Online
              </p>
              <p class="mt-1.5 font-[family-name:var(--font-serif)] text-lg font-bold tracking-[0.08em] text-stone-50">
                MMGO
              </p>
            </div>
          </.link>

          <div class="flex shrink-0 items-center gap-2">
            <span class="hidden rounded-full border border-white/10 bg-white/5 px-3 py-1.5 font-[family-name:var(--font-sans)] text-[0.65rem] font-bold uppercase tracking-[0.16em] text-stone-400 sm:inline-flex">
              Closed alpha
            </span>
            <a
              id="public-bot-link"
              href="https://t.me/mmgo_bot?start=play"
              target="_blank"
              rel="noreferrer"
              class="inline-flex min-h-10 items-center gap-2 rounded-full border border-amber-300/30 bg-amber-200 px-4 font-[family-name:var(--font-sans)] text-xs font-bold text-stone-950 shadow-[0_0.75rem_2.5rem_rgba(217,169,54,0.12)] transition duration-300 hover:-translate-y-0.5 hover:bg-amber-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-200"
            >
              <.icon name="hero-paper-airplane" class="size-4" />
              <span class="hidden sm:inline">Открыть бота</span>
              <span class="sm:hidden">Играть</span>
            </a>
          </div>
        </div>
      </header>

      <main id="public-content" class="relative z-10">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>

    <div
      :if={not @public and not is_nil(@current_scope)}
      id="game-shell"
      class="game-shell"
    >
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
      class="min-h-screen bg-[#090807] text-stone-100"
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
      class="fixed bottom-4 right-4 z-40 max-w-[calc(100vw-2rem)]"
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
        class="inline-flex min-h-10 items-center gap-2 rounded-full border border-stone-600/80 bg-stone-950/90 px-3 py-2 text-xs font-medium text-stone-200 shadow-lg backdrop-blur transition enabled:hover:border-sky-300 enabled:hover:text-sky-100 disabled:cursor-not-allowed disabled:opacity-70"
      >
        <.icon name="hero-speaker-wave" class="size-4" />
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
      class="fixed left-3 right-3 top-3 z-50 flex flex-col gap-3 sm:left-auto sm:right-4 sm:top-4 sm:w-full sm:max-w-sm"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
