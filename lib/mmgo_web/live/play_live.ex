defmodule MMGOWeb.PlayLive do
  use MMGOWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "MMGO")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main
        id="play-shell"
        class="play-shell flex h-[100dvh] flex-col overflow-hidden"
      >
        <header
          id="play-topbar"
          class="play-topbar relative z-20 flex shrink-0 items-center justify-between border-b px-4 py-3"
        >
          <div>
            <p class="play-kicker font-['Cinzel'] text-[0.62rem] uppercase tracking-[0.22em]">
              Ministry of Magic Online
            </p>
            <h1 class="font-['Cinzel'] text-xl font-bold tracking-wide">MMGO</h1>
          </div>
          <div
            id="game-time-pill"
            class="play-time-pill rounded-full border px-3 py-1 text-right"
          >
            <p class="font-mono text-[0.62rem] uppercase tracking-[0.16em]">—</p>
            <p class="text-xs">загрузка...</p>
          </div>
        </header>

        <section class="relative min-h-0 flex-1">
          <.map_screen />
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp map_screen(assigns) do
    ~H"""
    <div
      id="map-screen"
      class="absolute inset-0"
      phx-hook="Map"
      phx-update="ignore"
      data-map-src={~p"/images/mmgo2-map.png"}
      data-state-path={~p"/api/play/state"}
      data-journeys-path={~p"/api/play/journeys"}
      data-journey-plans-path={~p"/api/play/journey-plans"}
      data-fast-arrive-path={~p"/api/play/demo/arrive"}
    >
    </div>
    """
  end
end
