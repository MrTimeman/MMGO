defmodule MMGOWeb.GameEntryLive do
  use MMGOWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:form, to_form(%{"init_data" => ""}, as: :telegram_auth))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} public={true}>
      <section
        id="game-entry-screen"
        class="relative isolate flex min-h-[calc(100svh-4.5rem)] items-center overflow-hidden px-4 py-8 sm:px-6 sm:py-12 lg:px-8"
      >
        <div
          aria-hidden="true"
          class="pointer-events-none absolute left-[8%] top-[12%] size-64 rounded-full border border-amber-300/10 shadow-[0_0_7rem_rgba(217,169,54,0.12),inset_0_0_5rem_rgba(217,169,54,0.05)] sm:size-96"
        >
        </div>
        <div
          aria-hidden="true"
          class="pointer-events-none absolute bottom-[8%] right-[5%] size-48 rotate-45 rounded-[3rem] border border-rose-300/10 sm:size-72"
        >
        </div>

        <div class="relative mx-auto grid w-full max-w-6xl gap-8 lg:grid-cols-[minmax(0,1.15fr)_minmax(22rem,0.85fr)] lg:items-center lg:gap-16">
          <div class="max-w-2xl">
            <div class="inline-flex items-center gap-2 rounded-full border border-amber-200/15 bg-amber-200/5 px-3 py-1.5 font-[family-name:var(--font-sans)] text-[0.65rem] font-bold uppercase tracking-[0.2em] text-amber-200/70">
              <span class="size-1.5 rounded-full bg-amber-300 shadow-[0_0_0.8rem_rgba(252,211,77,0.8)]">
              </span>
              Public alpha
            </div>

            <h1 class="mt-6 max-w-xl font-[family-name:var(--font-serif)] text-4xl font-bold leading-[0.98] tracking-[-0.035em] text-stone-50 sm:text-6xl lg:text-7xl">
              Ministry of
              <span class="block bg-gradient-to-r from-amber-200 via-amber-400 to-orange-300 bg-clip-text text-transparent">
                MaGic Online
              </span>
            </h1>

            <p class="mt-6 max-w-xl font-[family-name:var(--font-sans)] text-base leading-7 text-stone-300/80 sm:text-lg sm:leading-8">
              Многопользовательская RPG в Telegram. Один персонаж, общий мир и серверные игровые правила.
            </p>

            <div class="mt-8 grid max-w-xl grid-cols-3 gap-2 sm:gap-3">
              <div class="rounded-2xl border border-white/10 bg-white/[0.035] p-3 sm:p-4">
                <.icon name="hero-sparkles" class="size-5 text-amber-300" />
                <p class="mt-3 font-[family-name:var(--font-sans)] text-[0.66rem] font-bold uppercase tracking-[0.14em] text-stone-300 sm:text-xs">
                  Заклинания
                </p>
              </div>
              <div class="rounded-2xl border border-white/10 bg-white/[0.035] p-3 sm:p-4">
                <.icon name="hero-globe-europe-africa" class="size-5 text-amber-300" />
                <p class="mt-3 font-[family-name:var(--font-sans)] text-[0.66rem] font-bold uppercase tracking-[0.14em] text-stone-300 sm:text-xs">
                  Общий мир
                </p>
              </div>
              <div class="rounded-2xl border border-white/10 bg-white/[0.035] p-3 sm:p-4">
                <.icon name="hero-scale" class="size-5 text-amber-300" />
                <p class="mt-3 font-[family-name:var(--font-sans)] text-[0.66rem] font-bold uppercase tracking-[0.14em] text-stone-300 sm:text-xs">
                  PvE / PvP
                </p>
              </div>
            </div>
          </div>

          <div
            id="telegram-auth-root"
            class="relative overflow-hidden rounded-[2rem] border border-amber-200/20 bg-[#17120d]/90 p-1 shadow-[0_2rem_6rem_rgba(0,0,0,0.45),0_0_4rem_rgba(217,169,54,0.06)] backdrop-blur-xl"
          >
            <div
              aria-hidden="true"
              class="pointer-events-none absolute inset-x-12 top-0 h-px bg-gradient-to-r from-transparent via-amber-200/70 to-transparent"
            >
            </div>
            <div class="rounded-[1.7rem] border border-white/[0.055] bg-[radial-gradient(circle_at_80%_0%,rgba(217,169,54,0.11),transparent_14rem)] p-6 sm:p-8">
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="font-[family-name:var(--font-sans)] text-[0.66rem] font-bold uppercase tracking-[0.22em] text-amber-300/70">
                    Telegram auth
                  </p>
                  <h2 class="mt-3 font-[family-name:var(--font-serif)] text-3xl font-bold tracking-[-0.02em] text-stone-50">
                    Войти в MMGO
                  </h2>
                </div>
                <div class="flex size-11 shrink-0 items-center justify-center rounded-2xl border border-amber-200/15 bg-amber-200/5 text-amber-200">
                  <.icon name="hero-key" class="size-5" />
                </div>
              </div>

              <.form
                for={@form}
                id="telegram-auth-form"
                action={~p"/auth/telegram"}
                method="post"
                phx-hook="TelegramAuth"
                phx-update="ignore"
                class="mt-8"
              >
                <.input field={@form[:init_data]} type="hidden" id="telegram-auth-init-data" />

                <div id="telegram-auth-loading" hidden class="space-y-5" aria-live="polite">
                  <div class="flex items-center gap-4">
                    <div class="flex size-11 items-center justify-center rounded-2xl border border-amber-200/15 bg-amber-200/5">
                      <.icon
                        name="hero-arrow-path"
                        class="size-5 animate-spin text-amber-300 motion-reduce:animate-none"
                      />
                    </div>
                    <div>
                      <p class="font-[family-name:var(--font-serif)] text-lg font-bold text-stone-100">
                        Проверяем вход
                      </p>
                      <p class="mt-1 font-[family-name:var(--font-sans)] text-sm text-stone-400">
                        Это займёт несколько секунд.
                      </p>
                    </div>
                  </div>
                  <div class="h-1.5 overflow-hidden rounded-full bg-white/5">
                    <div class="h-full w-2/3 animate-pulse rounded-full bg-gradient-to-r from-amber-600 via-amber-300 to-amber-600">
                    </div>
                  </div>
                </div>

                <div id="telegram-auth-normal-browser" class="space-y-5" aria-live="polite">
                  <p class="font-[family-name:var(--font-sans)] text-sm leading-6 text-stone-300">
                    Откройте Mini App из @mmgo_bot. Telegram подтвердит аккаунт без отдельного пароля.
                  </p>
                  <a
                    id="telegram-auth-open-bot"
                    href="https://t.me/mmgo_bot?start=play"
                    target="_blank"
                    rel="noreferrer"
                    class="group flex min-h-13 w-full items-center justify-center gap-3 rounded-2xl bg-amber-200 px-5 font-[family-name:var(--font-sans)] text-sm font-bold text-stone-950 shadow-[0_1rem_3rem_rgba(217,169,54,0.14)] transition duration-300 hover:-translate-y-0.5 hover:bg-amber-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-200"
                  >
                    <.icon
                      name="hero-paper-airplane"
                      class="size-5 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
                    /> Открыть @mmgo_bot
                  </a>
                  <div class="flex items-start gap-3 border-t border-white/8 pt-5">
                    <.icon
                      name="hero-shield-check"
                      class="mt-0.5 size-4 shrink-0 text-emerald-300/70"
                    />
                    <p class="font-[family-name:var(--font-sans)] text-xs leading-5 text-stone-500">
                      На сервер отправляется только подписанный Telegram initData.
                    </p>
                  </div>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
