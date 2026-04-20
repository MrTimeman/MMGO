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

  attr :variant, :atom,
    default: :marketing,
    values: [:marketing, :game],
    doc: "layout variant used to render marketing or in-game surfaces"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= case @variant do %>
      <% :game -> %>
        <div class="min-h-screen bg-[var(--color-bg)] text-[var(--color-text)]">
          <main class="min-h-screen">
            {render_slot(@inner_block)}
          </main>

          <.flash_group flash={@flash} id="game-flash-group" />
        </div>
      <% :marketing -> %>
        <div class="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(251,191,36,0.2),_transparent_22rem),linear-gradient(180deg,_#f7f1e8_0%,_#f3ede2_42%,_#efe7da_100%)] text-stone-900">
          <header class="border-b border-stone-200/80 bg-white/70 backdrop-blur">
            <div class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between lg:px-8">
              <.link navigate={~p"/"} class="flex items-center gap-3">
                <div class="flex size-11 items-center justify-center rounded-2xl border border-amber-300 bg-amber-100 text-sm font-black uppercase tracking-[0.25em] text-amber-950">
                  M
                </div>
                <div>
                  <p class="text-sm font-semibold uppercase tracking-[0.26em] text-stone-500">
                    Ministry of MaGic Online
                  </p>
                  <p class="text-lg font-semibold text-stone-950">MMGO</p>
                </div>
              </.link>

              <nav class="flex flex-wrap items-center gap-3 text-sm text-stone-600">
                <a
                  href={~p"/healthz"}
                  class="rounded-full border border-stone-300 bg-white px-4 py-2 font-medium transition hover:-translate-y-0.5 hover:border-stone-900 hover:text-stone-950"
                >
                  Health
                </a>
                <a
                  href="https://core.telegram.org/bots/api"
                  class="rounded-full border border-stone-300 bg-white px-4 py-2 font-medium transition hover:-translate-y-0.5 hover:border-stone-900 hover:text-stone-950"
                >
                  Telegram API
                </a>
                <a
                  href="https://hexdocs.pm/phoenix_live_view/welcome.html"
                  class="rounded-full border border-stone-900 bg-stone-900 px-4 py-2 font-medium text-white transition hover:-translate-y-0.5 hover:bg-black"
                >
                  LiveView
                </a>
              </nav>
            </div>
          </header>

          <main class="px-4 py-10 sm:px-6 sm:py-14 lg:px-8">
            <div class="mx-auto max-w-6xl space-y-4">
              {render_slot(@inner_block)}
            </div>
          </main>

          <.flash_group flash={@flash} />
        </div>
    <% end %>
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
    <.app flash={@flash} variant={:game}>
      <div id="game-root" class="game-root">
        {render_slot(@inner_block)}
      </div>
    </.app>
    """
  end

  # ---------------------------------------------------------------------------

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed right-4 top-4 z-50 flex max-w-sm flex-col gap-3">
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
