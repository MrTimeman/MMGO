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
      <section id="game-entry-screen" class="entry-scene">
        <div class="entry-table">
          <header class="entry-plaque">
            <span class="entry-plaque__chain entry-plaque__chain--left" aria-hidden="true"></span>
            <span class="entry-plaque__chain entry-plaque__chain--right" aria-hidden="true"></span>
            <div class="entry-plaque__seal" aria-hidden="true">MM</div>
            <p class="entry-plaque__alpha">
              <span></span> закрытая альфа · допуск по приглашению
            </p>
            <h1>
              Министерство <span>Магии Онлайн</span>
            </h1>
            <p class="entry-plaque__copy">
              Один персонаж, общий живой мир и правила, которые исполняет сам мир.
            </p>
            <div class="entry-plaque__marks" aria-label="Особенности игры">
              <span><.icon name="hero-sparkles" /> заклинания</span>
              <span><.icon name="hero-globe-europe-africa" /> общий мир</span>
              <span><.icon name="hero-scale" /> Бои с миром и игроками</span>
            </div>
          </header>

          <div id="telegram-auth-root" class="entry-letter">
            <span class="entry-letter__fold" aria-hidden="true"></span>
            <span class="entry-letter__wax" aria-hidden="true">
              <.icon name="hero-key" />
            </span>
            <p class="entry-letter__registry">пропуск Министерства · Telegram</p>
            <h2>Предъявить приглашение</h2>
            <p class="entry-letter__salutation">Уважаемый маг,</p>
            <p class="entry-letter__copy">
              откройте игру через @mmgo_bot. Telegram заверит ваш пропуск — отдельный пароль не требуется.
            </p>

            <.form
              for={@form}
              id="telegram-auth-form"
              action={~p"/auth/telegram"}
              method="post"
              phx-hook="TelegramAuth"
              phx-update="ignore"
              class="entry-auth-form"
            >
              <.input field={@form[:init_data]} type="hidden" id="telegram-auth-init-data" />

              <div id="telegram-auth-loading" hidden class="entry-auth-loading" aria-live="polite">
                <span class="entry-auth-loading__sigil" aria-hidden="true">
                  <.icon name="hero-arrow-path" />
                </span>
                <div>
                  <strong>Проверяем печать</strong>
                  <p>Писарю потребуется несколько секунд.</p>
                </div>
                <span class="entry-auth-loading__line" aria-hidden="true"></span>
              </div>

              <div id="telegram-auth-normal-browser" class="entry-auth-normal" aria-live="polite">
                <a
                  id="telegram-auth-open-bot"
                  href="https://t.me/mmgo_bot?start=play"
                  target="_blank"
                  rel="noreferrer"
                  class="entry-telegram-button"
                >
                  <.icon name="hero-paper-airplane" /> Открыть @mmgo_bot
                </a>
                <div class="entry-letter__fineprint">
                  <.icon name="hero-shield-check" />
                  <p>На сервер передаются только подписанные данные авторизации Telegram.</p>
                </div>
              </div>
            </.form>
            <p class="entry-letter__signature">Канцелярия MMGO</p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
