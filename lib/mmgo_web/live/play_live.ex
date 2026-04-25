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
              <p class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[#7a6030]">
                14 Мглистый
              </p>
              <p class="text-xs text-[#e8d5b0]">день · VII г.</p>
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
    assigns = assign(assigns, :locations_json, Jason.encode!(map_locations()))

    ~H"""
    <div
      id="map-screen"
      class="relative h-full min-h-[720px] overflow-hidden"
      phx-hook="Map"
      phx-update="ignore"
      data-map-src={~p"/images/mmgo2-map.png"}
      data-locations={@locations_json}
    >
    </div>
    """
  end

  defp map_locations do
    [
      %{
        id: "tower",
        name: "Башня",
        type: "tower",
        icon: "♜",
        x: 44.5,
        y: 21.0,
        desc: "Единственное место, где работает магия. Вход в подземелье.",
        subtitle: "Единственное место, где работает магия",
        hero: "У подножия",
        layout: "tower",
        text: [
          "Воздух здесь звенит, как струна слабо натянутого лука. Камень у входа тёплый — местами теплее ладони.",
          "Внутри слышно, как кто-то сосредоточенно что-то бормочет по-латыни. Голоса сразу трёх."
        ],
        actions: [
          %{key: "party", title: "Собрать / найти отряд", note: "перед входом"},
          %{
            key: "dungeon",
            title: "Войти в подземелье",
            note: "готовьтесь тщательно",
            accent: true
          },
          %{key: "library", title: "Библиотека Башни", note: "старые записи"}
        ]
      },
      %{
        id: "capital",
        name: "Столица",
        type: "city",
        icon: "♛",
        x: 46.0,
        y: 46.5,
        desc: "Столичный город княжества. Академия, рынок, таверны.",
        subtitle: "Главный город княжества",
        hero: "Городские врата",
        layout: "capital",
        text: [
          "Стражники в кольчугах лениво переглядываются. От кузницы тянет углём и потом, с рыночной площади — жареной рыбой и пряной мятой.",
          "К вам подходит мальчишка-посыльный: «Сударь, там на доске объявлений — письмо с вашим именем»."
        ],
        actions: [
          %{key: "academy", title: "В Академию", note: "учебные залы"},
          %{key: "market", title: "На рынок", note: "лавки и торговцы"},
          %{key: "tavern", title: "В таверну «Три пера»", note: "новости и наём"},
          %{key: "letter", title: "Вскрыть письмо", note: "печать красного воска", accent: true}
        ]
      },
      %{
        id: "east-town",
        name: "Верхний Предел",
        type: "city",
        icon: "♛",
        x: 77.0,
        y: 25.5,
        desc: "Северный торговый город на границе.",
        subtitle: "Пограничный торг",
        hero: "Северные ворота",
        layout: "settlement",
        text: ["Каменные склады и узкие улицы пахнут смолой, железом и чужими деньгами."],
        actions: [
          %{key: "trade", title: "Осмотреть рынок", note: "редкие реагенты"},
          %{key: "rumors", title: "Собрать слухи", note: "дорога на север"}
        ]
      },
      %{
        id: "kamen",
        name: "Камни",
        type: "ruin",
        icon: "◘",
        x: 88.0,
        y: 37.0,
        desc: "Каменный круг в предгорьях.",
        subtitle: "Старый круг",
        hero: "Предгорья",
        layout: "ruin",
        text: ["Над плитами стоит сухая тишина. Руна на центральном камне выглядит свежей."],
        actions: [
          %{key: "inspect", title: "Осмотреть круг", note: "следы старой магии"},
          %{key: "camp", title: "Разбить лагерь", note: "опасно после заката"}
        ]
      },
      %{
        id: "lake-village",
        name: "Малые Воды",
        type: "village",
        icon: "⌂",
        x: 55.5,
        y: 61.0,
        desc: "Деревня у озера.",
        subtitle: "Озерная деревня",
        hero: "Причал",
        layout: "settlement",
        text: [
          "Сети сохнут на кольях, дети гоняют деревянный обруч, а староста делает вид, что не ждал вас."
        ],
        actions: [
          %{key: "rest", title: "Отдохнуть", note: "восстановить усталость"},
          %{key: "boat", title: "Нанять лодку", note: "путь через озеро"}
        ]
      },
      %{
        id: "windmill",
        name: "Мельница",
        type: "village",
        icon: "⌂",
        x: 69.5,
        y: 49.5,
        desc: "Мельница и хутор мельника.",
        subtitle: "Ветряной хутор",
        hero: "Мельничный холм",
        layout: "settlement",
        text: ["Крылья мельницы скрипят даже без ветра. На двери висит знак гильдии поставщиков."],
        actions: [
          %{key: "supplies", title: "Купить припасы", note: "мука, сухари, соль"},
          %{key: "work", title: "Помочь мельнику", note: "малая награда"}
        ]
      },
      %{
        id: "east-farms",
        name: "Жёлтые Поля",
        type: "village",
        icon: "⌂",
        x: 83.5,
        y: 55.0,
        desc: "Житница княжества — сельскохозяйственные артели.",
        subtitle: "Полевые артели",
        hero: "Пшеничные полосы",
        layout: "settlement",
        text: [
          "Поля идут до горизонта, но чучела стоят слишком ровно, будто их расставлял военный инженер."
        ],
        actions: [
          %{key: "harvest", title: "Помочь на поле", note: "провиант"},
          %{key: "investigate", title: "Проверить чучела", note: "странный порядок"}
        ]
      },
      %{
        id: "hermitage",
        name: "Скит",
        type: "ruin",
        icon: "◘",
        x: 21.5,
        y: 40.5,
        desc: "Заброшенная хижина в горах.",
        subtitle: "Заброшенный скит",
        hero: "Горная хижина",
        layout: "ruin",
        text: ["В очаге лежит тёплый пепел. Кто-то ушёл недавно и намеренно не заметал следы."],
        actions: [
          %{key: "search", title: "Обыскать скит", note: "записки и травы"},
          %{key: "wait", title: "Подождать хозяина", note: "риск встречи"}
        ]
      },
      %{
        id: "farmstead",
        name: "Хутор",
        type: "camp",
        icon: "▲",
        x: 48.0,
        y: 89.0,
        desc: "Ваша база — маленький хутор на юге.",
        subtitle: "Ваша база",
        hero: "Дом",
        layout: "farmstead",
        text: [
          "Скрипит калитка. Пёс без одного уха привычно не гавкает. На крыльце — чей-то оставленный вчера свёрток."
        ],
        actions: [
          %{key: "base", title: "Войти в дом", note: "личные комнаты", accent: true},
          %{key: "forge", title: "В мастерскую", note: "крафт и ремонт"},
          %{key: "garden", title: "Огород и запасы", note: "провиант"}
        ]
      }
    ]
  end
end
