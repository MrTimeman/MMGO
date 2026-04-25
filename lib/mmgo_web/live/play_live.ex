defmodule MMGOWeb.PlayLive do
  use MMGOWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "MMGO")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="play-shell" class="min-h-screen overflow-hidden bg-[#0d0a07] text-[#e8d5b0]">
        <div class="mx-auto flex min-h-screen w-full max-w-[460px] flex-col border-x border-[#3b2b1e] bg-[#17110c] shadow-[0_0_70px_rgba(0,0,0,0.65)] sm:min-h-[920px] sm:my-6 sm:rounded-[2rem] sm:border">
          <header
            id="play-topbar"
            class="relative z-20 flex items-center justify-between border-b border-[#3f2f20] bg-[#251b12]/95 px-4 py-3"
          >
            <div>
              <p class="font-['Cinzel'] text-[0.62rem] uppercase tracking-[0.22em] text-[#7a6030]">
                Ministry of Magic Online
              </p>
              <h1 class="font-['Cinzel'] text-xl font-bold tracking-wide text-[#e8c46a]">MMGO</h1>
            </div>
            <div
              id="game-time-pill"
              class="rounded-full border border-[#5f462b] bg-[#2e2418] px-3 py-1 text-right"
            >
              <p class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[#7a6030]">—</p>
              <p class="text-xs text-[#e8d5b0]">загрузка...</p>
            </div>
          </header>

          <section class="relative min-h-0 flex-1 overflow-hidden">
            <.map_screen />
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp map_screen(assigns) do
    ~H"""
    <div
      id="map-screen"
      class="relative h-full min-h-[720px] overflow-hidden"
      phx-hook="Map"
      phx-update="ignore"
      data-map-src={~p"/images/mmgo2-map.png"}
      data-state-path={~p"/api/play/state"}
      data-journeys-path={~p"/api/play/journeys"}
      data-fast-arrive-path={~p"/api/play/demo/arrive"}
    >
    </div>
    """
  end
end
