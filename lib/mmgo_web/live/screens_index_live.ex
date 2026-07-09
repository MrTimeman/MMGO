defmodule MMGOWeb.ScreensIndexLive do
  @moduledoc """
  Dev-only index of every screen in the design pass — a quick launchpad
  for visual review. Not part of the game (players navigate via the map).
  """
  use MMGOWeb, :live_view

  @groups [
    {"Мир",
     [
       {"/screens", "Этот индекс демо-экранов"},
       {"/map", "Карта мира"},
       {"/event", "Событие / хаб локации — город / башня / тракт"},
       {"/travel", "Путешествие"},
       {"/party", "Отряд"}
     ]},
    {"Бой",
     [
       {"/combat", "Бой"},
       {"/defeat", "Поражение — Жертва Роглайка"},
       {"/pvp", "Вызов на дуэль"}
     ]},
    {"База и магия",
     [
       {"/base", "База (интерьер)"},
       {"/spellbook", "Круг заклинаний + гримуары — все школы"},
       {"/alchemy", "Алхимия"},
       {"/craft", "Мастерская"}
     ]},
    {"Экономика",
     [
       {"/trade", "Торговля"},
       {"/inventory", "Инвентарь"},
       {"/finance", "Финансы"}
     ]},
    {"Подземелье",
     [
       {"/dungeon", "Карта глубин"},
       {"/dungeon/level/1", "Уровень 1 — граф комнат"},
       {"/dungeon/level/2", "Уровень 2 — глубокий вариант"},
       {"/dungeon/level/3", "Уровень 3 — глубокий вариант"}
     ]},
    {"Организации",
     [
       {"/orgs", "Организации"},
       {"/orgs/new", "Основание организации"},
       {"/orgs/demo", "Организация — обзор"},
       {"/orgs/demo/people", "Организация — люди"},
       {"/orgs/demo/roles", "Организация — роли"},
       {"/orgs/demo/treasury", "Организация — казна"},
       {"/orgs/demo/charter", "Организация — устав"},
       {"/orgs/demo/appearance", "Организация — внешний вид"},
       {"/orgs/sever", "Организация — торговый вариант"}
     ]},
    {"Академия",
     [
       {"/academy", "Обзор"},
       {"/academy/timetable", "Расписание"},
       {"/academy/grades", "Оценки"},
       {"/academy/library", "Библиотека"},
       {"/academy/courses", "Курсы и запись"},
       {"/academy/progress", "Путь обучения"},
       {"/academy/clubs", "Клубы"},
       {"/academy/clubs/duelists", "Клуб — дуэльный"},
       {"/academy/clubs/lore", "Клуб — общий"},
       {"/academy/clubs/research", "Клуб — исследовательский"},
       {"/academy/clubs/expedition", "Клуб — экспедиционный"},
       {"/academy/clubs/duelists/manage", "Клуб — управление"},
       {"/academy/thesis/demo", "Защита диссертации"},
       {"/academy/bulletin-board", "Доска объявлений"},
       {"/academy/study-desk", "Учебный стол"}
     ]},
    {"Системные демо",
     [
       {"/dev/hooks", "LiveView hooks demo (dev)"},
       {"/dev/screens", "Dev-версия индекса"},
       {"/editor", "Редактор карты (dev)"}
     ]}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, groups: @groups, page_title: "Экраны (dev)")}
  end

  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-[var(--color-bg)] text-[var(--color-text)] px-4 py-6"
      style="font-family: var(--font-serif);"
    >
      <h1 class="text-xl font-bold text-[var(--color-accent)] mb-1">Экраны MMGO</h1>
      <p class="text-sm text-[var(--color-text-muted)] mb-5">
        Дизайн-обзор · демо-данные · все доступные экраны и основные варианты
      </p>
      <div :for={{group, links} <- @groups} class="mb-5">
        <h2
          class="text-xs uppercase tracking-widest text-[var(--color-text-muted)] mb-2"
          style="font-family: var(--font-sans);"
        >
          {group}
        </h2>
        <div class="flex flex-col gap-1.5">
          <a
            :for={{path, label} <- links}
            href={path}
            class="flex items-baseline justify-between rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 hover:border-[var(--color-accent)]"
          >
            <span>{label}</span>
            <span
              class="text-xs text-[var(--color-text-muted)]"
              style="font-family: var(--font-mono);"
            >
              {path}
            </span>
          </a>
        </div>
      </div>
    </div>
    """
  end
end
