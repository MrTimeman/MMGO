defmodule MMGOWeb.OrganizationsLive do
  @moduledoc """
  Player Organisations suite (GDD §17, cult flavour §5.5).

  DESIGN PASS — hardcoded demo data, no backend wiring. The old
  backend-wired version lives in git history; module name and routes are
  preserved so wiring can return later. Every seam is marked `# TODO: wire`.

  Three views, one module, dispatched on @live_action:

    * :index  /orgs             — the registry hall (mine + discoverable)
    * :new    /orgs/new         — the founding ceremony (4 in-screen steps)
    * :show   /orgs/:id[/:tab]  — an organisation's rooms (6 diegetic tabs)

  Ids are strings so /orgs/demo renders with no database. Interactive
  demo state (referendum tally, applications, облик preview) lives in
  assigns and is mutated by phx-click; tab switches patch the URL and
  preserve that state (see handle_params).

  See docs/UI_DESIGN_BRIEF.md · CSS in assets/css/screens/org.css (.org-).
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # ------------------------------------------------------------------
  # Kind archetypes (§17.2) — flavour presets, expectations not limits.
  # Each carries a sigil glyph and an accent token (defined in org.css).
  # ------------------------------------------------------------------
  @kind_order ~w(cult company council guild)

  @kind_meta %{
    "cult" => %{
      label: "Культ",
      sigil: "☾",
      accent: "--org-cult",
      tagline: "Вера, тайна и общий обряд",
      flavor:
        "Братство, связанное клятвой и тайной. Культы держат скрытое — тропы, реликвии, знание — " <>
          "и берут плату за доступ. Ждут преданности, дают принадлежность."
    },
    "company" => %{
      label: "Компания",
      sigil: "⚖",
      accent: "--org-company",
      tagline: "Прибыль, доли и общее дело",
      flavor:
        "Предприятие, что делит риск и барыш по долям. Компании держат лавки, караваны и пошлины. " <>
          "Ждут вложения, дают долю в прибыли."
    },
    "council" => %{
      label: "Совет",
      sigil: "❖",
      accent: "--org-council",
      tagline: "Закон, голос и общее благо",
      flavor:
        "Собрание, что правит местом и людьми через голос. Советы держат уставы, суды и общинную казну. " <>
          "Ждут участия, дают право слова."
    },
    "guild" => %{
      label: "Гильдия",
      sigil: "⚒",
      accent: "--org-guild",
      tagline: "Ремесло, честь и общая сила",
      flavor:
        "Братство мастеров и бойцов, спаянное делом. Гильдии держат мастерские, контракты и территорию. " <>
          "Ждут труда, дают защиту и славу."
    }
  }

  # ------------------------------------------------------------------
  # Governance blocks (§17.4) — the constitution builder vocabulary.
  # ------------------------------------------------------------------
  @leadership_opts [
    {"appoint", "Назначение основателем", "Основатель ставит преемника своей волей."},
    {"election", "Выборы членами", "Каждый полноправный член отдаёт один голос."},
    {"share", "По долям владения", "Голос весит столько, сколько долей за спиной."},
    {"duel", "Ритуальная дуэль", "Первенство берётся в честном поединке."},
    {"rotation", "Ротация", "Власть переходит по кругу через равный срок."},
    {"inheritance", "Наследование", "Титул передаётся названному наследнику."}
  ]

  @decision_opts [
    {"autocrat", "Единолично"},
    {"council", "Совет офицеров"},
    {"assembly", "Общий сбор"},
    {"share", "По долям"}
  ]

  @decision_domains [
    {"treasury", "Казна", "Кто волен тратить общее золото."},
    {"war", "Война", "Кто объявляет вражду и ведёт в бой."},
    {"admit", "Приём", "Кто решает, кому отворить двери."}
  ]

  @membership_opts [
    {"open", "Открытые двери", "Войти волен всякий, кто пожелает."},
    {"invite", "По приглашению", "Только по зову изнутри."},
    {"application", "Заявка и голос", "Проситель ждёт, пока братство рассудит."},
    {"dues", "Вступительный взнос", "Двери отворяет уплаченная монета."}
  ]

  # ------------------------------------------------------------------
  # Diegetic anthem cues (§16.5) — the music-box shelf on «облик».
  # ------------------------------------------------------------------
  @anthems [
    {"travel.safe", "Тихая дорога", "Ровный ход, когда путь безопасен."},
    {"tower.arrival", "Порог Башни", "Медь и хор у чёрного шпиля."},
    {"dungeon.explore.deep", "Нижние своды", "Глухой гул под каменной толщей."},
    {"combat.duel.elite", "Поединок равных", "Гроза струн, когда сходятся сильные."}
  ]

  # ------------------------------------------------------------------
  # Registry demo data (§17 index view).
  # ------------------------------------------------------------------
  @my_orgs [
    %{
      id: "demo",
      name: "Тихий Ход",
      kind: "cult",
      creed: "Ни шагом дольше, чем должно.",
      members: 23,
      role: "Хранитель тропы",
      banner: "Знамя Тихого Хода — свеча в подземном своде"
    }
  ]

  @discover_orgs [
    %{
      id: "sever",
      name: "Северный путь",
      kind: "company",
      creed: "Дорога платит тем, кто её держит.",
      members: 41,
      door: :application,
      banner: "Знамя дома «Северный путь» — весы над горным перевалом"
    },
    %{
      id: "sovet",
      name: "Совет Врат Зари",
      kind: "council",
      creed: "Голос города — закон города.",
      members: 9,
      door: :invite,
      banner: "Печать Совета Врат Зари — ключ и башня"
    },
    %{
      id: "pepel",
      name: "Пепел",
      kind: "guild",
      creed: "Кто прошёл огонь — не боится искры.",
      members: 68,
      door: :open,
      banner: "Знамя гильдии «Пепел» — молот над углями"
    }
  ]

  # ------------------------------------------------------------------
  # Full organisation rooms (§17.3–17.5 show view). Two seeded orgs so
  # the tabs render for /orgs/demo and /orgs/sever alike.
  # ------------------------------------------------------------------
  @org_demo %{
    id: "demo",
    name: "Тихий Ход",
    kind: "cult",
    creed: "Ни шагом дольше, чем должно.",
    founded: "3-е Месяца Листопада, 843 год",
    members: 23,
    treasury: 4_820,
    territory: "Перевал Волчьей пустоши · 3 скрытых тропы к Башне",
    banner: "Знамя Тихого Хода — свеча в подземном своде",
    my_role: "Хранитель тропы",
    events: [
      %{date: "14-е Жатвы", text: "Обряд посвящения: принята послушница Ирма Долль."},
      %{date: "12-е Жатвы", text: "Открыта третья тропа: Утёсы → Башня."},
      %{date: "9-е Жатвы", text: "Совет утвердил пошлину перевала — 8 монет за проход."},
      %{date: "5-е Жатвы", text: "Союз с домом «Северный путь» скреплён печатью (доля 15%)."}
    ],
    ladder: [
      %{
        rank: "Хранитель",
        note: "решающий голос",
        people: [
          %{name: "Альберт Северин", joined: "843", hint: "основатель · 25% долей"}
        ]
      },
      %{
        rank: "Проводники",
        note: "равный голос",
        people: [
          %{name: "Ирма Долль", joined: "844", hint: "412 проводок сквозь перевал"},
          %{name: "Кель Ворон", joined: "845", hint: "указал две скрытых тропы"}
        ]
      },
      %{
        rank: "Послушники",
        note: "без голоса",
        people: [
          %{name: "Мила Тэн", joined: "846", hint: "держит свечи у первого свода"},
          %{name: "Гром Задвор", joined: "847", hint: "испытательный срок"}
        ]
      }
    ],
    roles: [
      %{
        title: "Хранитель тропы",
        rank: 1,
        vote: "решающий голос",
        perms: ["казна: без предела", "приглашать", "объявлять войну", "изменять устав"]
      },
      %{
        title: "Проводник",
        rank: 2,
        vote: "равный голос",
        perms: ["казна: до 200", "приглашать", "открывать тропу"]
      },
      %{
        title: "Послушник",
        rank: 3,
        vote: "без голоса",
        perms: ["читать вести", "ходить тропами"]
      }
    ],
    income: [{"Взносы братьев", 620}, {"Пошлина перевала", 3_200}, {"Лавка амулетов", 480}],
    expense: [{"Свечи и обряды", 240}, {"Подкуп стражи", 300}, {"Содержание троп", 180}],
    shares: [
      %{holder: "Организация «Тихий Ход»", kind: "казна братства", pct: 60},
      %{holder: "Альберт Северин", kind: "основатель", pct: 25},
      %{holder: "Дом «Северный путь»", kind: "союзник", pct: 15}
    ],
    gov: %{
      "leadership" => "duel",
      "treasury" => "council",
      "war" => "autocrat",
      "admit" => "council",
      "membership" => "application"
    },
    applications: [
      %{id: "a1", name: "Тихон Пепел", note: "просит тропу к Башне для отряда", status: :pending},
      %{
        id: "a2",
        name: "Лея Морок",
        note: "отвергнута гильдией «Пепел», ищет приюта",
        status: :pending
      }
    ],
    referendum: %{
      question: "Выкупить четвёртую тропу — Гавань → Башня — за 2 000 монет?",
      ends: "закрытие через 2 дня",
      my_vote: nil,
      my_weight: 25,
      options: [%{key: "yes", label: "За", weight: 38}, %{key: "no", label: "Против", weight: 12}]
    }
  }

  @org_sever %{
    id: "sever",
    name: "Северный путь",
    kind: "company",
    creed: "Дорога платит тем, кто её держит.",
    founded: "18-е Месяца Céва, 841 год",
    members: 41,
    treasury: 12_400,
    territory: "Горный перевал · 2 караванных тракта · лавка у Врат Зари",
    banner: "Знамя дома «Северный путь» — весы над горным перевалом",
    my_role: "Пайщик",
    events: [
      %{date: "13-е Жатвы", text: "Караван «Соль» вернулся: чистый барыш 210 монет."},
      %{date: "10-е Жатвы", text: "Пайщики утвердили дивиденд — 4 монеты на долю."},
      %{date: "6-е Жатвы", text: "Заключён эскорт-контракт с Академией."}
    ],
    ladder: [
      %{
        rank: "Держатель",
        note: "по долям",
        people: [%{name: "Горан Вейл", joined: "841", hint: "основатель · 40% долей"}]
      },
      %{
        rank: "Пайщики",
        note: "голос по долям",
        people: [
          %{name: "Альберт Северин", joined: "846", hint: "15% долей · союзник"},
          %{name: "Дарья Кром", joined: "843", hint: "22% долей · караванщик"}
        ]
      },
      %{
        rank: "Приказчики",
        note: "без голоса",
        people: [%{name: "Юсуф Ланн", joined: "845", hint: "ведёт лавку у Врат"}]
      }
    ],
    roles: [
      %{
        title: "Держатель",
        rank: 1,
        vote: "по долям",
        perms: ["казна: без предела", "нанимать", "заключать контракты", "изменять устав"]
      },
      %{
        title: "Пайщик",
        rank: 2,
        vote: "по долям",
        perms: ["казна: до 1000", "голос по долям", "делить дивиденд"]
      },
      %{
        title: "Приказчик",
        rank: 3,
        vote: "без голоса",
        perms: ["вести лавку", "нанимать носильщиков"]
      }
    ],
    income: [{"Пошлина перевала", 5_400}, {"Караванный фрахт", 4_800}, {"Лавка у Врат", 2_200}],
    expense: [{"Жалованье эскорту", 1_600}, {"Фураж и телеги", 900}, {"Налог казне", 1_240}],
    shares: [
      %{holder: "Горан Вейл", kind: "держатель", pct: 40},
      %{holder: "Дарья Кром", kind: "пайщик", pct: 22},
      %{holder: "Организация «Северный путь»", kind: "казна компании", pct: 23},
      %{holder: "Альберт Северин", kind: "союзник", pct: 15}
    ],
    gov: %{
      "leadership" => "share",
      "treasury" => "share",
      "war" => "council",
      "admit" => "council",
      "membership" => "dues"
    },
    applications: [
      %{
        id: "b1",
        name: "Мирон Гусь",
        note: "предлагает третий караванный тракт",
        status: :pending
      }
    ],
    referendum: %{
      question: "Поднять пошлину перевала с 12 до 15 монет за телегу?",
      ends: "закрытие через 5 дней",
      my_vote: nil,
      my_weight: 15,
      options: [%{key: "yes", label: "За", weight: 40}, %{key: "no", label: "Против", weight: 45}]
    }
  }

  # ------------------------------------------------------------------
  # Lifecycle
  # ------------------------------------------------------------------
  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load character, memberships, invitations, treasuries.
    {:ok,
     socket
     |> assign(:page_title, "Организации")
     |> assign(:kind_order, @kind_order)
     |> assign(:my_orgs, @my_orgs)
     |> assign(:discover_orgs, @discover_orgs)
     # governance vocabulary — needed by templates in every view
     |> assign(:leadership_opts, @leadership_opts)
     |> assign(:decision_opts, @decision_opts)
     |> assign(:decision_domains, @decision_domains)
     |> assign(:membership_opts, @membership_opts)
     # founding ceremony (:new) state
     |> assign(:step, 1)
     |> assign(:new_kind, nil)
     |> assign(:new_name, "")
     |> assign(:new_creed, "")
     |> assign(:new_gov, %{
       "leadership" => "appoint",
       "treasury" => "council",
       "war" => "autocrat",
       "admit" => "application",
       "membership" => "invite"
     })
     |> assign(:sealed, false)
     # show-view interactive state
     |> assign(:org, nil)
     |> assign(:tab, "overview")
     |> assign(:invite_open, false)
     |> assign(:accent, nil)
     |> assign(:anthem, "travel.safe")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.live_action == :show do
      id = params["id"] || "demo"
      tab = params["tab"] || "overview"

      socket =
        if socket.assigns.org && socket.assigns.org.id == id do
          # Same org, only the tab changed — keep mutated demo state.
          socket
        else
          org = org_by_id(id)
          socket |> assign(:org, org) |> assign(:accent, @kind_meta[org.kind].accent)
        end

      {:noreply, assign(socket, :tab, tab)}
    else
      {:noreply, socket}
    end
  end

  # ------------------------------------------------------------------
  # Founding ceremony events (:new)
  # ------------------------------------------------------------------
  @impl true
  def handle_event("pick_kind", %{"kind" => kind}, socket) do
    {:noreply, socket |> assign(:new_kind, kind) |> assign(:step, 2)}
  end

  def handle_event("goto_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, :step, String.to_integer(step))}
  end

  def handle_event("edit_founding", %{"name" => name, "creed" => creed}, socket) do
    {:noreply, socket |> assign(:new_name, name) |> assign(:new_creed, creed)}
  end

  def handle_event("set_gov", %{"block" => block, "value" => value}, socket) do
    {:noreply, assign(socket, :new_gov, Map.put(socket.assigns.new_gov, block, value))}
  end

  def handle_event("seal", _params, socket) do
    # TODO: wire — persist organisation, constitution blocks, founder membership.
    {:noreply, assign(socket, :sealed, true)}
  end

  # ------------------------------------------------------------------
  # Show-view events
  # ------------------------------------------------------------------
  def handle_event("vote", %{"choice" => choice}, socket) do
    org = socket.assigns.org
    ref = org.referendum

    ref =
      if ref.my_vote do
        ref
      else
        options =
          Enum.map(ref.options, fn opt ->
            if opt.key == choice, do: %{opt | weight: opt.weight + ref.my_weight}, else: opt
          end)

        %{ref | my_vote: choice, options: options}
      end

    # TODO: wire — record share-weighted vote against the referendum.
    {:noreply, assign(socket, :org, %{org | referendum: ref})}
  end

  def handle_event("resolve_app", %{"id" => id, "decision" => decision}, socket) do
    org = socket.assigns.org
    status = if decision == "approve", do: :approved, else: :declined

    apps =
      Enum.map(org.applications, fn app ->
        if app.id == id, do: %{app | status: status}, else: app
      end)

    # TODO: wire — approve/decline membership application.
    {:noreply, assign(socket, :org, %{org | applications: apps})}
  end

  def handle_event("toggle_invite", _params, socket) do
    {:noreply, assign(socket, :invite_open, !socket.assigns.invite_open)}
  end

  def handle_event("set_accent", %{"accent" => accent}, socket) do
    {:noreply, assign(socket, :accent, accent)}
  end

  def handle_event("set_anthem", %{"cue" => cue}, socket) do
    {:noreply, assign(socket, :anthem, cue)}
  end

  # ==================================================================
  # RENDER — dispatch on @live_action
  # ==================================================================
  @impl true
  def render(%{live_action: :index} = assigns), do: render_index(assigns)
  def render(%{live_action: :new} = assigns), do: render_new(assigns)
  def render(%{live_action: :show} = assigns), do: render_show(assigns)

  # ------------------------------------------------------------------
  # VIEW 1 — /orgs : the registry hall
  # ------------------------------------------------------------------
  defp render_index(assigns) do
    ~H"""
    <div class="game-screen">
      <div class="org-wrap">
        <a href={~p"/map"} class="org-exit">← Выйти на карту</a>

        <header class="org-hall-head">
          <span class="org-hall-kicker">Зал уставов · Врата Зари</span>
          <h1 class="org-hall-title">Организации</h1>
          <p class="org-hall-sub">Братства, компании и советы, что делят власть над Эленвиром.</p>
        </header>

        <section class="org-section">
          <h2 class="org-section-title">Ваши братства</h2>
          <div class="org-card-list">
            <.link
              :for={o <- @my_orgs}
              navigate={~p"/orgs/#{o.id}"}
              class="org-card"
              style={accent_style(o.kind)}
            >
              <div class="org-card-banner">
                <.art_slot kind="banner" label={o.banner} variant="dark" />
                <span class="org-sigil">{kind_sigil(o.kind)}</span>
              </div>
              <div class="org-card-body">
                <div class="org-card-top">
                  <h3 class="org-card-name">{o.name}</h3>
                  <span class="org-kind-tag">{kind_label(o.kind)}</span>
                </div>
                <p class="org-card-creed">«{o.creed}»</p>
                <div class="org-card-foot">
                  <span class="org-role-badge">✦ {o.role}</span>
                  <span class="org-card-members">{o.members} членов</span>
                </div>
              </div>
            </.link>
          </div>
        </section>

        <section class="org-section">
          <h2 class="org-section-title">Открытые двери</h2>
          <p class="org-section-hint">Братства, что ищут новых рук и голосов.</p>
          <div class="org-card-list">
            <.link
              :for={o <- @discover_orgs}
              navigate={~p"/orgs/#{o.id}"}
              class="org-card org-card--discover"
              style={accent_style(o.kind)}
            >
              <div class="org-card-banner">
                <.art_slot kind="banner" label={o.banner} variant="dark" />
                <span class="org-sigil">{kind_sigil(o.kind)}</span>
              </div>
              <div class="org-card-body">
                <div class="org-card-top">
                  <h3 class="org-card-name">{o.name}</h3>
                  <span class="org-kind-tag">{kind_label(o.kind)}</span>
                </div>
                <p class="org-card-creed">«{o.creed}»</p>
                <div class="org-card-foot">
                  <span class={"org-door org-door--#{o.door}"}>{door_label(o.door)}</span>
                  <span class="org-card-members">{o.members} членов</span>
                </div>
              </div>
            </.link>
          </div>
        </section>

        <.link navigate={~p"/orgs/new"} class="org-found-btn">
          <span class="org-found-seal">✦</span>
          <span>Основать организацию</span>
        </.link>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  # VIEW 2 — /orgs/new : the founding ceremony
  # ------------------------------------------------------------------
  defp render_new(assigns) do
    assigns = assign(assigns, :steps, [{1, "Природа"}, {2, "Имя"}, {3, "Устав"}, {4, "Печать"}])

    ~H"""
    <div class="game-screen">
      <div class="org-wrap">
        <a href={~p"/orgs"} class="org-exit">← Назад в зал уставов</a>

        <header class="org-hall-head">
          <span class="org-hall-kicker">Обряд основания</span>
          <h1 class="org-hall-title">Новая организация</h1>
        </header>

        <ol class="org-steps">
          <li
            :for={{n, label} <- @steps}
            class={["org-step", @step == n && "is-active", @step > n && "is-done"]}
          >
            <span class="org-step-dot">{n}</span>
            <span class="org-step-label">{label}</span>
          </li>
        </ol>

        <%= case @step do %>
          <% 1 -> %>
            <section class="org-ceremony">
              <h2 class="org-ceremony-title">Какой природы ваше братство?</h2>
              <p class="org-ceremony-lead">
                Природа задаёт ожидания, не оковы. Компания может держать веру, культ — торговать.
              </p>
              <div class="org-kind-grid">
                <button
                  :for={k <- @kind_order}
                  type="button"
                  phx-click="pick_kind"
                  phx-value-kind={k}
                  class={["org-kind-card", @new_kind == k && "is-chosen"]}
                  style={accent_style(k)}
                >
                  <span class="org-kind-sigil">{kind_sigil(k)}</span>
                  <span class="org-kind-name">{kind_label(k)}</span>
                  <span class="org-kind-tagline">{kind_tagline(k)}</span>
                  <span class="org-kind-flavor">{kind_flavor(k)}</span>
                </button>
              </div>
            </section>
          <% 2 -> %>
            <section class="org-ceremony">
              <h2 class="org-ceremony-title">Наречение</h2>
              <p class="org-ceremony-lead">Имя и краткое кредо — то, что запомнят и повторят.</p>
              <form phx-change="edit_founding" class="org-name-form">
                <label class="org-field">
                  <span class="org-field-label">Имя организации</span>
                  <input
                    type="text"
                    name="name"
                    value={@new_name}
                    autocomplete="off"
                    placeholder="напр. Тихий Ход"
                    class="org-input"
                  />
                </label>
                <label class="org-field">
                  <span class="org-field-label">Кредо</span>
                  <input
                    type="text"
                    name="creed"
                    value={@new_creed}
                    autocomplete="off"
                    placeholder="одна строка, что скажет о вас всё"
                    class="org-input"
                  />
                </label>
              </form>
              <div class="org-name-preview" style={accent_style(@new_kind)}>
                <span class="org-sigil org-sigil--static">{kind_sigil(@new_kind)}</span>
                <div>
                  <p class="org-name-preview-name">{blank(@new_name, "Безымянное братство")}</p>
                  <p class="org-name-preview-creed">
                    «{blank(@new_creed, "…кредо ещё не сложено…")}»
                  </p>
                </div>
              </div>
              <div class="org-ceremony-nav">
                <button
                  type="button"
                  class="org-btn org-btn--ghost"
                  phx-click="goto_step"
                  phx-value-step="1"
                >
                  Назад
                </button>
                <button type="button" class="org-btn" phx-click="goto_step" phx-value-step="3">
                  Дальше
                </button>
              </div>
            </section>
          <% 3 -> %>
            <section class="org-ceremony">
              <h2 class="org-ceremony-title">Устав</h2>
              <p class="org-ceremony-lead">
                Соберите правление из блоков. Каждый выбор высекается в устав братства.
              </p>

              <div class="org-gov-block">
                <h3 class="org-gov-title">Как избирается глава</h3>
                <div class="org-gov-opts">
                  <button
                    :for={{val, label, hint} <- @leadership_opts}
                    type="button"
                    phx-click="set_gov"
                    phx-value-block="leadership"
                    phx-value-value={val}
                    class={["org-gov-opt", @new_gov["leadership"] == val && "is-picked"]}
                  >
                    <span class="org-gov-opt-label">{label}</span>
                    <span class="org-gov-opt-hint">{hint}</span>
                  </button>
                </div>
              </div>

              <div class="org-gov-block">
                <h3 class="org-gov-title">Кто решает</h3>
                <div :for={{domain, dlabel, dhint} <- @decision_domains} class="org-gov-domain">
                  <div class="org-gov-domain-head">
                    <span class="org-gov-domain-name">{dlabel}</span>
                    <span class="org-gov-domain-hint">{dhint}</span>
                  </div>
                  <div class="org-gov-chips">
                    <button
                      :for={{val, label} <- @decision_opts}
                      type="button"
                      phx-click="set_gov"
                      phx-value-block={domain}
                      phx-value-value={val}
                      class={["org-chip", @new_gov[domain] == val && "is-picked"]}
                    >
                      {label}
                    </button>
                  </div>
                </div>
              </div>

              <div class="org-gov-block">
                <h3 class="org-gov-title">Как входят в братство</h3>
                <div class="org-gov-opts">
                  <button
                    :for={{val, label, hint} <- @membership_opts}
                    type="button"
                    phx-click="set_gov"
                    phx-value-block="membership"
                    phx-value-value={val}
                    class={["org-gov-opt", @new_gov["membership"] == val && "is-picked"]}
                  >
                    <span class="org-gov-opt-label">{label}</span>
                    <span class="org-gov-opt-hint">{hint}</span>
                  </button>
                </div>
              </div>

              <div class="org-ceremony-nav">
                <button
                  type="button"
                  class="org-btn org-btn--ghost"
                  phx-click="goto_step"
                  phx-value-step="2"
                >
                  Назад
                </button>
                <button type="button" class="org-btn" phx-click="goto_step" phx-value-step="4">
                  К печати
                </button>
              </div>
            </section>
          <% 4 -> %>
            <section class="org-ceremony">
              <h2 class="org-ceremony-title">Скрепить устав</h2>
              <p class="org-ceremony-lead">Прочтите грамоту. Печать сделает братство явью.</p>

              <.charter
                name={blank(@new_name, "Безымянное братство")}
                kind={@new_kind}
                creed={blank(@new_creed, "…кредо ещё не сложено…")}
                gov={@new_gov}
                sealed={@sealed}
                leadership_opts={@leadership_opts}
                decision_opts={@decision_opts}
                decision_domains={@decision_domains}
                membership_opts={@membership_opts}
              />

              <div class="org-ceremony-nav">
                <%= if @sealed do %>
                  <.link navigate={~p"/orgs/demo"} class="org-btn">Войти в братство →</.link>
                <% else %>
                  <button
                    type="button"
                    class="org-btn org-btn--ghost"
                    phx-click="goto_step"
                    phx-value-step="3"
                  >
                    Назад
                  </button>
                  <button type="button" class="org-btn org-btn--seal" phx-click="seal">
                    Скрепить печатью
                  </button>
                <% end %>
              </div>
            </section>
        <% end %>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  # VIEW 3 — /orgs/:id[/:tab] : the organisation's rooms
  # ------------------------------------------------------------------
  @tabs [
    {"overview", "Обзор"},
    {"people", "Люди"},
    {"roles", "Роли"},
    {"treasury", "Казна"},
    {"charter", "Устав"},
    {"appearance", "Облик"}
  ]

  defp render_show(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="game-screen">
      <div class="org-wrap" style={accent_style(@org.kind)}>
        <a href={~p"/orgs"} class="org-exit">← В зал уставов</a>

        <header class="org-detail-head">
          <div class="org-card-banner org-detail-banner">
            <.art_slot kind="banner" label={@org.banner} variant="dark" />
            <span class="org-sigil">{kind_sigil(@org.kind)}</span>
          </div>
          <div class="org-detail-title-row">
            <h1 class="org-detail-name">{@org.name}</h1>
            <span class="org-kind-tag">{kind_label(@org.kind)}</span>
          </div>
          <p class="org-detail-creed">«{@org.creed}»</p>
        </header>

        <nav class="org-tabs" aria-label="Разделы организации">
          <.link
            :for={{key, label} <- @tabs}
            patch={~p"/orgs/#{@org.id}/#{key}"}
            class={["org-tab", @tab == key && "is-active"]}
          >
            {label}
          </.link>
        </nav>

        <div class="org-tab-body">
          <%= case @tab do %>
            <% "people" -> %>
              {people_tab(assigns)}
            <% "roles" -> %>
              {roles_tab(assigns)}
            <% "treasury" -> %>
              {treasury_tab(assigns)}
            <% "charter" -> %>
              {charter_tab(assigns)}
            <% "appearance" -> %>
              {appearance_tab(assigns)}
            <% _ -> %>
              {overview_tab(assigns)}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---- обзор -------------------------------------------------------
  defp overview_tab(assigns) do
    ~H"""
    <div class="org-panel-grid">
      <div class="org-stat">
        <span class="org-stat-label">Членов</span>
        <span class="org-stat-value">{@org.members}</span>
      </div>
      <div class="org-stat">
        <span class="org-stat-label">Казна</span>
        <span class="org-stat-value org-stat-value--gold">
          {fmt(@org.treasury)}<span class="org-coin">м</span>
        </span>
      </div>
      <div class="org-stat">
        <span class="org-stat-label">Основано</span>
        <span class="org-stat-value org-stat-value--sm">{@org.founded}</span>
      </div>
      <div class="org-stat">
        <span class="org-stat-label">Ваша роль</span>
        <span class="org-stat-value org-stat-value--sm">{@org.my_role}</span>
      </div>
    </div>

    <div class="org-territory">
      <span class="org-territory-sigil">⛰</span>
      <div>
        <span class="org-panel-kicker">Владения · фильтр карты</span>
        <p class="org-territory-note">{@org.territory}</p>
        <a href={~p"/map"} class="org-territory-link">Показать на карте →</a>
      </div>
    </div>

    <section class="org-feed">
      <h3 class="org-panel-title">Вести братства</h3>
      <ul class="org-feed-list">
        <li :for={e <- @org.events} class="org-feed-item">
          <span class="org-feed-date">{e.date}</span>
          <span class="org-feed-text">{e.text}</span>
        </li>
      </ul>
    </section>
    """
  end

  # ---- люди --------------------------------------------------------
  defp people_tab(assigns) do
    ~H"""
    <section>
      <div :for={group <- @org.ladder} class="org-rank-group">
        <div class="org-rank-head">
          <h3 class="org-rank-title">{group.rank}</h3>
          <span class="org-rank-note">{group.note}</span>
        </div>
        <ul class="org-member-list">
          <li :for={p <- group.people} class="org-member">
            <span class="org-member-mark">◈</span>
            <div class="org-member-main">
              <span class="org-member-name">{p.name}</span>
              <span class="org-member-hint">{p.hint}</span>
            </div>
            <span class="org-member-joined">с {p.joined}</span>
          </li>
        </ul>
      </div>
    </section>

    <section class="org-apps">
      <h3 class="org-panel-title">Прошения</h3>
      <div :for={app <- @org.applications} class="org-app">
        <div class="org-app-main">
          <span class="org-app-name">{app.name}</span>
          <span class="org-app-note">{app.note}</span>
        </div>
        <%= case app.status do %>
          <% :pending -> %>
            <div class="org-app-actions">
              <button
                type="button"
                class="org-mini-btn org-mini-btn--yes"
                phx-click="resolve_app"
                phx-value-id={app.id}
                phx-value-decision="approve"
              >
                Принять
              </button>
              <button
                type="button"
                class="org-mini-btn org-mini-btn--no"
                phx-click="resolve_app"
                phx-value-id={app.id}
                phx-value-decision="decline"
              >
                Отказать
              </button>
            </div>
          <% :approved -> %>
            <span class="org-app-verdict org-app-verdict--yes">✦ принят</span>
          <% :declined -> %>
            <span class="org-app-verdict org-app-verdict--no">✕ отказано</span>
        <% end %>
      </div>

      <button type="button" class="org-invite-toggle" phx-click="toggle_invite">
        {if @invite_open, do: "Скрыть зов", else: "＋ Позвать в братство"}
      </button>
      <div :if={@invite_open} class="org-invite-panel">
        <label class="org-field">
          <span class="org-field-label">Имя странника</span>
          <input
            type="text"
            class="org-input"
            placeholder="напр. Ирма Долль"
            autocomplete="off"
          />
        </label>
        <p class="org-invite-hint"># TODO: wire — отправить приглашение с ролью Послушник.</p>
        <button type="button" class="org-btn org-btn--sm">Послать зов</button>
      </div>
    </section>
    """
  end

  # ---- роли --------------------------------------------------------
  defp roles_tab(assigns) do
    ~H"""
    <section class="org-role-list">
      <article :for={role <- @org.roles} class="org-role-card">
        <div class="org-role-head">
          <span class="org-role-rank">{role.rank}</span>
          <h3 class="org-role-title">{role.title}</h3>
          <span class="org-role-vote">{role.vote}</span>
        </div>
        <div class="org-perm-chips">
          <span :for={perm <- role.perms} class="org-perm-chip">{perm}</span>
        </div>
      </article>
    </section>
    <p class="org-note">
      Вес голоса задаётся уставом: «по долям» — голос весит как доля владения; «равный» — один член, один голос.
    </p>
    """
  end

  # ---- казна -------------------------------------------------------
  defp treasury_tab(assigns) do
    assigns =
      assigns
      |> assign(:income_total, Enum.sum(Enum.map(assigns.org.income, &elem(&1, 1))))
      |> assign(:expense_total, Enum.sum(Enum.map(assigns.org.expense, &elem(&1, 1))))

    ~H"""
    <div class="org-treasury-head">
      <span class="org-panel-kicker">Общая казна</span>
      <span class="org-treasury-balance">{fmt(@org.treasury)}<span class="org-coin">м</span></span>
    </div>

    <section class="org-flow">
      <div class="org-flow-col">
        <h3 class="org-flow-title org-flow-title--in">Доход <span>+{fmt(@income_total)}</span></h3>
        <div :for={{label, amt} <- @org.income} class="org-flow-row">
          <span class="org-flow-bar-track">
            <span
              class="org-flow-bar org-flow-bar--in"
              style={"width:#{bar_pct(amt, @income_total)}%"}
            >
            </span>
          </span>
          <span class="org-flow-label">{label}</span>
          <span class="org-flow-amt">+{fmt(amt)}</span>
        </div>
      </div>
      <div class="org-flow-col">
        <h3 class="org-flow-title org-flow-title--out">Расход <span>−{fmt(@expense_total)}</span></h3>
        <div :for={{label, amt} <- @org.expense} class="org-flow-row">
          <span class="org-flow-bar-track">
            <span
              class="org-flow-bar org-flow-bar--out"
              style={"width:#{bar_pct(amt, @expense_total)}%"}
            >
            </span>
          </span>
          <span class="org-flow-label">{label}</span>
          <span class="org-flow-amt">−{fmt(amt)}</span>
        </div>
      </div>
    </section>

    <section class="org-shares">
      <h3 class="org-panel-title">Доли владения</h3>
      <div class="org-share-bar">
        <span
          :for={s <- @org.shares}
          class="org-share-seg"
          style={"width:#{s.pct}%"}
          title={"#{s.holder} — #{s.pct}%"}
        >
        </span>
      </div>
      <ul class="org-share-legend">
        <li :for={s <- @org.shares} class="org-share-item">
          <span class="org-share-dot"></span>
          <span class="org-share-holder">{s.holder}</span>
          <span class="org-share-kind">{s.kind}</span>
          <span class="org-share-pct">{s.pct}%</span>
        </li>
      </ul>
    </section>

    <section class="org-referendum">
      <div class="org-panel-kicker">Голосование о тратах</div>
      <p class="org-ref-question">{@org.referendum.question}</p>
      <span class="org-ref-ends">{@org.referendum.ends} · голос по долям</span>

      <div class="org-ref-tally">
        <div
          :for={opt <- @org.referendum.options}
          class={["org-ref-opt", @org.referendum.my_vote == opt.key && "is-mine"]}
        >
          <div class="org-ref-opt-head">
            <span class="org-ref-opt-label">{opt.label}</span>
            <span class="org-ref-opt-pct">{ref_pct(opt.weight, @org.referendum)}%</span>
          </div>
          <span class="org-ref-track">
            <span
              class={"org-ref-fill org-ref-fill--#{opt.key}"}
              style={"width:#{ref_pct(opt.weight, @org.referendum)}%"}
            >
            </span>
          </span>
        </div>
      </div>

      <%= if @org.referendum.my_vote do %>
        <p class="org-ref-voted">✦ Ваш голос ({@org.referendum.my_weight}% долей) отдан.</p>
      <% else %>
        <div class="org-ref-buttons">
          <button type="button" class="org-btn org-btn--sm" phx-click="vote" phx-value-choice="yes">
            Голос «за»
          </button>
          <button
            type="button"
            class="org-btn org-btn--sm org-btn--ghost"
            phx-click="vote"
            phx-value-choice="no"
          >
            Голос «против»
          </button>
        </div>
      <% end %>
    </section>
    """
  end

  # ---- устав -------------------------------------------------------
  defp charter_tab(assigns) do
    ~H"""
    <.charter
      name={@org.name}
      kind={@org.kind}
      creed={@org.creed}
      gov={@org.gov}
      sealed={true}
      leadership_opts={@leadership_opts}
      decision_opts={@decision_opts}
      decision_domains={@decision_domains}
      membership_opts={@membership_opts}
    />
    <p class="org-note">
      Поправка к уставу требует того же голоса, что и он был скреплён: соберите совет и внесите изменение.
    </p>
    """
  end

  # ---- облик -------------------------------------------------------
  defp appearance_tab(assigns) do
    assigns = assign(assigns, :anthems, @anthems)

    ~H"""
    <section>
      <h3 class="org-panel-title">Знамя</h3>
      <div class="org-card-banner org-appearance-banner" style={accent_var_style(@accent)}>
        <.art_slot kind="banner" label={@org.banner} variant="dark" />
        <span class="org-sigil">{kind_sigil(@org.kind)}</span>
      </div>
      <button type="button" class="org-upload-slot"># загрузить знамя (позже)</button>
    </section>

    <section class="org-appearance-block">
      <h3 class="org-panel-title">Цвет братства</h3>
      <p class="org-section-hint">Живой отклик на знамени выше.</p>
      <div class="org-accent-row">
        <button
          :for={{key, var} <- accent_choices()}
          type="button"
          phx-click="set_accent"
          phx-value-accent={var}
          class={["org-accent-swatch", @accent == var && "is-picked"]}
          style={"--swatch: var(#{var})"}
          aria-label={key}
        >
        </button>
      </div>
    </section>

    <section class="org-appearance-block">
      <h3 class="org-panel-title">Музыкальная шкатулка</h3>
      <p class="org-section-hint">Напев, что звучит в чертогах братства.</p>
      <ul class="org-anthem-list">
        <li :for={{cue, title, hint} <- @anthems}>
          <button
            type="button"
            phx-click="set_anthem"
            phx-value-cue={cue}
            class={["org-anthem", @anthem == cue && "is-playing"]}
          >
            <span class="org-anthem-note">{if @anthem == cue, do: "♫", else: "♪"}</span>
            <div class="org-anthem-main">
              <span class="org-anthem-title">{title}</span>
              <span class="org-anthem-hint">{hint}</span>
            </div>
            <code class="org-anthem-cue">{cue}</code>
          </button>
        </li>
      </ul>
    </section>

    <section class="org-appearance-block">
      <h3 class="org-panel-title">Девиз</h3>
      <p class="org-motto">«{@org.creed}»</p>
    </section>
    """
  end

  # ==================================================================
  # Shared function component — the CHARTER document (parchment)
  # Used by the founding ceremony (step 4) and the «устав» tab.
  # ==================================================================
  attr :name, :string, required: true
  attr :kind, :string, required: true
  attr :creed, :string, required: true
  attr :gov, :map, required: true
  attr :sealed, :boolean, default: false
  attr :leadership_opts, :list, required: true
  attr :decision_opts, :list, required: true
  attr :decision_domains, :list, required: true
  attr :membership_opts, :list, required: true

  defp charter(assigns) do
    ~H"""
    <article class={["org-charter", @sealed && "is-sealed"]}>
      <div class="org-charter-crest">{kind_sigil(@kind)}</div>
      <p class="org-charter-preamble">Сим уставом, скреплённым во Вратах Зари, учреждается</p>
      <h2 class="org-charter-name">{@name}</h2>
      <p class="org-charter-kind">— {kind_label(@kind)} —</p>
      <p class="org-charter-creed">«{@creed}»</p>

      <hr class="org-charter-rule" />

      <dl class="org-charter-clauses">
        <div class="org-charter-clause">
          <dt>Статья I · Глава</dt>
          <dd>
            Глава братства избирается через: <em>{opt_label(@leadership_opts, @gov["leadership"])}</em>.
          </dd>
        </div>
        <div :for={{domain, dlabel, _} <- @decision_domains} class="org-charter-clause">
          <dt>{domain_article(domain)} · {dlabel}</dt>
          <dd>
            Решения по делу «{String.downcase(dlabel)}» принимает: <em>{opt2_label(@decision_opts, @gov[domain])}</em>.
          </dd>
        </div>
        <div class="org-charter-clause">
          <dt>Статья V · Приём</dt>
          <dd>В братство входят: <em>{opt_label(@membership_opts, @gov["membership"])}</em>.</dd>
        </div>
      </dl>

      <div class="org-charter-foot">
        <div class="org-charter-sign">
          <span class="org-charter-signline">Альберт Северин</span>
          <span class="org-charter-signrole">основатель</span>
        </div>
        <div class={["org-charter-seal", @sealed && "is-pressed"]}>
          <span class="org-charter-seal-glyph">{kind_sigil(@kind)}</span>
          <span class="org-charter-seal-text">
            {if @sealed, do: "скреплено", else: "не скреплено"}
          </span>
        </div>
      </div>
    </article>
    """
  end

  # ==================================================================
  # Helpers
  # ==================================================================
  # Give templates access to the kind-meta map and gov vocab via closures/assigns.
  defp org_by_id("sever"), do: @org_sever
  defp org_by_id(_), do: @org_demo

  defp kind_label(nil), do: "—"
  defp kind_label(kind), do: @kind_meta[kind].label
  defp kind_sigil(nil), do: "✦"
  defp kind_sigil(kind), do: @kind_meta[kind].sigil
  defp kind_tagline(nil), do: ""
  defp kind_tagline(kind), do: @kind_meta[kind].tagline
  defp kind_flavor(nil), do: ""
  defp kind_flavor(kind), do: @kind_meta[kind].flavor
  defp kind_accent(nil), do: "--org-cult"
  defp kind_accent(kind), do: @kind_meta[kind].accent

  defp accent_style(kind), do: "--org-accent: var(#{kind_accent(kind)})"
  defp accent_var_style(var), do: "--org-accent: var(#{var})"

  defp accent_choices do
    [
      {"культ", "--org-cult"},
      {"компания", "--org-company"},
      {"совет", "--org-council"},
      {"гильдия", "--org-guild"}
    ]
  end

  defp door_label(:open), do: "открытые двери"
  defp door_label(:invite), do: "по приглашению"
  defp door_label(:application), do: "по заявке"

  defp opt_label(opts, value) do
    Enum.find_value(opts, "—", fn {v, label, _hint} -> if v == value, do: label end)
  end

  defp opt2_label(opts, value) do
    Enum.find_value(opts, "—", fn {v, label} -> if v == value, do: label end)
  end

  defp domain_article("treasury"), do: "Статья II"
  defp domain_article("war"), do: "Статья III"
  defp domain_article("admit"), do: "Статья IV"
  defp domain_article(_), do: "Статья"

  defp bar_pct(_amt, 0), do: 0
  defp bar_pct(amt, total), do: round(amt / total * 100)

  defp ref_pct(weight, %{options: options, my_vote: my_vote, my_weight: my_weight}) do
    base = Enum.sum(Enum.map(options, & &1.weight))
    total = if my_vote, do: base, else: base + my_weight
    if total == 0, do: 0, else: round(weight / total * 100)
  end

  defp fmt(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end

  defp blank(nil, fallback), do: fallback
  defp blank("", fallback), do: fallback
  defp blank(str, _fallback), do: str
end
