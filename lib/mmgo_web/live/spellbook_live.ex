defmodule MMGOWeb.SpellbookLive do
  @moduledoc """
  The Tower spellbook, wired to the real `MMGO.Spells`/`MMGO.Grimoires`
  contexts through `MMGO.Play`.

  Map-first (GDD §5): magic only works at the Tower, so mount gates on the
  session character's location. Domain rules stay in their contexts — this view
  only composes reads and forwards player intent.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

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

  @impl true
  def mount(_params, session, socket) do
    case session_character(session) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/play/continue")}

      character ->
        case LocationGate.gate(socket, character, :tower) do
          {:halt, socket} ->
            {:ok, socket}

          {:ok, socket} ->
            {:ok, state} = Play.spellbook_state(character)

            {:ok,
             socket
             |> assign(:page_title, "Гримуар")
             |> assign(:view, :cast)
             |> assign(:compiling, false)
             |> assign(:last_spell, nil)
             |> assign(:compile_error, nil)
             |> assign(:pending_formula, nil)
             |> assign(:grimoire_order, nil)
             |> assign_spellbook_state(state)}
        end
    end
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

      attrs = %{
        "formula" => formula,
        "school" => params["school"] || "chaos",
        "base_id" => params["base"]
      }

      # Give the circle a beat to settle before the server-authoritative
      # compile lands; the compile itself is deterministic (MMGO.Play).
      Process.send_after(self(), {:spell_compiled, attrs}, 1200)

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

    case Play.create_grimoire(socket.assigns.character.id, "Чистый переплёт #{index}") do
      {:ok, _grimoire} -> {:noreply, socket |> reload_spellbook() |> push_shelf()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("grimoire_activate", %{"id" => id}, socket) do
    case Play.activate_grimoire(socket.assigns.character.id, id) do
      {:ok, _result} -> {:noreply, socket |> reload_spellbook() |> push_shelf()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("grimoire_inscribe", %{"id" => id}, socket) do
    case Play.inscribe_next_spell(socket.assigns.character.id, id) do
      {:ok, _entry} -> {:noreply, socket |> reload_spellbook() |> push_shelf()}
      {:error, _reason} -> {:noreply, socket}
    end
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
  def handle_info({:spell_compiled, attrs}, socket) do
    case Play.compile_spell(socket.assigns.character.id, attrs) do
      {:ok, spell} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:compiling, false)
         |> assign(:last_spell, spell_view(spell))
         |> assign(:compile_error, nil)
         |> assign(:pending_formula, nil)
         |> push_event("spell_result", %{ok: true})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:compiling, false)
         |> assign(:last_spell, nil)
         |> assign(:compile_error, compile_error_message(reason))
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

  # ------------------------------------------------------------------
  # Session + server-authoritative state
  # ------------------------------------------------------------------

  defp session_character(session) do
    with id when is_binary(id) <- session["demo_character_id"],
         {:ok, %{character: character}} <- Play.load_demo_state(id) do
      character
    else
      _other -> nil
    end
  end

  defp reload_spellbook(socket) do
    {:ok, state} = Play.spellbook_state(socket.assigns.character.id)
    assign_spellbook_state(socket, state)
  end

  defp assign_spellbook_state(socket, state) do
    socket
    |> assign(:character, %{
      id: state.character.id,
      name: state.character.name,
      level: state.character.level
    })
    |> assign(:spells, Enum.map(state.spells, &spell_view/1))
    |> assign(:grimoires, Enum.map(state.grimoires, &grimoire_view/1))
  end

  # Real Spell/Grimoire structs carry more (and less) than the book UI needs;
  # these adapters project them onto the flat shapes the templates and the
  # SpellCircle/GrimoireShelf JS hooks already consume.
  defp spell_view(spell) do
    %{
      id: spell.id,
      name: spell.name,
      formula: spell.formula,
      school: spell.school,
      description: spell.description,
      level_requirement: spell.level_requirement,
      fatigue_cost: spell.fatigue_cost,
      mana_cost: derived_mana_cost(spell),
      cooldown_turns: spell.cooldown_turns,
      delivery_form: spell.delivery_form,
      targeting: spell.targeting,
      effects: spell.effects,
      lineage: spell_lineage(spell)
    }
  end

  defp derived_mana_cost(spell) do
    case spell.effects do
      [] -> (spell.fatigue_cost || 0) * 2
      effects -> Enum.sum(Enum.map(effects, &(&1.intensity || 0)))
    end
  end

  defp spell_lineage(%{source_spell_id: id}) when is_binary(id), do: "производное заклинание"
  defp spell_lineage(_spell), do: "собственная формула"

  defp grimoire_view(grimoire) do
    %{
      id: grimoire.id,
      name: grimoire.name,
      status: grimoire.status,
      capacity: grimoire.capacity,
      weight: grimoire.weight,
      entries:
        grimoire.entries
        |> Enum.sort_by(& &1.slot_index)
        |> Enum.map(&%{slot: &1.slot_index, spell_id: &1.spell_id})
    }
  end

  defp compile_error_message(%Ecto.Changeset{}),
    do: "Круг не сомкнулся: формула вышла за пределы устойчивого заклинания."

  defp compile_error_message(:formula_too_short),
    do: "Слишком коротко — начерти хотя бы одно слово действия."

  defp compile_error_message(:invalid_school),
    do: "Не выбрана школа — круг не с чем связать."

  defp compile_error_message(_reason),
    do: "Круг вспыхнул слишком резко, и формула распалась. Попробуй иначе."
end
