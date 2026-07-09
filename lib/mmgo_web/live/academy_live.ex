defmodule MMGOWeb.AcademyLive do
  @moduledoc """
  Design-pass screen family — the Academy (GDD §9): a magical university
  with real academic life. One LiveView, six diegetic rooms selected by
  `live_action`:

    :overview  /academy            — the facade / main hall (dark shell)
    :timetable /academy/timetable  — the term schedule (agenda)
    :grades    /academy/grades     — the grade book (parchment .book)
    :library   /academy/library    — the reading room (dark shell)
    :courses   /academy/courses    — course catalog & enrollment
    :progress  /academy/progress   — the education ladder (the long view)

  No backend wiring: all data is hardcoded demo data, consistent with the
  other academy screens. Demo student: Альберт Северин, Academy Core
  (Wizardry, Огонь + Хаос), term 2/3, GPA 87, cohort rank 4/31.
  See docs/UI_DESIGN_BRIEF.md and docs/academy-plan.md.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # ---- Shared demo student -------------------------------------------
  @student %{
    name: "Альберт Северин",
    program: "Академия Врат",
    program_kind: "Academy Core",
    track: "Чародейство",
    schools: [%{name: "Огонь", hue: 18}, %{name: "Хаос", hue: 320}],
    term: 2,
    terms_total: 3,
    gpa: 87,
    rank: 4,
    cohort: 31
  }

  # term phases, GDD §9.0 rhythm. We are mid-term-2, in the club window.
  @phases [
    %{key: :enroll, label: "Запись", state: :done},
    %{key: :lectures, label: "Лекции", state: :done},
    %{key: :clubs, label: "Клубы", state: :now},
    %{key: :midterm, label: "Аттестация", state: :future},
    %{key: :final, label: "Экзамен", state: :future},
    %{key: :break, label: "Каникулы", state: :future}
  ]

  # doors from the lobby to every other academy room
  @doors [
    %{
      glyph: "❦",
      title: "Расписание",
      hint: "лекции, экзамены, приёмные часы",
      to: "/academy/timetable"
    },
    %{
      glyph: "✒",
      title: "Ведомость",
      hint: "оценки, средний балл, ранг курса",
      to: "/academy/grades"
    },
    %{glyph: "▰", title: "Библиотека", hint: "чтение и знания школ", to: "/academy/library"},
    %{glyph: "❧", title: "Курсы", hint: "запись и профессора семестра", to: "/academy/courses"},
    %{glyph: "⚑", title: "Клубы", hint: "дуэли, исследования, экспедиции", to: "/academy/clubs"},
    %{
      glyph: "✦",
      title: "Путь",
      hint: "образовательная лестница до профессуры",
      to: "/academy/progress"
    },
    %{
      glyph: "▤",
      title: "Доска объявлений",
      hint: "курсы, защиты, рейтинг курса",
      to: "/academy/bulletin-board"
    }
  ]

  # ---- Timetable (one term's events, §9.0) ---------------------------
  @timetable [
    %{
      when: "Месяц 1 · Запись",
      title: "Открытие семестра",
      kind: "Запись на курсы",
      state: :done,
      note: nil
    },
    %{
      when: "Месяц 3",
      title: "Лекция: Строение огненной печати",
      kind: "Лекция · проф. Веладрис",
      state: :done,
      note: nil
    },
    %{
      when: "Месяц 5",
      title: "Лекция: Хаотические возмущения потока",
      kind: "Лекция · маг. Орн",
      state: :missed,
      note: "Пропуск: −5 к потолку итоговой оценки"
    },
    %{
      when: "Месяц 6",
      title: "Приёмные часы проф. Веладрис",
      kind: "Office hours · §9.9",
      state: :now,
      note: "Посещение: +5 к потолку оценки курса"
    },
    %{
      when: "Месяц 7 · Клубы",
      title: "Дуэльный клуб: заря",
      kind: "Клубное событие",
      state: :now,
      note: nil
    },
    %{
      when: "Месяц 9",
      title: "Промежуточная аттестация",
      kind: "Midterm · необязательно",
      state: :future,
      note: "Поднимает потолок итоговой оценки"
    },
    %{
      when: "Месяц 12",
      title: "Итоговый экзамен, семестр 2",
      kind: "Final · обязательно",
      state: :future,
      note: "Через 6 дней"
    }
  ]

  # ---- Grade book: per-term exam scores ------------------------------
  @grade_terms [
    %{term: 1, title: "Год 1 — Основы", score: 84, midterm: 78, status: :pass},
    %{term: 2, title: "Год 2 — Практика", score: 90, midterm: 85, status: :active},
    %{term: 3, title: "Год 3 — Дипломный проект", score: nil, midterm: nil, status: :future}
  ]

  # ---- Library shelves -----------------------------------------------
  @shelves [
    %{
      label: "Школа Огня",
      hue: 18,
      books: [
        %{title: "Пламя как форма мысли", author: "проф. Веладрис", xp: 40, read: true},
        %{title: "Огненные печати: канон", author: "маг. Т. Орн", xp: 60, read: true},
        %{title: "Управление жаром в бою", author: "NPC · архив Академии", xp: 35, read: false}
      ]
    },
    %{
      label: "Школа Хаоса",
      hue: 320,
      books: [
        %{title: "Возмущения дикого потока", author: "проф. Ил-Сарра", xp: 55, read: false},
        %{title: "Хаос без имени", author: "игрок-проф. Каэль Вейн", xp: 70, read: false}
      ]
    },
    %{
      label: "Общий курс",
      hue: 45,
      books: [
        %{title: "История княжества Эленвир", author: "NPC · архив Академии", xp: 25, read: true},
        %{title: "Латынь для заклинателей", author: "проф. Мовен", xp: 30, read: false}
      ]
    }
  ]

  # ---- Course catalog (§9.4) -----------------------------------------
  @courses [
    %{
      id: "fire2",
      title: "Огненная печать II",
      track: "Чародейство · Огонь",
      professor: "проф. Веладрис",
      player?: false,
      replaced?: false,
      seats_taken: 22,
      seats: 24,
      enrolled?: true,
      syllabus:
        "Компиляция трёх стартовых заклинаний огня под ограничением утомления. Два практикума, приёмные часы, финал с прикладной задачей на компиляторе."
    },
    %{
      id: "chaos2",
      title: "Хаотическая динамика",
      track: "Чародейство · Хаос",
      professor: "игрок-проф. Каэль Вейн",
      player?: true,
      replaced?: true,
      seats_taken: 18,
      seats: 20,
      enrolled?: true,
      syllabus:
        "Авторский курс, заменивший стандартную секцию Академии. Каэль Вейн — валедикторианец 844 года. Репутация профессора привлекает сильных студентов (§9.4 престиж-петля)."
    },
    %{
      id: "latin",
      title: "Латынь заклинаний",
      track: "Общий",
      professor: "проф. Мовен",
      player?: false,
      replaced?: false,
      seats_taken: 24,
      seats: 30,
      enrolled?: false,
      syllabus:
        "Практическая латынь для написания инкантаций: Actio, Forma, Vis. Полезно перед дипломным проектом."
    },
    %{
      id: "duel",
      title: "Прикладная дуэлистика",
      track: "Чародейство",
      professor: "игрок-проф. Мира Дол",
      player?: true,
      replaced?: false,
      seats_taken: 20,
      seats: 20,
      enrolled?: false,
      syllabus:
        "Мест нет. Ведёт президент дуэльного клуба. Практика на боевом движке, дружеские поединки без ставок."
    }
  ]

  # ---- Education ladder (§9.0-9.11) ----------------------------------
  @ladder [
    %{
      title: "Базовое образование",
      span: "10 терминов",
      state: :done,
      glyph: "✓",
      desc: "Всеобщее и бесплатное: история, стихийная грамота, латынь. Завершено с отличием.",
      badges: [%{text: "Distinction", kind: "distinction"}, %{text: "GPA 88", kind: "pass"}]
    },
    %{
      title: "Академия · специализация",
      span: "3 термина",
      state: :now,
      glyph: "★",
      desc:
        "Чародейство, школы Огонь + Хаос. Год 1 — основы, год 2 — практика (сейчас), год 3 — дипломный проект.",
      badges: [%{text: "Термин 2 / 3", kind: "pass"}, %{text: "Ранг 4 / 31", kind: "distinction"}],
      here: true
    },
    %{
      title: "Расширенный курс",
      span: "2 термина · опция",
      state: :branch,
      glyph: "◇",
      desc:
        "Необязательная ветка углубления перед научным путём. Больше стартовых заклинаний, выше их качество.",
      badges: [%{text: "Ответвление", kind: "npc"}]
    },
    %{
      title: "Академия наук · курсы",
      span: "4 термина",
      state: :future,
      glyph: "✎",
      desc:
        "Выбор научного руководителя (§9.8). +20% к скорости исследований, доступ к публикациям наставника.",
      badges: [%{text: "Нужен наставник", kind: "npc"}]
    },
    %{
      title: "Тезис и защита",
      span: "переменно",
      state: :future,
      glyph: "⚖",
      desc:
        "Дипломная работа выносится на открытую защиту перед тремя профессорами. Принято / с правками / Отклонено (§9.10).",
      badges: [%{text: "Публичная церемония", kind: "distinction"}]
    },
    %{
      title: "Профессор",
      span: "карьера",
      state: :future,
      glyph: "❦",
      desc: "Право публиковать курсы, брать учеников, стипендия с каждого семестра преподавания.",
      badges: [%{text: "Стипендия", kind: "pass"}, %{text: "Право наставника", kind: "player"}]
    },
    %{
      title: "Глава Академии / Эмерит",
      span: "вершина",
      state: :branch,
      glyph: "♛",
      desc:
        "Глава Академии избирается профессорами раз в ~10 дней; управляет учебным планом и фондом стипендий. Эмерит — почётная отставка с правом рекомендаций.",
      badges: [%{text: "Политика (§9.10)", kind: "rival"}]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — resolve enrollment/terms/grades for the session character.
    {:ok,
     socket
     |> assign(:student, @student)
     |> assign(:phases, @phases)
     |> assign(:doors, @doors)
     |> assign(:timetable, @timetable)
     |> assign(:grade_terms, @grade_terms)
     |> assign(:shelves, @shelves)
     |> assign(:courses, @courses)
     |> assign(:ladder, @ladder)
     |> assign(:read_this_term, 3)
     |> assign(:read_goal, 8)
     |> assign(:open_syllabus, nil)
     |> assign(:flash_note, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    action = socket.assigns.live_action || :overview
    {:noreply, assign(socket, :page_title, "Академия · #{title_for(action)}")}
  end

  @impl true
  def handle_event("toggle_syllabus", %{"id" => id}, socket) do
    open = if socket.assigns.open_syllabus == id, do: nil, else: id
    {:noreply, assign(socket, :open_syllabus, open)}
  end

  @impl true
  def handle_event("enroll", %{"id" => id}, socket) do
    # demo: flip enrolled? and nudge the seat counter
    courses =
      Enum.map(socket.assigns.courses, fn c ->
        if c.id == id and not c.enrolled? and c.seats_taken < c.seats do
          %{c | enrolled?: true, seats_taken: c.seats_taken + 1}
        else
          c
        end
      end)

    {:noreply,
     socket |> assign(:courses, courses) |> assign(:flash_note, "Запись на курс подтверждена.")}
  end

  @impl true
  def handle_event("drop", %{"id" => id}, socket) do
    courses =
      Enum.map(socket.assigns.courses, fn c ->
        if c.id == id and c.enrolled? do
          %{c | enrolled?: false, seats_taken: max(c.seats_taken - 1, 0)}
        else
          c
        end
      end)

    {:noreply,
     socket |> assign(:courses, courses) |> assign(:flash_note, "Вы отписались от курса.")}
  end

  # ==================================================================
  #  Render dispatch
  # ==================================================================
  @impl true
  def render(%{live_action: :grades} = assigns), do: grades(assigns)
  def render(%{live_action: :timetable} = assigns), do: timetable(assigns)
  def render(%{live_action: :library} = assigns), do: library(assigns)
  def render(%{live_action: :courses} = assigns), do: courses(assigns)
  def render(%{live_action: :progress} = assigns), do: progress(assigns)
  def render(assigns), do: overview(assigns)

  # ------------------------------------------------------------------
  #  :overview — the facade / main hall
  # ------------------------------------------------------------------
  defp overview(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/map"} class="acd-exit">← Выйти на площадь</a>

        <div class="acd-hero">
          <.art_slot
            kind="hero"
            label="Академия Врат Зари — главный холл"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Академия · Врата Зари</p>
            <h1 class="acd-hero__title">Главный холл</h1>
            <p class="acd-hero__sub">Княжество Эленвир · семестр в разгаре</p>
          </div>
        </div>

        <div class="acd-body">
          <.enroll_card student={@student} phases={@phases} />

          <section class="acd-section">
            <div class="acd-section__head">
              <h2 class="acd-section__title">Ближайшие обязательства</h2>
              <span class="acd-section__aside">не пропусти</span>
            </div>
            <ul class="acd-oblig">
              <li class="acd-oblig__item">
                <span class="acd-oblig__glyph">❦</span>
                <span class="acd-oblig__txt">
                  <span class="acd-oblig__t">Приёмные часы проф. Веладрис</span>
                  <span class="acd-oblig__d">+5 к потолку оценки курса «Огненная печать II»</span>
                </span>
                <span class="acd-oblig__when">сегодня</span>
              </li>
              <li class="acd-oblig__item">
                <span class="acd-oblig__glyph">✒</span>
                <span class="acd-oblig__txt">
                  <span class="acd-oblig__t">Итоговый экзамен, семестр 2</span>
                  <span class="acd-oblig__d">обязательный · тема: практика огня и хаоса</span>
                </span>
                <span class="acd-oblig__when">через 6 дней</span>
              </li>
            </ul>
          </section>

          <section class="acd-section">
            <div class="acd-section__head">
              <h2 class="acd-section__title">Куда пойти</h2>
              <span class="acd-section__label">залы Академии</span>
            </div>
            <div class="acd-doors">
              <.link :for={d <- @doors} navigate={d.to} class="acd-door">
                <span class="acd-door__glyph">{d.glyph}</span>
                <span class="acd-door__txt">
                  <span class="acd-door__t">{d.title}</span>
                  <span class="acd-door__h">{d.hint}</span>
                </span>
                <span class="acd-door__chev">›</span>
              </.link>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  # shared enrollment card with the term-phase rhythm indicator
  attr :student, :map, required: true
  attr :phases, :list, required: true

  defp enroll_card(assigns) do
    ~H"""
    <section class="acd-card">
      <div class="acd-enroll__crest">
        <span class="acd-enroll__sigil">✦</span>
        <div class="acd-enroll__who">
          <p class="acd-enroll__name">{@student.name}</p>
          <p class="acd-enroll__prog">{@student.program} · {@student.track}</p>
          <div class="acd-schools">
            <span
              :for={s <- @student.schools}
              class="acd-school"
              style={"color: hsl(#{s.hue},70%,68%); border-color: hsl(#{s.hue},55%,40%);"}
            >
              {s.name}
            </span>
          </div>
        </div>
      </div>

      <div class="acd-section__head" style="margin-bottom:0.4rem;">
        <span class="acd-section__label">Термин {@student.term} из {@student.terms_total}</span>
        <span class="acd-section__label">
          GPA {@student.gpa} · ранг {@student.rank}/{@student.cohort}
        </span>
      </div>
      <div class="acd-bar">
        <div
          class="acd-bar__fill"
          style={"width: #{round(@student.term / @student.terms_total * 100)}%;"}
        >
        </div>
      </div>

      <div class="acd-phase">
        <div class="acd-phase__track">
          <div :for={p <- @phases} class={"acd-phase__step acd-phase__step--#{p.state}"}>
            <span class="acd-phase__dot"></span>
            <span class="acd-phase__label">{p.label}</span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ------------------------------------------------------------------
  #  :timetable — the term schedule
  # ------------------------------------------------------------------
  defp timetable(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В холл</a>
        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Академия — доска расписания в холле"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Семестр 2 · Год практики</p>
            <h1 class="acd-hero__title">Расписание</h1>
          </div>
        </div>

        <div class="acd-body">
          <div class="acd-section__head">
            <span class="acd-section__label">Ритм термина · §9.0</span>
            <span class="acd-section__aside">посещения важны</span>
          </div>

          <div class="acd-agenda">
            <div :for={e <- @timetable} class={"acd-agenda__item acd-agenda__item--#{e.state}"}>
              <div class="acd-agenda__rail">
                <span class="acd-agenda__node"></span>
                <span class="acd-agenda__line"></span>
              </div>
              <div class="acd-agenda__body">
                <span class="acd-agenda__when">{e.when} · {attendance_label(e.state)}</span>
                <p class="acd-agenda__t">{e.title}</p>
                <p class="acd-agenda__d">{e.kind}</p>
                <p :if={e.note} class="acd-note">{e.note}</p>
              </div>
            </div>
          </div>

          <section class="acd-card" style="margin-top:1.4rem;">
            <p class="acd-card__title">Приёмные часы · §9.9</p>
            <p class="acd-card__meta">
              Каждый профессор проводит один приём в семестр. Посещение поднимает потолок оценки
              курса на 5 баллов и укрепляет связь с наставником — путь к рекомендательному письму.
            </p>
          </section>
        </div>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  #  :grades — the grade book (parchment .book chrome)
  # ------------------------------------------------------------------
  defp grades(assigns) do
    assigns = assign(assigns, :spark, sparkline_points([84, 90]))

    ~H"""
    <div class="scene-desk">
      <div class="book">
        <div class="book__spine"></div>
        <div class="book__page">
          <a href={~p"/academy"} class="book__back">&larr; в холл Академии</a>
          <div class="book__leaf">
            <h1 class="book__title">Ведомость успеваемости</h1>
            <p class="book__subtitle">{@student.name} · {@student.program}</p>

            <div style="display:flex; gap:0.5rem; margin:0.8rem 0 1rem;">
              <div class="acd-metric" style="flex:1;">
                <div class="acd-metric__num">{@student.gpa}</div>
                <div class="acd-metric__lab">Средний балл</div>
              </div>
              <div class="acd-metric" style="flex:1;">
                <div class="acd-metric__num">
                  {@student.rank}<span style="font-size:0.9rem;">/{@student.cohort}</span>
                </div>
                <div class="acd-metric__lab">Ранг курса</div>
              </div>
              <div class="acd-metric" style="flex:1;">
                <div class="acd-metric__num" style="color:var(--parch-red);">85+</div>
                <div class="acd-metric__lab">Порог отличия</div>
              </div>
            </div>

            <div class="acdg-projection">
              <span class="acdg-projection__seal">✦</span>
              <div>
                <p class="acdg-projection__t">Идёте на отличие</p>
                <p class="acdg-projection__d">
                  GPA 87 ≥ 85 при ≤ 1 проваленном термине — Distinction, стипендия и почётное звание.
                </p>
              </div>
            </div>

            <p class="acdg-runline">Кривая среднего балла</p>
            <svg class="acdg-spark" viewBox="0 0 100 34" preserveAspectRatio="none" aria-hidden="true">
              <polyline
                points={@spark}
                fill="none"
                stroke="var(--parch-red)"
                stroke-width="1.6"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <line
                x1="0"
                y1="17"
                x2="100"
                y2="17"
                stroke="var(--parch-ink-faint)"
                stroke-width="0.4"
                stroke-dasharray="2 2"
                opacity="0.5"
              />
            </svg>

            <table class="acdg-book">
              <thead>
                <tr>
                  <th>Термин</th>
                  <th>Аттестация</th>
                  <th>Экзамен</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @grade_terms}>
                  <td>
                    <strong>Год {t.term}</strong>
                    <span class="acdg-book__sub">{t.title}</span>
                  </td>
                  <td class="acdg-num">{t.midterm || "—"}</td>
                  <td class="acdg-num acdg-score">{t.score || "—"}</td>
                  <td>{term_tag(t.status)}</td>
                </tr>
              </tbody>
            </table>

            <p class="acdg-boost">
              Промежуточная аттестация поднимает потолок итоговой оценки — год 2 закрыт на 90 благодаря
              аттестации на 85.
            </p>

            <div class="acdg-legend">
              <p class="acdg-legend__t">Последствия провала (§9.1)</p>
              <ul>
                <li><span class="acd-badge acd-badge--pass">≤ 3</span> провала — выпуск как Pass</li>
                <li><span class="acd-badge">4–6</span> провалов — выпуск с испытательным сроком</li>
                <li>
                  <span class="acd-badge acd-badge--fail">≥ 7</span>
                  провалов — отчисление, год ожидания
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  #  :library — the reading room
  # ------------------------------------------------------------------
  defp library(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В холл</a>
        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Академия — читальный зал библиотеки"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Тишина и свет ламп</p>
            <h1 class="acd-hero__title">Библиотека</h1>
          </div>
        </div>

        <div class="acd-body">
          <section class="acd-card">
            <div class="acd-section__head" style="margin-bottom:0.5rem;">
              <p class="acd-card__title" style="margin:0;">Прочитано в этом семестре</p>
              <span class="acd-section__aside">{@read_this_term} / {@read_goal}</span>
            </div>
            <div class="acd-bar">
              <div
                class="acd-bar__fill"
                style={"width: #{round(@read_this_term / @read_goal * 100)}%;"}
              >
              </div>
            </div>
            <p class="acd-card__meta" style="margin-top:0.5rem;">
              Чтение приносит очки знаний и поднимает потолок экзамена по школе.
            </p>
          </section>

          <div :for={shelf <- @shelves} class="acd-shelf">
            <p class="acd-shelf__label">{shelf.label}</p>
            <div
              :for={b <- shelf.books}
              class={"acd-book#{if b.read, do: " acd-book--read"}"}
            >
              <span class="acd-book__spine" style={"background: hsl(#{shelf.hue},55%,42%);"}></span>
              <div class="acd-book__txt">
                <div class="acd-book__t">{b.title}</div>
                <div class="acd-book__a">{b.author}</div>
              </div>
              <span class="acd-book__xp">
                {if b.read, do: "прочитано", else: "+#{b.xp} знаний"}
              </span>
            </div>
          </div>

          <div class="acd-forbidden">
            <p class="acd-forbidden__t">⚿ Запретная секция</p>
            <p class="acd-forbidden__d">
              Доступ только по рекомендации профессора (§9.9). Рукописи хаоса и утраченные каноны
              ждут за кованой решёткой — принесите письмо наставника.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  #  :courses — catalog & enrollment
  # ------------------------------------------------------------------
  defp courses(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В холл</a>
        <div class="acd-hero">
          <.art_slot kind="banner" label="Академия — стол записи на курсы" />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Окно записи · семестр 2</p>
            <h1 class="acd-hero__title">Курсы</h1>
          </div>
        </div>

        <div class="acd-body">
          <p
            :if={@flash_note}
            class="acd-note"
            style="color:var(--acd-pass); text-align:center; margin-bottom:0.8rem;"
          >
            {@flash_note}
          </p>

          <section :for={c <- @courses} class="acd-card">
            <div class="acd-course__head">
              <div style="min-width:0;">
                <p class="acd-card__title">{c.title}</p>
                <p class="acd-card__meta">{c.track}</p>
              </div>
              <span :if={c.enrolled?} class="acd-badge acd-badge--pass">записан</span>
            </div>

            <div class="acd-course__prof">
              <span>{professor_glyph(c.player?)}</span>
              <span>{c.professor}</span>
              <span :if={c.player?} class="acd-badge acd-badge--player">игрок-профессор</span>
              <span :if={not c.player?} class="acd-badge acd-badge--seeded">курс Академии</span>
              <span :if={c.replaced?} class="acd-badge acd-badge--rival">заменяет базовый</span>
            </div>

            <div class="acd-course__seats">
              <div class="acd-bar acd-course__seatbar">
                <div class="acd-bar__fill" style={"width: #{round(c.seats_taken / c.seats * 100)}%;"}>
                </div>
              </div>
              <span class="acd-course__seatnum">{c.seats_taken}/{c.seats} мест</span>
            </div>

            <details class="acd-syllabus" open={@open_syllabus == c.id}>
              <summary phx-click="toggle_syllabus" phx-value-id={c.id}>Программа курса</summary>
              {c.syllabus}
            </details>

            <div style="margin-top:0.7rem;">
              <button
                :if={not c.enrolled? and c.seats_taken < c.seats}
                type="button"
                class="acd-btn acd-btn--primary acd-btn--block"
                phx-click="enroll"
                phx-value-id={c.id}
              >
                Записаться
              </button>
              <button
                :if={not c.enrolled? and c.seats_taken >= c.seats}
                type="button"
                class="acd-btn acd-btn--block"
                disabled
              >
                Мест нет
              </button>
              <button
                :if={c.enrolled?}
                type="button"
                class="acd-btn acd-btn--danger acd-btn--block"
                phx-click="drop"
                phx-value-id={c.id}
              >
                Отписаться
              </button>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  #  :progress — the education ladder, the long view
  # ------------------------------------------------------------------
  defp progress(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В холл</a>
        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Академия — лестница мастерства, витраж"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Путь длиною в жизнь</p>
            <h1 class="acd-hero__title">Образовательный путь</h1>
            <p class="acd-hero__sub">от первого термина до главы Академии</p>
          </div>
        </div>

        <div class="acd-body">
          <div class="acd-ladder">
            <div :for={s <- @ladder} class={"acd-stage acd-stage--#{s.state}"}>
              <span class="acd-stage__node">{s.glyph}</span>
              <div class="acd-stage__card">
                <div class="acd-stage__head">
                  <span class="acd-stage__t">{s.title}</span>
                  <span class="acd-stage__span">{s.span}</span>
                </div>
                <span :if={Map.get(s, :here)} class="acd-here">✦ вы здесь</span>
                <p class="acd-stage__d">{s.desc}</p>
                <div class="acd-stage__meta">
                  <span :for={b <- s.badges} class={"acd-badge acd-badge--#{b.kind}"}>{b.text}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---- helpers -------------------------------------------------------
  defp title_for(:overview), do: "Холл"
  defp title_for(:timetable), do: "Расписание"
  defp title_for(:grades), do: "Ведомость"
  defp title_for(:library), do: "Библиотека"
  defp title_for(:courses), do: "Курсы"
  defp title_for(:progress), do: "Путь"
  defp title_for(_), do: "Холл"

  defp attendance_label(:done), do: "посещено"
  defp attendance_label(:now), do: "предстоит"
  defp attendance_label(:missed), do: "пропущено"
  defp attendance_label(:future), do: "впереди"

  defp professor_glyph(true), do: "❈"
  defp professor_glyph(false), do: "❦"

  defp term_tag(:pass),
    do: Phoenix.HTML.raw(~s(<span class="acd-badge acd-badge--pass">зачёт</span>))

  defp term_tag(:active),
    do: Phoenix.HTML.raw(~s(<span class="acd-badge acd-badge--distinction">текущий</span>))

  defp term_tag(:future), do: Phoenix.HTML.raw(~s(<span class="acd-badge">впереди</span>))
  defp term_tag(_), do: Phoenix.HTML.raw("")

  # scores 0-100 → polyline points across a 100x34 viewbox (y inverted)
  defp sparkline_points(scores) do
    n = max(length(scores), 1)

    scores
    |> Enum.with_index()
    |> Enum.map(fn {score, i} ->
      x = if n == 1, do: 50, else: i / (n - 1) * 100
      y = 34 - score / 100 * 34
      "#{Float.round(x, 1)},#{Float.round(y * 1.0, 1)}"
    end)
    |> Enum.join(" ")
  end
end
