defmodule MMGOWeb.SpellbookLive do
  @moduledoc """
  Scoped spell composition and grimoire loadouts.

  The LiveView only renders state supplied by `MMGO.Play` and forwards player
  choices back to that facade. Location, travel, ownership, and school rules
  are deliberately rechecked there for every command.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @school_labels %{
    "fire" => "Огонь",
    "water" => "Вода",
    "earth" => "Земля",
    "air" => "Воздух",
    "life" => "Жизнь",
    "death" => "Смерть",
    "chaos" => "Хаос",
    "order" => "Порядок"
  }

  @school_hues %{
    "fire" => 18,
    "water" => 210,
    "earth" => 80,
    "air" => 190,
    "life" => 140,
    "death" => 270,
    "chaos" => 320,
    "order" => 45
  }

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case Play.spellbook_state(character) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(:page_title, "Гримуар")
         |> assign(:last_spell, nil)
         |> assign(:compose_error, nil)
         |> assign(:action_feedback, nil)
         |> assign(:view, :cast)
         |> assign(:grimoire_order, nil)
         |> assign(:inscription_form, inscription_form())
         |> assign_spellbook_state(state)}

      {:error, reason} ->
        {:ok, redirect_for_spellbook_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("switch_view", %{"view" => view}, socket) do
    view =
      case view do
        "cast" -> :cast
        "grimoires" -> :grimoires
        "spells" -> :spells
        _other -> socket.assigns.view
      end

    socket = assign(socket, :view, view)
    {:noreply, if(view == :grimoires, do: push_shelf(socket), else: socket)}
  end

  @impl true
  def handle_event("hook_mounted", %{"hook" => "SpellCircle"}, socket) do
    {:noreply,
     push_event(socket, "spell_circle_init", %{
       slots:
         spell_circle_slots(
           socket.assigns.permitted_schools,
           socket.assigns.spells,
           socket.assigns.spell_circle_tier
         ),
       current: %{}
     })}
  end

  def handle_event("hook_mounted", %{"hook" => "GrimoireShelf"}, socket) do
    {:noreply, push_shelf(socket)}
  end

  @impl true
  def handle_event("spell_compile", params, socket) when is_map(params) do
    {:noreply, compile_spell(socket, params, true)}
  end

  def handle_event("spell_compile", _params, socket) do
    {:noreply,
     socket
     |> assign(:compose_error, spellbook_error_message(:invalid_composition))
     |> assign(:last_spell, nil)
     |> push_event("spell_result", %{ok: false})}
  end

  @impl true
  def handle_event(
        "inscribe",
        %{"inscription" => %{"grimoire_id" => grimoire_id, "spell_id" => spell_id}},
        socket
      ) do
    case Play.inscribe_spell(socket.assigns.current_scope.character, grimoire_id, spell_id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Заклинание внесено в переплёт."})
         |> maybe_push_shelf()}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("inscribe", _params, socket) do
    {:noreply,
     assign(socket, :action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_inscription)
     })}
  end

  def handle_event(
        "shelf_inscribe",
        %{"grimoire_id" => grimoire_id, "spell_id" => spell_id},
        socket
      ) do
    case Play.inscribe_spell(socket.assigns.current_scope.character, grimoire_id, spell_id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Чернила легли в переплёт."})
         |> push_shelf()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })
         |> push_shelf()}
    end
  end

  def handle_event("shelf_inscribe", _params, socket) do
    {:noreply,
     socket
     |> assign(:action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_inscription)
     })
     |> push_shelf()}
  end

  @impl true
  def handle_event("activate", %{"id" => grimoire_id}, socket) do
    case Play.activate_grimoire(socket.assigns.current_scope.character, grimoire_id) do
      {:ok, _grimoire} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Боевой гримуар выбран."})
         |> maybe_push_shelf()}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("activate", _params, socket) do
    {:noreply,
     assign(socket, :action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_grimoire)
     })}
  end

  def handle_event("shelf_activate", %{"id" => grimoire_id}, socket) do
    case Play.activate_grimoire(socket.assigns.current_scope.character, grimoire_id) do
      {:ok, _grimoire} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Этот том теперь боевой."})
         |> push_shelf()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })
         |> push_shelf()}
    end
  end

  def handle_event("shelf_activate", _params, socket) do
    {:noreply,
     socket
     |> assign(:action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_grimoire)
     })
     |> push_shelf()}
  end

  def handle_event("grimoire_reorder", %{"id" => id} = params, socket) do
    current_order =
      socket.assigns.grimoire_order || Enum.map(socket.assigns.grimoires, & &1.id)

    order_without_moved = Enum.reject(current_order, &(&1 == id))

    new_order =
      case Map.get(params, "before_id") do
        nil -> order_without_moved ++ [id]
        before_id -> insert_before(order_without_moved, id, before_id)
      end

    {:noreply, socket |> assign(:grimoire_order, new_order) |> push_shelf()}
  end

  defp compile_spell(socket, attrs, notify_circle?) do
    case Play.compile_structured_spell(socket.assigns.current_scope.character, attrs) do
      {:ok, result} ->
        socket
        |> reload_spellbook()
        |> assign(:last_spell, compiled_spell(result))
        |> assign(:compose_error, nil)
        |> assign(:action_feedback, nil)
        |> maybe_refresh_spell_circle(notify_circle?)
        |> maybe_push_spell_result(notify_circle?, true)

      {:error, reason} ->
        socket
        |> assign(:compose_error, spellbook_error_message(reason))
        |> assign(:last_spell, nil)
        |> maybe_push_spell_result(notify_circle?, false)
    end
  end

  @impl true
  def render(%{view: _view} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="spellbook-screen" class="scene-desk spellbook-scene">
        <div class="book spellbook-book">
          <div class="book__spine"></div>
          <div class="book__page">
            <nav class="book__ribbons" aria-label="Разделы гримуара">
              <button
                id="spellbook-tab-cast"
                type="button"
                class={["book__ribbon", @view == :cast && "book__ribbon--active"]}
                phx-click="switch_view"
                phx-value-view="cast"
                aria-pressed={to_string(@view == :cast)}
              >
                Создать
              </button>
              <button
                id="spellbook-tab-grimoires"
                type="button"
                class={["book__ribbon", @view == :grimoires && "book__ribbon--active"]}
                phx-click="switch_view"
                phx-value-view="grimoires"
                aria-pressed={to_string(@view == :grimoires)}
              >
                Гримуары
              </button>
              <button
                id="spellbook-tab-spells"
                type="button"
                class={["book__ribbon", @view == :spells && "book__ribbon--active"]}
                phx-click="switch_view"
                phx-value-view="spells"
                aria-pressed={to_string(@view == :spells)}
              >
                Заклинания
              </button>
            </nav>

            <.link id="spellbook-back-to-map" navigate={~p"/map"} class="book__back">
              ← покинуть гримуар
            </.link>

            <%= case @view do %>
              <% :cast -> %>
                <div class="book__leaf">
                  <p class="book__folio">личная книга магии · {@character.name}</p>
                  <h1 class="book__title">Создание заклинания</h1>
                  <p class="book__subtitle">
                    <%= if @composition_available? do %>
                      <span id="spellbook-location">
                        {@composition_location.name} · начертите печать
                      </span>
                    <% else %>
                      круг откликается только в Башне или у вашего рабочего стола
                    <% end %>
                  </p>

                  <%= if spell_circle_available?(
                    @composition_available?,
                    @spell_circle_tier,
                    @spells
                  ) do %>
                    <p id="spell-circle-instruction" class="spell-ritual__hint">
                      {spell_circle_instruction(@spell_circle_tier)}
                    </p>
                    <div
                      id="spell-circle-root"
                      phx-hook="SpellCircle"
                      phx-update="ignore"
                      data-circle-tier={to_string(@spell_circle_tier)}
                      aria-label="Ритуальный круг создания заклинания"
                    />
                  <% else %>
                    <div
                      :if={not @composition_available?}
                      id="spell-compose-locked"
                      class="spellbook-note spellbook-note--locked"
                    >
                      <span class="spellbook-note__pin" aria-hidden="true"></span>
                      <p class="spellbook-note__kicker">Круг молчит</p>
                      <p>{composition_lock_message(@composition_lock_reason)}</p>
                      <p id="spellbook-read-only-note" class="spellbook-note__aside">
                        Заклинания и переплёты остаются доступны на соседних закладках.
                      </p>
                    </div>

                    <div
                      :if={
                        @composition_available? and @spell_circle_tier == :trained and
                          @spells == []
                      }
                      id="spell-library-empty"
                      class="spellbook-note"
                    >
                      <p class="spellbook-note__kicker">Чистая страница</p>
                      <p>
                        Для полного академического круга нужна известная основа заклинания.
                      </p>
                    </div>
                  <% end %>

                  <div
                    :if={@compose_error}
                    id="spell-compose-error"
                    role="alert"
                    class="sc-result spell-ritual__error"
                  >
                    <span class="sc-result__kicker">Круг распался</span>
                    <p class="sc-result__desc">{@compose_error}</p>
                  </div>

                  <article
                    :if={@last_spell}
                    id={"spell-compose-result-#{@last_spell.id}"}
                    class="sc-result"
                  >
                    <span class="sc-result__kicker">Новое заклинание записано</span>
                    <h2 class="sc-result__name">{@last_spell.name}</h2>
                    <p class="sc-result__formula">«{@last_spell.formula}»</p>
                    <p class="sc-result__desc">{lineage_label(@last_spell)}</p>
                    <div class="sc-result__meta">
                      <span>{school_label(@last_spell.school)}</span>
                    </div>
                  </article>
                </div>
              <% :grimoires -> %>
                <div id="grimoire-loadouts" class="book__leaf">
                  <p class="book__folio">переплёты и боевая раскладка</p>
                  <h1 class="book__title">Полка гримуаров</h1>
                  <p class="book__subtitle">
                    {length(@grimoires)} томов · выберите корешок, чтобы раскрыть книгу
                  </p>

                  <div
                    id="grimoire-shelf-root"
                    phx-hook="GrimoireShelf"
                    phx-update="ignore"
                    aria-label="Полка гримуаров"
                  >
                  </div>

                  <p :if={@grimoires == []} id="grimoire-empty" class="splist__empty">
                    На полке пока пусто. Новый физический гримуар приобретается у торговца.
                  </p>

                  <div
                    :if={@action_feedback}
                    id="spellbook-action-feedback"
                    class={[
                      "spellbook-ink-feedback",
                      @action_feedback.kind == :error && "spellbook-ink-feedback--error"
                    ]}
                  >
                    {@action_feedback.message}
                  </div>

                  <details :if={@grimoires != []} class="grim-fallback">
                    <summary>Каталог переплётов</summary>
                    <div class="grim-fallback__list">
                      <article
                        :for={grimoire <- @grimoires}
                        id={"grimoire-#{grimoire.id}"}
                        class={[
                          "grim-fallback__volume",
                          active_grimoire?(grimoire, @active_grimoire) &&
                            "grim-fallback__volume--active"
                        ]}
                      >
                        <div class="grim-fallback__head">
                          <div>
                            <p>{grimoire_status_label(grimoire.status)}</p>
                            <h2>{grimoire.name}</h2>
                          </div>
                          <span>{entry_count(grimoire)} / {grimoire.capacity}</span>
                        </div>

                        <ol :if={grimoire_entries(grimoire) != []} class="grim-fallback__entries">
                          <li
                            :for={entry <- sorted_entries(grimoire)}
                            id={"grimoire-entry-#{entry.id}"}
                          >
                            <span>{entry_label(entry)}</span>
                            <small>слот {entry.slot_index}</small>
                          </li>
                        </ol>

                        <.form
                          :if={
                            @composition_available? and
                              writable_grimoire?(grimoire, @writable_grimoires) and
                              uninscribed_spells(grimoire, @spells) != []
                          }
                          for={@inscription_form}
                          id={"grimoire-inscribe-form-#{grimoire.id}"}
                          phx-submit="inscribe"
                          class="grim-fallback__form"
                        >
                          <.input
                            field={@inscription_form[:grimoire_id]}
                            id={"grimoire-target-#{grimoire.id}"}
                            type="hidden"
                            value={grimoire.id}
                          />
                          <.input
                            field={@inscription_form[:spell_id]}
                            id={"grimoire-spell-#{grimoire.id}"}
                            type="select"
                            label="Заклинание для записи"
                            options={spell_options(uninscribed_spells(grimoire, @spells))}
                            prompt="Выберите формулу"
                            required
                          />
                          <button
                            id={"grimoire-inscribe-#{grimoire.id}"}
                            type="submit"
                            class="grim__panel-btn"
                          >
                            Записать в переплёт
                          </button>
                        </.form>

                        <button
                          :if={
                            @composition_available? and
                              not active_grimoire?(grimoire, @active_grimoire)
                          }
                          id={"grimoire-activate-#{grimoire.id}"}
                          type="button"
                          phx-click="activate"
                          phx-value-id={grimoire.id}
                          class="grim__panel-btn"
                        >
                          Сделать боевым
                        </button>
                      </article>
                    </div>
                  </details>
                </div>
              <% :spells -> %>
                <div id="spell-library" class="book__leaf">
                  <p class="book__folio">личная библиотека</p>
                  <h1 class="book__title">Известные заклинания</h1>
                  <p class="book__subtitle">записей в указателе: {length(@spells)}</p>

                  <p :if={@spells == []} id="spell-library-empty-copy" class="splist__empty">
                    Указатель пуст. Сначала изучите или создайте заклинание.
                  </p>

                  <div :if={@spells != []} class="splist">
                    <details
                      :for={spell <- @spells}
                      id={"spell-library-#{spell.id}"}
                      class="splist__row"
                    >
                      <summary>
                        <span
                          class="splist__mark"
                          style={"background: #{school_color(spell.school)}"}
                        >
                        </span>
                        <span class="splist__name">{spell.name}</span>
                        <span class="splist__school">{school_label(spell.school)}</span>
                      </summary>
                      <div class="splist__body">
                        <p class="splist__formula">«{spell.formula}»</p>
                        <p :if={spell.description} class="splist__desc">{spell.description}</p>
                        <div class="splist__stat-grid">
                          <div class="splist__stat">
                            <span class="splist__stat-label">Уровень</span>
                            <span class="splist__stat-value">{spell.level_requirement}+</span>
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
                            <span class="splist__stat-value">
                              {delivery_form_label(spell.delivery_form)}
                            </span>
                          </div>
                        </div>
                        <p class="splist__lineage">{lineage_label(spell)}</p>
                      </div>
                    </details>
                  </div>
                </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp reload_spellbook(socket) do
    case Play.spellbook_state(socket.assigns.current_scope.character) do
      {:ok, state} -> assign_spellbook_state(socket, state)
      {:error, reason} -> redirect_for_spellbook_error(socket, reason)
    end
  end

  defp push_shelf(socket) do
    ordered_grimoires =
      case socket.assigns.grimoire_order do
        nil ->
          socket.assigns.grimoires

        order ->
          order_index = Map.new(Enum.with_index(order))
          Enum.sort_by(socket.assigns.grimoires, &Map.get(order_index, &1.id, 999_999))
      end

    push_event(socket, "shelf_update", %{
      grimoires: Enum.map(ordered_grimoires, &shelf_grimoire(&1, socket.assigns))
    })
  end

  defp maybe_push_shelf(%{assigns: %{view: :grimoires}} = socket), do: push_shelf(socket)
  defp maybe_push_shelf(socket), do: socket

  defp shelf_grimoire(grimoire, assigns) do
    writable? = writable_grimoire?(grimoire, assigns.writable_grimoires)

    %{
      id: grimoire.id,
      name: grimoire.name,
      status:
        if(active_grimoire?(grimoire, assigns.active_grimoire),
          do: "active",
          else: to_string(grimoire.status)
        ),
      capacity: grimoire.capacity,
      weight: grimoire.weight,
      writable: writable?,
      available_spells:
        if(writable?,
          do:
            Enum.map(uninscribed_spells(grimoire, assigns.spells), fn spell ->
              %{value: spell.id, label: spell.name}
            end),
          else: []
        ),
      entries:
        Enum.map(grimoire_entries(grimoire), fn entry ->
          %{
            slot: max(entry.slot_index - 1, 0),
            spell: shelf_spell(entry)
          }
        end)
    }
  end

  defp shelf_spell(%{spell: spell}) when not is_nil(spell) do
    %{
      id: spell.id,
      name: spell.name,
      school: to_string(spell.school),
      cooldown: spell.cooldown_turns
    }
  end

  defp shelf_spell(_entry), do: nil

  defp insert_before(order, id, before_id) do
    {left, right} = Enum.split_while(order, &(&1 != before_id))
    left ++ [id] ++ right
  end

  defp assign_spellbook_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:spells, state.spells)
    |> assign(:grimoires, state.grimoires)
    |> assign(:active_grimoire, state.active_grimoire)
    |> assign(:permitted_schools, state.permitted_schools)
    |> assign(:spell_circle_tier, state.spell_circle_tier)
    |> assign(:composition_location, state.composition_location)
    |> assign(:composition_available?, state.composition_available?)
    |> assign(:composition_lock_reason, state.composition_lock_reason)
    |> assign(:writable_grimoires, Map.get(state, :writable_grimoires, []))
  end

  defp composition_lock_message(:travelling),
    do: "В пути нельзя менять гримуар. После прибытия доберитесь до Башни или своей базы."

  defp composition_lock_message(:spellbook_location),
    do: "Новые формулы создаются только в Башне или на своей базе."

  defp composition_lock_message(_reason),
    do: "Создание новых формул сейчас недоступно."

  defp redirect_for_spellbook_error(socket, _reason) do
    socket
    |> put_flash(
      :error,
      "Не удалось открыть гримуар. Вернитесь к игровому входу и попробуйте снова."
    )
    |> push_navigate(to: ~p"/play")
  end

  defp maybe_push_spell_result(socket, false, _ok?), do: socket

  defp maybe_push_spell_result(socket, true, ok?),
    do: push_event(socket, "spell_result", %{ok: ok?})

  defp maybe_refresh_spell_circle(socket, false), do: socket

  defp maybe_refresh_spell_circle(socket, true) do
    push_event(socket, "spell_circle_init", %{
      slots:
        spell_circle_slots(
          socket.assigns.permitted_schools,
          socket.assigns.spells,
          socket.assigns.spell_circle_tier
        ),
      current: %{}
    })
  end

  defp spell_circle_slots(permitted_schools, _spells, :novice) do
    school_options = spell_circle_school_options(permitted_schools)

    [
      %{key: "school", label: "Школа", required: true, kind: "select", options: school_options},
      %{key: "actio", label: "Акцио", required: true, kind: "text"},
      %{key: "tempus", label: "Темпус", required: true, kind: "text"}
    ]
  end

  defp spell_circle_slots(permitted_schools, spells, :trained) do
    school_options = spell_circle_school_options(permitted_schools)

    spell_options = Enum.map(spells, &%{value: &1.id, label: &1.name})

    [
      %{key: "school", label: "Школа", required: true, kind: "select", options: school_options},
      %{key: "actio", label: "Акцио", required: true, kind: "text"},
      %{key: "forma", label: "Форма", required: false, kind: "text"},
      %{key: "vis", label: "Вис", required: false, kind: "text"},
      %{key: "tempus", label: "Темпус", required: false, kind: "text"},
      %{key: "mutatio", label: "Мутацио", required: false, kind: "text"},
      %{key: "pretium", label: "Прециум", required: false, kind: "text"},
      %{
        key: "base",
        label: "Основа",
        required: true,
        kind: "select",
        options: spell_options
      }
    ]
  end

  defp spell_circle_school_options(permitted_schools) do
    school_options =
      Enum.map(permitted_schools, fn school ->
        school = to_string(school)

        %{
          value: school,
          label: school_label(school),
          hue: Map.get(@school_hues, school, 45)
        }
      end)

    school_options
  end

  defp spell_circle_available?(false, _tier, _spells), do: false
  defp spell_circle_available?(true, :novice, _spells), do: true
  defp spell_circle_available?(true, :trained, spells), do: spells != []

  defp spell_circle_instruction(:novice),
    do:
      "Круг самоучки: выберите школу и впишите по одному слову в печати Акцио и Темпус. Все три печати обязательны."

  defp spell_circle_instruction(:trained),
    do:
      "Полный академический круг: обязательны Школа, Акцио и Основа; остальные печати уточняют действие."

  defp inscription_form do
    to_form(%{"grimoire_id" => "", "spell_id" => ""}, as: :inscription)
  end

  defp compiled_spell(%{spell: spell}), do: spell
  defp compiled_spell(spell), do: spell

  defp spell_options(spells), do: Enum.map(spells, &{"#{&1.name} — #{&1.formula}", &1.id})

  defp school_label(school), do: Map.get(@school_labels, to_string(school), "Неизвестная школа")

  defp school_color(school) do
    hue = Map.get(@school_hues, to_string(school), 45)
    "hsl(#{hue}, 60%, 42%)"
  end

  defp delivery_form_label(:single_target), do: "одна цель"
  defp delivery_form_label(:beam), do: "луч"
  defp delivery_form_label(:cone), do: "конус"
  defp delivery_form_label(:sphere), do: "сфера"
  defp delivery_form_label(:wall), do: "стена"
  defp delivery_form_label(:zone), do: "область"
  defp delivery_form_label(:self), do: "на себя"
  defp delivery_form_label(:link), do: "связь"
  defp delivery_form_label(:delayed_trigger), do: "отложенный запуск"
  defp delivery_form_label(_form), do: "иная"

  defp lineage_label(%{source_spell_id: source_spell_id}) when is_binary(source_spell_id),
    do: "Производная формула: она сохраняет связь с выбранной основой."

  defp lineage_label(_spell), do: "Самостоятельная формула из вашей библиотеки."

  defp entry_count(grimoire), do: length(grimoire_entries(grimoire))

  defp grimoire_entries(%{entries: entries}) when is_list(entries), do: entries
  defp grimoire_entries(_grimoire), do: []

  defp sorted_entries(grimoire), do: Enum.sort_by(grimoire_entries(grimoire), & &1.slot_index)

  defp entry_label(%{spell: %{name: name}}) when is_binary(name), do: name
  defp entry_label(_entry), do: "Записанная формула"

  defp active_grimoire?(grimoire, %{id: active_id}), do: grimoire.id == active_id
  defp active_grimoire?(_grimoire, _active_grimoire), do: false

  defp writable_grimoire?(grimoire, writable_grimoires) do
    Enum.any?(writable_grimoires, &(&1.id == grimoire.id))
  end

  defp uninscribed_spells(grimoire, spells) do
    inscribed_ids = MapSet.new(grimoire_entries(grimoire), & &1.spell_id)
    Enum.reject(spells, &MapSet.member?(inscribed_ids, &1.id))
  end

  defp grimoire_status_label(:draft), do: "чистый переплёт"
  defp grimoire_status_label(:sealed), do: "запечатан"
  defp grimoire_status_label(:active), do: "боевой"
  defp grimoire_status_label(_status), do: "неизвестное состояние"

  defp spellbook_error_message(:travelling),
    do: "Вы в пути. Дождитесь прибытия и откройте гримуар снова."

  defp spellbook_error_message(:spellbook_location),
    do: "Здесь магию не составить. Доберитесь до Башни или своей базы."

  defp spellbook_error_message(:not_grimoire_owner), do: "Этот переплёт вам не принадлежит."
  defp spellbook_error_message(:grimoire_not_found), do: "Переплёт не найден в вашей библиотеке."

  defp spellbook_error_message(:spell_not_found),
    do: "Это заклинание нельзя записать в ваш переплёт."

  defp spellbook_error_message(:no_spell_to_inscribe), do: "Нет доступной формулы для записи."
  defp spellbook_error_message(:invalid_composition), do: generic_composition_error()
  defp spellbook_error_message(:invalid_spell_circle), do: generic_composition_error()

  defp spellbook_error_message(:incomplete_spell_circle),
    do: "Заполните все обязательные печати круга."

  defp spellbook_error_message(:invalid_spell_circle_word),
    do: "В каждой словесной печати должно быть ровно одно слово из букв, не длиннее 32 байт."

  defp spellbook_error_message(:missing_spell_foundation),
    do: "Выберите известное заклинание для печати Основа."

  defp spellbook_error_message(:invalid_inscription),
    do: "Выберите свой переплёт и заклинание для записи."

  defp spellbook_error_message(:invalid_grimoire), do: "Выберите гримуар из своей библиотеки."
  defp spellbook_error_message(%Ecto.Changeset{}), do: generic_composition_error()
  defp spellbook_error_message(_reason), do: generic_composition_error()

  defp generic_composition_error do
    "Формула не сложилась. Проверьте обязательные печати и впишите в каждую словесную печать ровно одно слово."
  end
end
