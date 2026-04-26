defmodule MMGOWeb.AcademyLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGOWeb.GameLiveHelpers

  @courses [
    %{
      id: "c1",
      name: "Теория Огня II",
      teacher: "Проф. Мирдор",
      track: "Волшебство",
      progress: 62,
      time_left: "2д 6ч",
      status: :active
    },
    %{
      id: "c2",
      name: "Латынь и Инкантации",
      teacher: "Проф. Велла",
      track: "Общие",
      progress: 40,
      time_left: "4д 0ч",
      status: :active
    },
    %{
      id: "c3",
      name: "Практика Хаоса I",
      teacher: "Проф. Мирдор",
      track: "Волшебство",
      progress: 0,
      time_left: "8д",
      status: :upcoming
    },
    %{
      id: "c4",
      name: "История Принципата",
      teacher: "Проф. Данн",
      track: "Общие",
      progress: 100,
      time_left: "Завершён",
      status: :done
    }
  ]

  @clubs [
    %{
      name: "Клуб Дуэлистов",
      desc: "Практические PvP-тренировки. Низкие ставки.",
      members: 12,
      joined: true,
      icon: "⚔"
    },
    %{
      name: "Экспедиционное общество",
      desc: "Планирование вылазок. Поиск группы.",
      members: 8,
      joined: false,
      icon: "◎"
    },
    %{
      name: "Алхимический кружок",
      desc: "Совместное создание зелий и ингредиентов.",
      members: 6,
      joined: false,
      icon: "⚗"
    },
    %{
      name: "Исследовательская гр. Хаос",
      desc: "Изучение природы и предела школы Хаоса.",
      members: 4,
      joined: true,
      icon: "⊗"
    }
  ]

  @research [
    %{
      title: "Комбинация Огонь + Хаос",
      desc: "Изучить взаимодействие двух ваших школ",
      progress: 30,
      xp: 400,
      difficulty: "Низкая"
    },
    %{
      title: "Новая формула инкантации",
      desc: "Создать оригинальное заклинание для БД",
      progress: 0,
      xp: 800,
      difficulty: "Средняя"
    },
    %{
      title: "Диссертация: Природа Хаоса",
      desc: "Финальная работа. Открывает должность Профессора",
      progress: 0,
      xp: 5000,
      difficulty: "Высокая"
    }
  ]

  @impl true
  def mount(_params, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)
    character = socket.assigns.current_character
    enrollment = Academy.current_enrollment(character.id)
    term = enrollment && Academy.current_term(enrollment.id)

    {:ok,
     assign(socket,
       page_title: "Академия",
       tab: "schedule",
       enrollment: enrollment,
       term: term,
       courses: @courses,
       clubs: @clubs,
       research: @research
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ~w(schedule clubs research) do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="academy-screen" class="zip-screen">
        <.zip_header title="Академия" subtitle={"Трек: Волшебство · #{term_phase(@term)}"} />

        <section class="zip-content">
          <div id="academy-path" class="academy-path">
            <p class="zip-kicker">АКАДЕМИЧЕСКИЙ ПУТЬ</p>
            <div class="academy-stages">
              <div
                :for={
                  {stage, index} <-
                    Enum.with_index(["Базовое", "Бакалавр", "Магистр", "Аспирант", "Доктор"])
                }
                class="academy-stage"
              >
                <span class={[
                  "academy-stage__bar",
                  index <= 1 && "is-filled",
                  index == 1 && "is-current"
                ]}>
                </span>
                <span class={["academy-stage__label", index <= 1 && "is-filled"]}>{stage}</span>
              </div>
            </div>
            <div class="academy-path__meta">
              <span>2-й год обучения</span>
              <span>+240 XP сегодня</span>
            </div>
          </div>

          <nav class="zip-tabs">
            <button
              id="academy-schedule"
              class={["zip-tab", @tab == "schedule" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="schedule"
            >
              Расписание
            </button>
            <button
              id="academy-clubs"
              class={["zip-tab", @tab == "clubs" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="clubs"
            >
              Клубы
            </button>
            <button
              id="academy-research"
              class={["zip-tab", @tab == "research" && "is-active"]}
              phx-click="switch_tab"
              phx-value-tab="research"
            >
              Исследования
            </button>
          </nav>

          <div class="zip-panel-list">
            <%= if @tab == "schedule" do %>
              <article
                :for={course <- @courses}
                id={"academy-course-#{course.id}"}
                class={[
                  "zip-card",
                  course.status == :active && "is-active",
                  course.status == :done && "is-done"
                ]}
              >
                <div class="zip-card__row">
                  <div>
                    <h2>{if course.status == :done, do: "✓ ", else: ""}{course.name}</h2>
                    <p>{course.teacher} · {course.track}</p>
                  </div>
                  <span class="zip-badge">{course.time_left}</span>
                </div>
                <div :if={course.status == :active} class="zip-progress">
                  <span style={"width: #{course.progress}%"}></span>
                </div>
              </article>
              <.link
                id="academy-study-link"
                navigate={~p"/academy/study-desk"}
                class="zip-gold-button"
              >
                Записаться на новый курс
              </.link>
              <.link
                id="academy-bulletin-link"
                navigate={~p"/academy/bulletin-board"}
                class="zip-sub-link"
              >
                Доска объявлений
              </.link>
            <% end %>

            <%= if @tab == "clubs" do %>
              <article :for={club <- @clubs} class={["zip-card", club.joined && "is-active"]}>
                <div class="zip-card__media-row">
                  <div class="zip-card__icon">{club.icon}</div>
                  <div>
                    <h2>{club.name}</h2>
                    <p>{club.desc}</p>
                    <small>{club.members} участников</small>
                  </div>
                </div>
                <button type="button" class={["zip-small-button", club.joined && "is-danger"]}>
                  {if club.joined, do: "Покинуть", else: "Вступить"}
                </button>
              </article>
            <% end %>

            <%= if @tab == "research" do %>
              <div class="zip-note">
                Академический путь открыт после бакалавриата. Исследования создают новые заклинания для публичной базы данных.
              </div>
              <article :for={item <- @research} class="zip-card">
                <div class="zip-card__row">
                  <div>
                    <h2>{item.title}</h2>
                    <p>{item.desc}</p>
                    <small>+{item.xp} XP · {item.difficulty}</small>
                  </div>
                  <button type="button" class="zip-small-button">
                    {if item.progress > 0, do: "Продолжить", else: "Начать"}
                  </button>
                </div>
                <div :if={item.progress > 0} class="zip-progress">
                  <span style={"width: #{item.progress}%"}></span>
                </div>
              </article>
            <% end %>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp zip_header(assigns) do
    ~H"""
    <header class="zip-telegram-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
    </header>
    """
  end

  defp term_phase(nil), do: "Бакалавр II"

  defp term_phase(term),
    do: term |> Academy.term_phase() |> to_string() |> String.replace("_", " ")
end
