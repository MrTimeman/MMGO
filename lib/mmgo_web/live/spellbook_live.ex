defmodule MMGOWeb.SpellbookLive do
  use MMGOWeb, :live_view

  @school_label %{
    fire: "Огонь",
    water: "Вода",
    earth: "Земля",
    air: "Воздух",
    life: "Жизнь",
    death: "Смерть",
    chaos: "Хаос",
    order: "Порядок"
  }

  @school_hue %{
    fire: 18,
    water: 210,
    earth: 80,
    air: 190,
    life: 140,
    death: 270,
    chaos: 320,
    order: 45
  }

  @school_order [:fire, :water, :earth, :air, :life, :death, :chaos, :order]

  @targeting_label %{
    self: "на себя",
    ally: "союзник",
    enemy: "враг",
    zone: "зона"
  }

  @delivery_label %{
    single_target: "одна цель",
    beam: "луч",
    cone: "конус",
    sphere: "сфера",
    wall: "стена",
    zone: "зона",
    self: "на себя",
    link: "связь",
    delayed_trigger: "отложенный триггер"
  }

  @demo_character %{id: "demo-albert", name: "Альберт Северин", level: 12}

  @demo_spells [
    %{
      id: "ember-spark",
      name: "Scintilla Cineris",
      formula: "Ictus Radius Levis",
      school: :fire,
      description: "Тонкая искра бьёт по одной цели и оставляет на коже серую метку жара.",
      level_requirement: 1,
      fatigue_cost: 3,
      mana_cost: 8,
      cooldown_turns: 1,
      delivery_form: :beam,
      targeting: :enemy,
      effects: [:burn],
      lineage: "академическая азбука Огня"
    },
    %{
      id: "chaos-veil",
      name: "Velum Discordiae",
      formula: "Scutum Nexus Mediocris Sustineo",
      school: :chaos,
      description: "Неровная завеса сбивает прицел и иногда меняет направление слабых чар.",
      level_requirement: 8,
      fatigue_cost: 7,
      mana_cost: 18,
      cooldown_turns: 3,
      delivery_form: :zone,
      targeting: :self,
      effects: [:deflect, :confuse],
      lineage: "на основе Scintilla Cineris"
    },
    %{
      id: "ash-wall",
      name: "Murus Favillae",
      formula: "Captio Murus Magnus Tardus Dissipatio",
      school: :fire,
      description: "Пепельная стена медленно поднимается из пола и крошится огненными хлопьями.",
      level_requirement: 11,
      fatigue_cost: 10,
      mana_cost: 24,
      cooldown_turns: 4,
      delivery_form: :wall,
      targeting: :zone,
      effects: [:block, :burn],
      lineage: "на основе Velum Discordiae"
    }
  ]

  @demo_grimoires [
    %{
      id: "gr-chaos",
      name: "Гримуар Хаоса",
      status: :active,
      capacity: 9,
      weight: 2.4,
      entries: [
        %{slot: 0, spell_id: "ember-spark"},
        %{slot: 1, spell_id: "chaos-veil"}
      ]
    },
    %{
      id: "gr-small",
      name: "Малый гримуар",
      status: :sealed,
      capacity: 5,
      weight: 1.1,
      entries: [%{slot: 0, spell_id: "ember-spark"}]
    },
    %{
      id: "gr-draft",
      name: "Новый переплёт",
      status: :draft,
      capacity: 7,
      weight: 1.8,
      entries: []
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — replace demo character/spells/grimoires with real player data.
    {:ok,
     socket
     |> assign(:page_title, "Гримуар")
     |> assign(:character, @demo_character)
     |> assign(:spells, @demo_spells)
     |> assign(:grimoires, @demo_grimoires)
     |> assign(:view, :cast)
     |> assign(:compiling, false)
     |> assign(:last_spell, nil)
     |> assign(:compile_error, nil)
     |> assign(:pending_formula, nil)
     |> assign(:grimoire_order, nil)}
  end

  @impl true
  def handle_event("switch_view", %{"view" => view}, socket) do
    view =
      case view do
        "cast" -> :cast
        "grimoires" -> :grimoires
        "spells" -> :spells
        _ -> socket.assigns.view
      end

    socket = assign(socket, :view, view)

    socket =
      if view == :grimoires do
        push_shelf(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("hook_mounted", %{"hook" => "SpellCircle"}, socket) do
    socket =
      push_event(socket, "spell_circle_init", %{
        slots: build_slots(socket.assigns.character, socket.assigns.spells),
        current: %{}
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("hook_mounted", %{"hook" => "GrimoireShelf"}, socket) do
    {:noreply, push_shelf(socket)}
  end

  @impl true
  def handle_event("spell_compile", params, socket) do
    if socket.assigns.compiling do
      {:noreply, socket}
    else
      formula = build_formula(params)
      school = params["school"] || "chaos"
      base_id = params["base"]

      # TODO: wire — send formula/school/base spell to the AI compiler.
      Process.send_after(
        self(),
        {:spell_compiled, %{formula: formula, school: school, base_id: base_id}},
        3000
      )

      {:noreply,
       socket
       |> assign(:compiling, true)
       |> assign(:compile_error, nil)
       |> assign(:pending_formula, formula)}
    end
  end

  @impl true
  def handle_event("grimoire_create", _params, socket) do
    index = length(socket.assigns.grimoires) + 1

    grimoire = %{
      id: "gr-demo-#{index}",
      name: "Чистый переплёт #{index}",
      status: :draft,
      capacity: 7,
      weight: 1.7,
      entries: []
    }

    {:noreply,
     socket |> assign(:grimoires, socket.assigns.grimoires ++ [grimoire]) |> push_shelf()}
  end

  @impl true
  def handle_event("grimoire_activate", %{"id" => id}, socket) do
    grimoires =
      Enum.map(socket.assigns.grimoires, fn g ->
        cond do
          g.id == id -> %{g | status: :active}
          g.status == :active -> %{g | status: :sealed}
          true -> g
        end
      end)

    {:noreply, socket |> assign(:grimoires, grimoires) |> push_shelf()}
  end

  @impl true
  def handle_event("grimoire_inscribe", %{"id" => id}, socket) do
    grimoires =
      Enum.map(socket.assigns.grimoires, fn g ->
        if g.id == id and g.status == :draft and length(g.entries) < g.capacity do
          inscribed_ids = Enum.map(g.entries, & &1.spell_id)

          case Enum.find(socket.assigns.spells, &(&1.id not in inscribed_ids)) do
            nil -> g
            spell -> %{g | entries: g.entries ++ [%{slot: length(g.entries), spell_id: spell.id}]}
          end
        else
          g
        end
      end)

    {:noreply, socket |> assign(:grimoires, grimoires) |> push_shelf()}
  end

  @impl true
  def handle_event("grimoire_reorder", %{"id" => id, "before_id" => before_id}, socket) do
    ids = Enum.map(socket.assigns.grimoires, & &1.id)
    order = socket.assigns.grimoire_order || ids
    order = Enum.reject(order, &(&1 == id))

    order =
      case before_id do
        nil -> order ++ [id]
        _ -> insert_before(order, id, before_id)
      end

    {:noreply, socket |> assign(:grimoire_order, order) |> push_shelf()}
  end

  @impl true
  def handle_info({:spell_compiled, params}, socket) do
    case scripted_compile(params, socket.assigns.spells) do
      {:ok, spell} ->
        {:noreply,
         socket
         |> assign(:compiling, false)
         |> assign(:last_spell, spell)
         |> assign(:compile_error, nil)
         |> assign(:pending_formula, nil)
         |> assign(:spells, socket.assigns.spells ++ [spell])
         |> push_event("spell_result", %{ok: true})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:compiling, false)
         |> assign(:last_spell, nil)
         |> assign(:compile_error, reason)
         |> assign(:pending_formula, nil)
         |> push_event("spell_result", %{ok: false})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="scene-desk">
      <%= if is_nil(@character) do %>
        <div style="text-align:center; margin-top: 20vh; color: #e7e5e4;">
          <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 2rem; margin-bottom: 1rem;">
            Гримуар
          </h1>
          <p style="margin-bottom: 2rem;">Продолжите локальную игру, чтобы открыть гримуар.</p>
          <a
            href={~p"/play/continue"}
            style="display: inline-block; padding: 0.75rem 2rem; background: var(--color-accent); color: #000; font-family: var(--font-serif); font-weight: bold; border-radius: 0.375rem; text-decoration: none;"
          >
            Войти в башню
          </a>
        </div>
      <% else %>
        <div class="book">
          <div class="book__spine"></div>
          <div class="book__page">
            <div class="book__ribbons">
              <button
                type="button"
                class={"book__ribbon#{if @view == :cast, do: " book__ribbon--active"}"}
                phx-click="switch_view"
                phx-value-view="cast"
              >
                Создать
              </button>
              <button
                type="button"
                class={"book__ribbon#{if @view == :grimoires, do: " book__ribbon--active"}"}
                phx-click="switch_view"
                phx-value-view="grimoires"
              >
                Гримуары
              </button>
              <button
                type="button"
                class={"book__ribbon#{if @view == :spells, do: " book__ribbon--active"}"}
                phx-click="switch_view"
                phx-value-view="spells"
              >
                Заклинания
              </button>
            </div>

            <a href={~p"/map"} class="book__back">&larr; покинуть башню</a>

            <%= case @view do %>
              <% :cast -> %>
                <.cast_leaf
                  character={@character}
                  compiling={@compiling}
                  compile_error={@compile_error}
                  last_spell={@last_spell}
                  pending_formula={@pending_formula}
                />
              <% :grimoires -> %>
                <.grimoires_leaf character={@character} />
              <% :spells -> %>
                <.spells_leaf spells={@spells} />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :character, :map, required: true
  attr :compiling, :boolean, required: true
  attr :compile_error, :any, required: true
  attr :last_spell, :any, required: true
  attr :pending_formula, :any, required: true

  defp cast_leaf(assigns) do
    ~H"""
    <div class="book__leaf">
      <h1 class="book__title">Создание заклинания</h1>
      <p class="book__subtitle">{@character.name}, начерти печать</p>
      <div
        id="spell-circle-root"
        phx-hook="SpellCircle"
        phx-update="ignore"
        style="min-height: 340px; display: flex; justify-content: center;"
      />

      <%= if @compiling do %>
        <div class="sc-result sc-result--working">
          <span class="sc-result__kicker">AI толкует круг</span>
          <p class="sc-result__formula">«{@pending_formula}»</p>
          <p class="sc-result__desc">
            Свечи гаснут, чернила ходят по странице. Ответ будет через несколько ударов сердца.
          </p>
        </div>
      <% end %>

      <%= if @compile_error do %>
        <div style="margin-top: 1rem; padding: 0.75rem 1rem; background: rgba(124,43,34,0.1); border: 1px solid var(--parch-red); border-radius: 0.375rem; color: var(--parch-red); font-size: 0.875rem;">
          {@compile_error}
        </div>
      <% end %>

      <%= if @last_spell do %>
        <div class="sc-result">
          <span class="sc-result__kicker">Новое заклинание записано</span>
          <h2 class="sc-result__name">{@last_spell.name}</h2>
          <p class="sc-result__formula">«{@last_spell.formula}»</p>
          <p class="sc-result__desc">{@last_spell.description}</p>
          <div class="sc-result__meta">
            <span>{school_label(@last_spell.school)}</span>
            <span>мана {@last_spell.mana_cost}</span>
            <span>усталость {@last_spell.fatigue_cost}</span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :character, :map, required: true

  defp grimoires_leaf(assigns) do
    ~H"""
    <div class="book__leaf">
      <h1 class="book__title">Полка гримуаров</h1>
      <p class="book__subtitle">переплетённые тома {@character.name}</p>
      <div id="grimoire-shelf-root" phx-hook="GrimoireShelf" phx-update="ignore"></div>
      <button
        type="button"
        phx-click="grimoire_create"
        style="margin-top: 1rem; padding: 0.5rem 1rem; background: var(--parch-paper-dark); border: 1px solid var(--parch-ink-faint); border-radius: 4px; color: var(--parch-ink); font-family: var(--font-serif); cursor: pointer;"
      >
        + Переплести новый гримуар
      </button>
    </div>
    """
  end

  attr :spells, :list, required: true

  defp spells_leaf(assigns) do
    ~H"""
    <div class="book__leaf">
      <h1 class="book__title">Известные заклинания</h1>
      <p class="book__subtitle">записей в списке: {length(@spells)}</p>

      <%= if @spells == [] do %>
        <p class="splist__empty">Список пуст. Сотвори что-нибудь достойное записи.</p>
      <% else %>
        <div class="splist">
          <%= for spell <- @spells do %>
            <details class="splist__row">
              <summary>
                <span class="splist__mark" style={"background: #{school_color(spell.school)}"}></span>
                <span class="splist__name">{spell.name}</span>
                <span class="splist__school">{school_label(spell.school)}</span>
              </summary>
              <div class="splist__body">
                <p class="splist__formula">«{spell.formula}»</p>
                <%= if spell.description do %>
                  <p class="splist__desc">{spell.description}</p>
                <% end %>
                <div class="splist__stat-grid">
                  <div class="splist__stat">
                    <span class="splist__stat-label">Уровень</span>
                    <span class="splist__stat-value">{spell.level_requirement}+</span>
                  </div>
                  <div class="splist__stat">
                    <span class="splist__stat-label">Мана</span>
                    <span class="splist__stat-value">{spell.mana_cost}</span>
                  </div>
                  <div class="splist__stat">
                    <span class="splist__stat-label">Утомление</span>
                    <span class="splist__stat-value">{spell.fatigue_cost}</span>
                  </div>
                  <div class="splist__stat">
                    <span class="splist__stat-label">Откат</span>
                    <span class="splist__stat-value">{spell.cooldown_turns} х.</span>
                  </div>
                  <div class="splist__stat">
                    <span class="splist__stat-label">Форма</span>
                    <span class="splist__stat-value">{delivery_label(spell.delivery_form)}</span>
                  </div>
                  <div class="splist__stat">
                    <span class="splist__stat-label">Цель</span>
                    <span class="splist__stat-value">{targeting_label(spell.targeting)}</span>
                  </div>
                  <%= if spell.effects != [] do %>
                    <div class="splist__stat">
                      <span class="splist__stat-label">Эффекты</span>
                      <span class="splist__stat-value">{length(spell.effects)}</span>
                    </div>
                  <% end %>
                </div>
                <p class="splist__lineage">{spell.lineage}</p>
              </div>
            </details>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp push_shelf(socket) do
    grimoires = order_grimoires(socket.assigns.grimoires, socket.assigns[:grimoire_order])

    push_event(socket, "shelf_update", %{
      grimoires: Enum.map(grimoires, &grimoire_json(&1, socket.assigns.spells))
    })
  end

  defp order_grimoires(grimoires, nil), do: grimoires

  defp order_grimoires(grimoires, order) do
    index = Map.new(Enum.with_index(order))
    Enum.sort_by(grimoires, &Map.get(index, &1.id, 999_999))
  end

  defp grimoire_json(grimoire, spells) do
    %{
      id: grimoire.id,
      name: grimoire.name,
      status: grimoire_status(grimoire.status),
      capacity: grimoire.capacity,
      weight: grimoire.weight,
      entries:
        Enum.map(grimoire.entries, fn entry ->
          spell = Enum.find(spells, &(&1.id == entry.spell_id))

          %{
            slot: entry.slot,
            spell: shelf_spell_json(spell)
          }
        end)
    }
  end

  defp shelf_spell_json(nil), do: nil

  defp shelf_spell_json(spell) do
    %{
      id: spell.id,
      name: spell.name,
      school: spell.school,
      cooldown: spell.cooldown_turns
    }
  end

  defp grimoire_status(:draft), do: "draft"
  defp grimoire_status(:sealed), do: "sealed"
  defp grimoire_status(:active), do: "active"

  defp insert_before(order, id, before_id) do
    {left, right} = Enum.split_while(order, &(&1 != before_id))
    left ++ [id] ++ right
  end

  # Canonical Latin incantation slots per GDD §2.2.2, in fixed order:
  # Actio (core action, always required) > Forma (shape) > Vis (power) >
  # Tempus (duration) > Mutatio (secondary effect) > Pretium (extra cost).
  # Only Actio is required — "a minimal spell uses only Actio... the AI
  # determines all other parameters."
  defp build_formula(params) do
    ["actio", "forma", "vis", "tempus", "mutatio", "pretium"]
    |> Enum.map(&Map.get(params, &1))
    |> Enum.reject(&(is_nil(&1) || &1 == ""))
    |> Enum.join(" ")
  end

  # Demo wizard circle: Schola, six Latin parameter slots from GDD §2.2.2,
  # and Fundamen as the optional base spell from the personal library.
  defp build_slots(character, known_spells) do
    _ = character

    school_options =
      Enum.map(@school_order, fn school ->
        %{
          value: Atom.to_string(school),
          label: school_label(school),
          hue: Map.get(@school_hue, school)
        }
      end)

    spell_options = Enum.map(known_spells, &%{value: &1.id, label: &1.name})

    [
      %{key: "school", label: "Schola", required: true, kind: "select", options: school_options},
      %{key: "actio", label: "Actio", required: true, kind: "text"},
      %{key: "forma", label: "Forma", required: false, kind: "text"},
      %{key: "vis", label: "Vis", required: false, kind: "text"},
      %{key: "tempus", label: "Tempus", required: false, kind: "text"},
      %{key: "mutatio", label: "Mutatio", required: false, kind: "text"},
      %{key: "pretium", label: "Pretium", required: false, kind: "text"},
      %{key: "base", label: "Fundamen", required: false, kind: "select", options: spell_options}
    ]
  end

  defp school_label(nil), do: "—"

  defp school_label(school) when is_atom(school),
    do: Map.get(@school_label, school, to_string(school))

  defp school_label(school) when is_binary(school),
    do: school |> String.to_existing_atom() |> school_label()

  defp school_color(nil), do: "hsl(0,0%,50%)"

  defp school_color(school) do
    hue = Map.get(@school_hue, to_atom(school), 0)
    "hsl(#{hue},60%,42%)"
  end

  defp to_atom(school) when is_atom(school), do: school
  defp to_atom(school) when is_binary(school), do: String.to_existing_atom(school)

  defp targeting_label(nil), do: "—"
  defp targeting_label(t), do: Map.get(@targeting_label, to_atom(t), to_string(t))

  defp delivery_label(nil), do: "—"
  defp delivery_label(d), do: Map.get(@delivery_label, to_atom(d), to_string(d))

  defp scripted_compile(%{formula: formula, school: school} = params, known_spells) do
    words = formula |> String.split(" ", trim: true)

    if scripted_failure?(words, school) do
      {:error,
       "Круг вспыхнул слишком резко: слова тянут школу в разные стороны, и формула распалась."}
    else
      {:ok, scripted_spell(params, known_spells, words)}
    end
  end

  defp scripted_failure?(["Sanatio" | _], "fire"), do: true
  defp scripted_failure?(["Ictus" | _], "life"), do: true
  defp scripted_failure?(["Scutum" | _], "death"), do: true
  defp scripted_failure?(_words, _school), do: false

  defp scripted_spell(%{formula: formula, school: school, base_id: base_id}, known_spells, words) do
    base = Enum.find(known_spells, &(&1.id == base_id))
    id = "demo-spell-#{System.unique_integer([:positive])}"

    %{
      id: id,
      name: scripted_name(words, school),
      formula: formula,
      school: to_atom(school),
      description:
        "AI принял намерение круга и связал его в устойчивую формулу: " <>
          "заклинание вспыхивает короткой дугой, затем оставляет после себя мерцающий след хаоса.",
      level_requirement: 12,
      fatigue_cost: 8 + max(length(words) - 2, 0),
      mana_cost: 16 + length(words) * 3,
      cooldown_turns: 3,
      delivery_form: :sphere,
      targeting: :enemy,
      effects: [:burn, :distort],
      lineage: if(base, do: "на основе #{base.name}", else: "создано без основы")
    }
  end

  defp scripted_name(["Captio" | _], _school), do: "Captio Lucis"
  defp scripted_name(["Scutum" | _], _school), do: "Aegis Nocturna"
  defp scripted_name(["Sanatio" | _], _school), do: "Sanatio Aurea"
  defp scripted_name(_words, "fire"), do: "Ignis Retortus"
  defp scripted_name(_words, _school), do: "Vinculum Incertum"
end
