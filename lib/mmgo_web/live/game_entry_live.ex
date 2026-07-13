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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main
        id="game-entry-screen"
        class="flex min-h-[calc(100vh-11rem)] items-center justify-center bg-[radial-gradient(circle_at_50%_18%,rgba(245,158,11,0.18),transparent_20rem),linear-gradient(160deg,var(--color-bg),var(--color-surface))] px-4 py-12 text-[var(--color-text)]"
      >
        <section class="w-full max-w-sm rounded-2xl border border-[var(--color-border)] bg-[color:var(--color-surface)]/95 p-6 shadow-2xl shadow-black/40 sm:p-8">
          <p class="font-[family-name:var(--font-sans)] text-xs font-bold uppercase tracking-[0.22em] text-[var(--color-accent)]">
            Министерство магии
          </p>
          <h1 class="mt-3 font-[family-name:var(--font-serif)] text-3xl font-bold leading-tight text-[var(--color-text)]">
            Врата в Эленвир
          </h1>

          <div id="telegram-auth-root">
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

              <div id="telegram-auth-loading" hidden class="space-y-3" aria-live="polite">
                <div class="flex items-center gap-3 text-[var(--color-accent)]">
                  <.icon
                    name="hero-arrow-path"
                    class="size-5 animate-spin motion-reduce:animate-none"
                  />
                  <span class="font-[family-name:var(--font-serif)] text-lg">
                    Открываем путь в Эленвир
                  </span>
                </div>
                <p class="text-sm leading-6 text-[var(--color-text-muted)]">
                  Подтверждаем вашу личность у врат Telegram.
                </p>
              </div>

              <div id="telegram-auth-normal-browser" class="space-y-5" aria-live="polite">
                <p class="font-[family-name:var(--font-serif)] text-xl font-bold text-[var(--color-text)]">
                  Откройте игру из Telegram
                </p>
                <p class="text-base leading-7 text-[var(--color-text-muted)]">
                  Мини-приложение передаёт подтверждение входа. Вернитесь в бот и откройте игру оттуда.
                </p>
                <p class="border-l-2 border-[var(--color-accent-dim)] pl-3 text-sm leading-6 text-[var(--color-text-muted)]">
                  Обычный браузер не получает доступ к вашему персонажу и не создаёт учебную учётную запись.
                </p>
              </div>
            </.form>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
