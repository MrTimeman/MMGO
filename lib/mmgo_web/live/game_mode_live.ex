defmodule MMGOWeb.GameModeLive do
  use MMGOWeb, :live_view

  alias MMGO.{Accounts, Arena}
  alias MMGO.Accounts.CharacterProfiles

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_scope.account
    world_characters = Accounts.list_characters_for_account(account.id)
    default_world_character = Accounts.get_default_world_character_for_account(account.id)
    arena_profile = Arena.get_profile_for_account(account.id) |> maybe_preload_profile()

    {:ok,
     socket
     |> assign(:page_title, "Выберите путь")
     |> assign(
       :world_character,
       default_world_character || preferred_world_character(world_characters)
     )
     |> assign(:arena_profile, arena_profile)
     |> assign(:world_form, to_form(%{}, as: :game_mode))
     |> assign(:arena_form, to_form(%{}, as: :game_mode))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} public={true}>
      <main id="game-mode-screen" class="mode-gate">
        <header class="mode-gate__mast">
          <p>Два пути · один аккаунт</p>
          <h1>Куда вы войдёте сегодня?</h1>
          <span>
            Между режимами можно свободно переключаться. Их персонажи и прогресс не смешиваются.
          </span>
        </header>

        <section id="game-mode-options" class="mode-gate__options" aria-label="Режимы игры">
          <article id="game-mode-world-card" class="mode-card mode-card--world">
            <div class="mode-card__sigil" aria-hidden="true">
              <.icon name="hero-globe-europe-africa" />
            </div>
            <p class="mode-card__eyebrow">Общий мир</p>
            <h2>MMGO</h2>
            <p class="mode-card__lead">
              Живой магический мир: путешествия, академия, организации и экономика.
            </p>
            <ul>
              <li><.icon name="hero-map" /> Исследуйте карту и её тайны</li>
              <li><.icon name="hero-academic-cap" /> Учитесь и развивайте персонажа</li>
              <li><.icon name="hero-user-group" /> Влияйте на общий мир</li>
            </ul>

            <div :if={@world_character} class="mode-card__profile">
              <span>Продолжить за</span>
              <strong>{@world_character.name}</strong>
            </div>

            <.form
              for={@world_form}
              id="select-world-mode-form"
              action={~p"/mode/world"}
              method="post"
            >
              <button id="select-world-mode" type="submit" class="mode-card__action">
                Войти в общий мир <.icon name="hero-arrow-right" />
              </button>
            </.form>
          </article>

          <article id="game-mode-arena-card" class="mode-card mode-card--arena">
            <div class="mode-card__flare">быстрый старт</div>
            <div class="mode-card__sigil" aria-hidden="true"><.icon name="hero-bolt" /></div>
            <p class="mode-card__eyebrow">Бой и создание заклинаний</p>
            <h2>Арена</h2>
            <p class="mode-card__lead">
              Сразу в поединок — с рейтингом, дружескими командами и событиями среды.
            </p>
            <ul>
              <li><.icon name="hero-book-open" /> Лучшие гримуары без долгого гринда</li>
              <li><.icon name="hero-sparkles" /> Три школы и полная свобода эксперимента</li>
              <li><.icon name="hero-fire" /> Случайные события меняют поле боя</li>
            </ul>

            <div :if={@arena_profile} class="mode-card__profile">
              <span>Рейтинг {arena_rating(@arena_profile)}</span>
              <strong>{@arena_profile.character.name}</strong>
            </div>

            <.form
              :if={@arena_profile}
              for={@arena_form}
              id="select-arena-mode-form"
              action={~p"/mode/arena"}
              method="post"
            >
              <button id="select-arena-mode" type="submit" class="mode-card__action">
                Войти на Арену <.icon name="hero-arrow-right" />
              </button>
            </.form>

            <.link
              :if={is_nil(@arena_profile)}
              id="create-arena-profile"
              navigate={~p"/arena/new"}
              class="mode-card__action"
            >
              Создать бойца <.icon name="hero-arrow-right" />
            </.link>
          </article>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp preferred_world_character(characters) do
    ordinary_characters =
      Enum.reject(characters, &CharacterProfiles.sealed_spirit?/1)

    Enum.find(ordinary_characters, &(&1.status == :active)) || List.first(ordinary_characters)
  end

  defp maybe_preload_profile(nil), do: nil

  defp maybe_preload_profile(profile) do
    if Ecto.assoc_loaded?(profile.character) do
      profile
    else
      MMGO.Repo.preload(profile, :character)
    end
  end

  defp arena_rating(%{rating: rating}) when is_integer(rating), do: rating
  defp arena_rating(_profile), do: 1_000
end
