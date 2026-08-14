defmodule MMGOWeb.SpellbookLive do
  @moduledoc """
  Scoped spell composition and grimoire loadouts.

  The LiveView only renders state supplied by `MMGO.Play` and forwards player
  choices back to that facade. Location, travel, ownership, and school rules
  are deliberately rechecked there for every command.
  """
  use MMGOWeb, :live_view

  alias MMGO.Arena.Ladder
  alias MMGO.Play
  alias MMGO.Spells.{Creation, Spell, SpellFailure}
  alias MMGO.Travel.Clock

  @max_visible_rejection_bytes 360
  @ritual_game_hours 1
  @rejection_control_pattern ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u
  @rejection_cyrillic_pattern ~r/[А-Яа-яЁё]/u
  @rejection_latin_pattern ~r/[A-Za-z]/u

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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(MMGO.PubSub, Creation.character_topic(character.id))
    end

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
         |> assign_spellbook_state(state)
         |> restore_recent_spell_creation(state)}

      {:error, reason} ->
        {:ok, redirect_for_spellbook_error(socket, reason)}
    end
  end

  @doc """
  The three leaves of the book are three pages.

  Writing a formula, arranging a loadout, and reading the index are different
  errands with different shapes, and cramming them behind ribbons in one corner
  made each of them harder to do. Each has its own address now, so a link means
  what it says and the back button works.
  """
  @impl true
  def handle_params(params, _uri, socket) do
    view =
      case socket.assigns.live_action do
        action when action in [:cast, :grimoires, :spells] -> action
        # `?view=` is how these were reached before they were pages.
        _other -> Map.get(params, "view")
      end

    {:noreply, switch_to_view(socket, view)}
  end

  @impl true
  def handle_event("switch_view", %{"view" => view}, socket) do
    {:noreply, switch_to_view(socket, view)}
  end

  def handle_event("hook_mounted", %{"hook" => "SpellCircle"}, socket) do
    {:noreply, push_spell_circle(socket)}
  end

  def handle_event("hook_mounted", %{"hook" => "GrimoireShelf"}, socket) do
    {:noreply, push_shelf(socket)}
  end

  def handle_event("spell_compile", params, socket) do
    case Play.begin_spell_creation(socket.assigns.current_scope.character, params) do
      {:ok, %{attempt: attempt}} ->
        {:noreply,
         socket
         |> assign(:spell_creation_attempt, attempt)
         |> assign(:compose_error, nil)
         |> assign(:last_spell, nil)
         |> assign(:action_feedback, nil)
         |> maybe_apply_immediate_spell_creation(attempt)}

      {:error, :spell_creation_in_progress} ->
        {:noreply, socket |> reload_spellbook() |> push_spell_circle()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:compose_error, spellbook_error_message(reason))
         |> assign(:last_spell, nil)
         |> push_event("spell_result", %{ok: false})}
    end
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

  # One tap on a formula is the fast path; the wrapped form above is the same
  # action reached from a keyboard.
  def handle_event(
        "inscribe",
        %{"grimoire_id" => grimoire_id, "spell_id" => spell_id},
        socket
      ) do
    handle_event(
      "inscribe",
      %{"inscription" => %{"grimoire_id" => grimoire_id, "spell_id" => spell_id}},
      socket
    )
  end

  def handle_event("inscribe", _params, socket) do
    {:noreply,
     assign(socket, :action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_inscription)
     })}
  end

  def handle_event("rename_grimoire", %{"grimoire_id" => grimoire_id, "name" => name}, socket) do
    case Play.rename_grimoire(socket.assigns.current_scope.character, grimoire_id, name) do
      {:ok, grimoire} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{
           kind: :success,
           message: "Переплёт теперь зовётся «#{grimoire.name}»."
         })
         |> maybe_push_shelf()}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("rename_spell", %{"spell_id" => spell_id, "name" => name}, socket) do
    case Play.rename_spell(socket.assigns.current_scope.character, spell_id, name) do
      {:ok, spell} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{
           kind: :success,
           message: "Формула теперь зовётся «#{spell.name}»."
         })}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("delete_spell", %{"spell_id" => spell_id}, socket) do
    case Play.delete_spell(socket.assigns.current_scope.character, spell_id) do
      {:ok, spell} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{
           kind: :success,
           message: "«#{spell.name}» сожжена и стёрта из всех переплётов."
         })
         |> maybe_push_shelf()}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("rename_grimoire", _params, socket) do
    {:noreply,
     assign(socket, :action_feedback, %{
       kind: :error,
       message: spellbook_error_message(:invalid_grimoire_name)
     })}
  end

  def handle_event(
        "erase",
        %{"grimoire_id" => grimoire_id, "spell_id" => spell_id},
        socket
      ) do
    case Play.erase_spell(socket.assigns.current_scope.character, grimoire_id, spell_id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Формула стёрта из переплёта."})
         |> maybe_push_shelf()}

      {:error, reason} ->
        {:noreply,
         assign(socket, :action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })}
    end
  end

  def handle_event("erase", _params, socket) do
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

  def handle_event("create_arena_grimoire", _params, socket) do
    case Play.create_arena_draft_grimoire(socket.assigns.current_scope.character) do
      {:ok, _grimoire} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{
           kind: :success,
           message: "Новый свободный гримуар на 45 формул открыт для записи."
         })
         |> push_shelf()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:action_feedback, %{
           kind: :error,
           message: spellbook_error_message(reason)
         })
         |> maybe_push_shelf()}
    end
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

  @impl true
  def handle_info({:spell_creation_revealed, attempt_id}, socket) do
    {:noreply, apply_revealed_spell_creation(socket, attempt_id)}
  end

  defp apply_revealed_spell_creation(socket, attempt_id) do
    case Play.spell_creation_result(socket.assigns.current_scope.character, attempt_id) do
      {:ok, spell} ->
        socket
        |> reload_spellbook()
        |> assign(:last_spell, spell)
        |> assign(:compose_error, nil)
        |> assign(:action_feedback, nil)
        |> push_spell_circle()
        |> push_event("spell_result", %{ok: true})

      {:error, {:spell_creation_failure, outcome}} ->
        socket
        |> reload_spellbook()
        |> assign(:compose_error, spell_creation_failure_message(outcome))
        |> assign(:last_spell, nil)
        |> push_spell_circle()
        |> push_event("spell_result", %{ok: false})

      {:error, _reason} ->
        reload_spellbook(socket)
    end
  end

  defp maybe_apply_immediate_spell_creation(socket, %{status: :revealed, id: attempt_id}),
    do: apply_revealed_spell_creation(socket, attempt_id)

  defp maybe_apply_immediate_spell_creation(socket, _attempt), do: socket

  @impl true
  def render(%{view: _view} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="spellbook-screen" class="scene-desk spellbook-scene">
        <div class="book spellbook-book">
          <div class="book__spine"></div>
          <div class="book__page">
            <%!-- Three pages, three links, full width. These were ribbons in the
                  top corner: a tap target the size of a fingernail on the one
                  device this game is played on. --%>
            <nav class="book__leaves" aria-label="Разделы гримуара">
              <.link
                :for={{leaf, id, label} <- spellbook_leaves()}
                id={id}
                navigate={leaf_path(@arena_mode?, leaf)}
                class={["book__leaf-tab", @view == leaf && "book__leaf-tab--active"]}
                aria-current={@view == leaf && "page"}
                aria-pressed={to_string(@view == leaf)}
              >
                {label}
              </.link>
            </nav>

            <.link
              id="spellbook-back-to-map"
              navigate={spellbook_exit_path(@arena_mode?)}
              class="book__back"
            >
              ← покинуть гримуар
            </.link>

            <%!-- Every leaf acts on the library, so the ink speaks on all of
                  them rather than only on the shelf. --%>
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

            <%= case @view do %>
              <% :cast -> %>
                <div class="book__leaf">
                  <p class="book__folio">личная книга магии · {@character.name}</p>
                  <h1 class="book__title">Создание заклинания</h1>
                  <p class="book__subtitle">
                    <%= if @composition_available? do %>
                      <span id="spellbook-location">
                        <%= if @arena_mode? do %>
                          Арена · полный круг отвечает мгновенно
                        <% else %>
                          {@composition_location.name} · начертите печать
                        <% end %>
                      </span>
                    <% else %>
                      круг откликается только в Башне или у вашего рабочего стола
                    <% end %>
                  </p>

                  <%= if @composition_available? do %>
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
                    <div id="spell-compose-locked" class="spellbook-note spellbook-note--locked">
                      <span class="spellbook-note__pin" aria-hidden="true"></span>
                      <p class="spellbook-note__kicker">Круг молчит</p>
                      <p>{composition_lock_message(@composition_lock_reason)}</p>
                      <p id="spellbook-read-only-note" class="spellbook-note__aside">
                        Заклинания и переплёты остаются доступны на соседних закладках.
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
                    <div
                      :if={@last_spell.manifestation}
                      id={"spell-compose-manifestation-#{@last_spell.id}"}
                      class="spellbook-note"
                    >
                      <p class="spellbook-note__kicker">
                        {manifestation_kind_label(@last_spell.manifestation.kind)}
                      </p>
                      <p>
                        {@last_spell.manifestation.display_name} · {manifestation_stats(
                          @last_spell.manifestation
                        )}
                      </p>
                      <p
                        :if={manifestation_trait_label(@last_spell.manifestation.trait)}
                        class="spellbook-note__aside"
                      >
                        {manifestation_trait_label(@last_spell.manifestation.trait)}
                      </p>
                      <p class="spellbook-note__aside">
                        Призыв существует только в бою и не становится предметом инвентаря.
                      </p>
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

                  <button
                    :if={@arena_mode?}
                    id="create-arena-grimoire"
                    type="button"
                    phx-click="create_arena_grimoire"
                    class="grim__panel-btn"
                  >
                    + Новый свободный гримуар · {MMGO.Arena.grimoire_capacity_for(@arena_profile)} формул
                  </button>

                  <p :if={@arena_mode?} id="arena-grimoire-policy" class="spellbook-note__aside">
                    Переплёты бесплатны и не ограничены по количеству. Активную раскладку можно
                    менять между боями: записывайте и стирайте формулы прямо в ней. В бой
                    берётся один гримуар — {MMGO.Arena.grimoire_capacity_for(@arena_profile)} формул.
                  </p>

                  <p :if={@grimoires == []} id="grimoire-empty" class="splist__empty">
                    На полке пока пусто. Новый физический гримуар приобретается у торговца.
                  </p>

                  <div :if={@grimoires != []} class="grim-list">
                    <article
                      :for={grimoire <- @grimoires}
                      id={"grimoire-#{grimoire.id}"}
                      class={[
                        "grim-vol",
                        active_grimoire?(grimoire, @active_grimoire) && "grim-vol--active"
                      ]}
                    >
                      <header class="grim-vol__head">
                        <div class="grim-vol__titling">
                          <p class="grim-vol__status">
                            {grimoire_status_label(grimoire.status)}
                            <span :if={active_grimoire?(grimoire, @active_grimoire)}>· боевой</span>
                          </p>
                          <form
                            id={"grimoire-rename-form-#{grimoire.id}"}
                            phx-submit="rename_grimoire"
                            class="grim-vol__rename"
                          >
                            <input type="hidden" name="grimoire_id" value={grimoire.id} />
                            <input
                              id={"grimoire-name-#{grimoire.id}"}
                              type="text"
                              name="name"
                              value={grimoire.name}
                              maxlength="60"
                              class="grim-vol__name"
                              aria-label={"Название переплёта #{grimoire.name}"}
                            />
                            <button
                              id={"grimoire-rename-#{grimoire.id}"}
                              type="submit"
                              class="grim-vol__rename-btn"
                            >
                              Переименовать
                            </button>
                          </form>
                        </div>
                        <span class="grim-vol__count">
                          {entry_count(grimoire)} / {grimoire.capacity}
                        </span>
                      </header>

                      <ol :if={grimoire_entries(grimoire) != []} class="grim-vol__entries">
                        <li :for={entry <- sorted_entries(grimoire)} id={"grimoire-entry-#{entry.id}"}>
                          <span class="grim-vol__entry-name">{entry_label(entry)}</span>
                          <button
                            :if={writable_grimoire?(grimoire, @writable_grimoires)}
                            id={"grimoire-erase-#{entry.id}"}
                            type="button"
                            phx-click="erase"
                            phx-value-grimoire_id={grimoire.id}
                            phx-value-spell_id={entry.spell_id}
                            class="grim-vol__erase"
                            aria-label={"Стереть #{entry_label(entry)}"}
                          >
                            Стереть
                          </button>
                        </li>
                      </ol>

                      <p :if={grimoire_entries(grimoire) == []} class="grim-vol__empty">
                        Переплёт пуст.
                      </p>

                      <div
                        :if={
                          @composition_available? and
                            writable_grimoire?(grimoire, @writable_grimoires)
                        }
                        id={"grimoire-inscribe-form-#{grimoire.id}"}
                        class="grim-vol__add"
                      >
                        <p class="grim-vol__add-label">Записать формулу</p>
                        <div
                          :if={uninscribed_spells(grimoire, @spells) != []}
                          class="grim-vol__add-list"
                        >
                          <button
                            :for={spell <- uninscribed_spells(grimoire, @spells)}
                            id={"grimoire-inscribe-#{grimoire.id}-#{spell.id}"}
                            type="button"
                            phx-click="inscribe"
                            phx-value-grimoire_id={grimoire.id}
                            phx-value-spell_id={spell.id}
                            class="grim-vol__add-btn"
                          >
                            <span
                              class="grim-vol__add-mark"
                              style={"background: #{school_color(spell.school)}"}
                            >
                            </span>
                            {spell.name}
                          </button>
                        </div>
                        <p
                          :if={uninscribed_spells(grimoire, @spells) == []}
                          class="grim-vol__add-empty"
                        >
                          Все известные формулы уже записаны здесь.
                        </p>
                      </div>

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

                  <%!-- The painted shelf keeps drag-to-reorder, but it is the
                        scenic view of a library the list above already manages. --%>
                  <div
                    id="grimoire-shelf-root"
                    phx-hook="GrimoireShelf"
                    phx-update="ignore"
                    aria-label="Полка гримуаров"
                  >
                  </div>
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
                        <p
                          :if={spell.school_quirk}
                          id={"spell-quirk-#{spell.id}"}
                          class="splist__lineage"
                        >
                          Особенность школы: {school_quirk_label(spell.school_quirk)}
                        </p>
                        <div
                          :if={spell.manifestation}
                          id={"spell-manifestation-#{spell.id}"}
                          class="spellbook-note"
                        >
                          <p class="spellbook-note__kicker">
                            {manifestation_kind_label(spell.manifestation.kind)}
                          </p>
                          <p>
                            {spell.manifestation.display_name} · {manifestation_stats(
                              spell.manifestation
                            )}
                          </p>
                          <p
                            :if={manifestation_trait_label(spell.manifestation.trait)}
                            class="spellbook-note__aside"
                          >
                            {manifestation_trait_label(spell.manifestation.trait)}
                          </p>
                        </div>
                        <div class="splist__stat-grid">
                          <div class="splist__stat">
                            <span class="splist__stat-label">Ранг</span>
                            <span class="splist__stat-value">{rank_requirement_label(spell)}</span>
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

                        <%!-- A library the player cannot prune is one they stop
                              reading. The formula is the spell; the name is only
                              what its author calls it. --%>
                        <div :if={@composition_available?} class="splist__manage">
                          <form
                            id={"spell-rename-form-#{spell.id}"}
                            phx-submit="rename_spell"
                            class="splist__rename"
                          >
                            <input type="hidden" name="spell_id" value={spell.id} />
                            <input
                              id={"spell-name-#{spell.id}"}
                              type="text"
                              name="name"
                              value={spell.name}
                              maxlength="120"
                              class="splist__name-field"
                              aria-label={"Название заклинания #{spell.name}"}
                            />
                            <button id={"spell-rename-#{spell.id}"} type="submit">
                              Переименовать
                            </button>
                          </form>

                          <button
                            id={"spell-delete-#{spell.id}"}
                            type="button"
                            phx-click="delete_spell"
                            phx-value-spell_id={spell.id}
                            data-confirm={"Сжечь «#{spell.name}»? Заклинание исчезнет из всех переплётов."}
                            class="splist__burn"
                          >
                            Сжечь формулу
                          </button>
                        </div>
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

  defp switch_to_view(socket, requested) do
    view =
      case requested do
        view when view in [:cast, :grimoires, :spells] -> view
        "cast" -> :cast
        "grimoires" -> :grimoires
        "spells" -> :spells
        _other -> Map.get(socket.assigns, :view, :cast)
      end

    socket =
      socket
      |> assign(:view, view)
      |> assign(:page_title, leaf_title(view))

    if view == :grimoires, do: push_shelf(socket), else: socket
  end

  defp leaf_title(:cast), do: "Круг заклинаний"
  defp leaf_title(:grimoires), do: "Полка гримуаров"
  defp leaf_title(:spells), do: "Библиотека"

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
    |> assign(:arena_mode?, Map.get(state, :arena_mode?, false))
    |> assign(:arena_profile, Map.get(state, :arena_profile))
    |> assign(:permitted_schools, state.permitted_schools)
    |> assign(:spell_circle_tier, state.spell_circle_tier)
    |> assign(:spell_creation_attempt, Map.get(state, :spell_creation_attempt))
    |> assign(:composition_location, state.composition_location)
    |> assign(:composition_available?, state.composition_available?)
    |> assign(:composition_lock_reason, state.composition_lock_reason)
    |> assign(:writable_grimoires, Map.get(state, :writable_grimoires, []))
  end

  defp restore_recent_spell_creation(
         socket,
         %{recent_spell_creation_attempt: %{outcome: %{"kind" => "success"}, spell: %{} = spell}}
       ) do
    socket
    |> assign(:last_spell, spell)
    |> assign(:compose_error, nil)
  end

  defp restore_recent_spell_creation(
         socket,
         %{recent_spell_creation_attempt: %{outcome: %{"kind" => "failure"} = outcome}}
       ) do
    socket
    |> assign(:last_spell, nil)
    |> assign(:compose_error, spell_creation_failure_message(outcome))
  end

  defp restore_recent_spell_creation(socket, _state), do: socket

  defp composition_lock_message(:travelling),
    do: "В пути нельзя менять гримуар. После прибытия доберитесь до Башни или своей базы."

  defp composition_lock_message(:spellbook_location),
    do: "Новые формулы создаются только в Башне или на своей базе."

  defp composition_lock_message(_reason),
    do: "Создание новых формул сейчас недоступно."

  defp redirect_for_spellbook_error(socket, _reason) do
    destination =
      case socket.assigns[:current_scope] do
        %{game_mode: :arena} -> ~p"/arena"
        _world_or_missing -> ~p"/play"
      end

    socket
    |> put_flash(
      :error,
      "Не удалось открыть гримуар. Вернитесь к игровому входу и попробуйте снова."
    )
    |> push_navigate(to: destination)
  end

  defp push_spell_circle(socket) do
    attempt = socket.assigns.spell_creation_attempt

    push_event(socket, "spell_circle_init", %{
      slots:
        spell_circle_slots(
          socket.assigns.permitted_schools,
          socket.assigns.spells,
          socket.assigns.spell_circle_tier
        ),
      current: spell_creation_circle(attempt),
      ritual_duration_ms: ritual_duration_ms(socket.assigns.arena_mode?),
      ritual: spell_creation_ritual(attempt)
    })
  end

  defp spell_creation_circle(%{input: %{"circle" => circle}}) when is_map(circle), do: circle
  defp spell_creation_circle(_attempt), do: %{}

  defp spell_creation_ritual(nil), do: %{active: false, remaining_ms: 0}

  defp spell_creation_ritual(%{completes_at: %DateTime{} = completes_at}) do
    %{
      active: true,
      remaining_ms: max(DateTime.diff(completes_at, DateTime.utc_now(), :millisecond), 0)
    }
  end

  defp ritual_duration_ms(true), do: 0

  defp ritual_duration_ms(false) do
    Clock.game_hours_to_real_seconds(@ritual_game_hours) * 1_000
  end

  defp spell_circle_slots(permitted_schools, _spells, :novice) do
    school_options = spell_circle_school_options(permitted_schools)

    [
      %{key: "school", label: "Schola", required: true, kind: "select", options: school_options},
      %{key: "actio", label: "Actio", required: true, kind: "text"},
      %{key: "tempus", label: "Tempus", required: true, kind: "text"}
    ]
  end

  defp spell_circle_slots(permitted_schools, spells, :trained) do
    school_options = spell_circle_school_options(permitted_schools)

    spell_options = Enum.map(spells, &%{value: &1.id, label: &1.name})

    [
      %{key: "school", label: "Schola", required: true, kind: "select", options: school_options},
      %{key: "actio", label: "Actio", required: true, kind: "text"},
      %{key: "forma", label: "Forma", required: false, kind: "text"},
      %{key: "vis", label: "Vis", required: false, kind: "text"},
      %{key: "tempus", label: "Tempus", required: false, kind: "text"},
      %{key: "mutatio", label: "Mutatio", required: false, kind: "text"},
      %{key: "pretium", label: "Pretium", required: false, kind: "text"},
      %{
        key: "base",
        label: "Fundamen",
        required: false,
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

  defp spell_circle_instruction(:novice),
    do:
      "Круг самоучки: выберите школу и впишите по одному латинскому слову в печати Actio и Tempus. Все три печати обязательны."

  defp spell_circle_instruction(:trained),
    do:
      "Полный академический круг: обязательны Schola и Actio. Остальные печати уточняют действие, а Fundamen связывает новую формулу с известным заклинанием."

  defp school_label(school), do: Map.get(@school_labels, to_string(school), "Неизвестная школа")

  defp school_quirk_label(:escalation), do: "эскалация"
  defp school_quirk_label(:environment_shift), do: "замещение среды"
  defp school_quirk_label(:persistence), do: "устойчивость"
  defp school_quirk_label(:tempo), do: "темп"
  defp school_quirk_label(:vitality), do: "жизненная сила"
  defp school_quirk_label(:harvest), do: "жатва"
  defp school_quirk_label(:volatility), do: "нестабильность"
  defp school_quirk_label(:precision), do: "точность"
  defp school_quirk_label(_quirk), do: "неизвестная особенность"

  defp school_color(school) do
    hue = Map.get(@school_hues, to_string(school), 45)
    "hsl(#{hue}, 60%, 42%)"
  end

  defp spellbook_exit_path(true), do: ~p"/arena"
  defp spellbook_exit_path(false), do: ~p"/map"

  defp spellbook_leaves do
    [
      {:cast, "spellbook-tab-cast", "Создать"},
      {:grimoires, "spellbook-tab-grimoires", "Гримуары"},
      {:spells, "spellbook-tab-spells", "Заклинания"}
    ]
  end

  defp leaf_path(true, :cast), do: ~p"/arena/spellbook"
  defp leaf_path(true, :grimoires), do: ~p"/arena/spellbook/books"
  defp leaf_path(true, :spells), do: ~p"/arena/spellbook/library"
  defp leaf_path(false, :cast), do: ~p"/spellbook"
  defp leaf_path(false, :grimoires), do: ~p"/spellbook/books"
  defp leaf_path(false, :spells), do: ~p"/spellbook/library"

  defp manifestation_kind_label(:held_shield), do: "Удерживаемый щит"
  defp manifestation_kind_label(:summoned_weapon), do: "Призванное оружие"
  defp manifestation_kind_label(:creature_ally), do: "Существо-союзник"
  defp manifestation_kind_label(_kind), do: "Боевое проявление"

  defp manifestation_stats(%{kind: :held_shield, hp: hp, duration_turns: duration}),
    do: "прочность #{hp}, #{duration} х."

  defp manifestation_stats(%{kind: :summoned_weapon, power: power, duration_turns: duration}),
    do: "сила #{power}, #{duration} х."

  defp manifestation_stats(%{
         kind: :creature_ally,
         hp: hp,
         power: power,
         duration_turns: duration
       }),
       do: "здоровье #{hp}, сила #{power}, #{duration} х."

  defp manifestation_stats(_manifestation), do: "ограничено длительностью дуэли"

  # What the construct does beyond the plain blow, so the player can read it off
  # the page instead of discovering it mid-duel.
  defp manifestation_trait_label(:ignite), do: "поджигает цель"
  defp manifestation_trait_label(:chill), do: "сковывает цель холодом"
  defp manifestation_trait_label(:gale), do: "сбивает цель с ног"
  defp manifestation_trait_label(:drain), do: "вытягивает здоровье в вашу сторону"
  defp manifestation_trait_label(:mending), do: "залечивает раны вашей стороны"
  defp manifestation_trait_label(:rupture), do: "разрывает раны, добавляя урон"
  defp manifestation_trait_label(:bastion), do: "поглощает больше урона"
  defp manifestation_trait_label(:ward), do: "усиливает носителя при блоке"
  defp manifestation_trait_label(_trait), do: nil

  # Craft decides how strong a spell is; the rank it earned decides who may
  # wield it outside a custom room.
  defp rank_requirement_label(%Spell{} = spell),
    do: spell |> Spell.rank_requirement() |> Ladder.label()

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

  defp spellbook_error_message(:invalid_grimoire_name),
    do: "Имя переплёта должно быть от одного до шестидесяти знаков."

  defp spellbook_error_message(:invalid_composition), do: generic_composition_error()
  defp spellbook_error_message(:invalid_spell_circle), do: generic_composition_error()

  defp spellbook_error_message(:incomplete_spell_circle),
    do: "Обязательная печать осталась немой, и круг не смог замкнуться."

  defp spellbook_error_message(:invalid_spell_circle_word),
    do:
      "Одна из словесных печатей треснула: круг принимает в неё только одно латинское слово без пробелов."

  defp spellbook_error_message(:invalid_school),
    do: "Печать Schola не узнала выбранную школу и погасла."

  defp spellbook_error_message(:school_not_permitted),
    do: "Печать Schola вспыхнула и погасла: эта школа пока не признаёт вашего обучения."

  defp spellbook_error_message(:spell_creation_in_progress),
    do: "Предыдущий ритуал ещё не завершён на мировых часах Башни."

  defp spellbook_error_message(:arena_profile_required),
    do: "Свободные переплёты выдаются только профилю Арены."

  defp spellbook_error_message(:location_changed),
    do: "Круг потерял опору: место ритуала изменилось прежде, чем легла первая печать."

  defp spellbook_error_message(%SpellFailure{reason: reason}) do
    case safe_rejection_reason(reason) do
      {:ok, safe_reason} -> "Толкователь отверг формулу: «#{safe_reason}»"
      :error -> generic_spell_rejection()
    end
  end

  defp spellbook_error_message(:missing_api_key),
    do:
      "Связующая печать Башни не настроена, поэтому круг не может обратиться к толкователю. Формула здесь ни при чём; попробуйте позже."

  defp spellbook_error_message(reason)
       when reason in [:timeout, :econnrefused, :nxdomain, :closed, :enetunreach],
       do: provider_connection_error()

  defp spellbook_error_message(%Req.TransportError{}), do: provider_connection_error()

  defp spellbook_error_message(reason)
       when reason in [:invalid_response, :empty_response],
       do:
         "Ответ толкователя пришёл искажённым, и круг рассеял его ради безопасности. Повторите ритуал."

  defp spellbook_error_message(%Jason.DecodeError{}),
    do:
      "Ответ толкователя пришёл искажённым, и круг рассеял его ради безопасности. Повторите ритуал."

  defp spellbook_error_message({provider, status, _details})
       when provider in [:deepseek_api, :gemini_api] and is_integer(status),
       do: provider_status_error(status)

  defp spellbook_error_message(:invalid_inscription),
    do: "Выберите свой переплёт и заклинание для записи."

  defp spellbook_error_message(:invalid_grimoire), do: "Выберите гримуар из своей библиотеки."

  defp spellbook_error_message(%Ecto.Changeset{} = changeset) do
    error_fields = Keyword.keys(changeset.errors)

    cond do
      :base_spell_id in error_fields ->
        "Печать Fundamen не признала выбранную основу и разорвала связь с формулой."

      :school in error_fields ->
        "Печать Schola не признала выбранную школу и погасла."

      :formula in error_fields ->
        "Словесные печати не удержали формулу, и круг рассыпался до толкования."

      :name in error_fields ->
        spellbook_error_message(:invalid_grimoire_name)

      true ->
        spell_persistence_error()
    end
  end

  defp spellbook_error_message(_reason),
    do:
      "Круг погас из-за сбоя в Башне, а не из-за вашей формулы. Попробуйте повторить ритуал позже."

  defp spell_creation_failure_message(%{
         "failure_kind" => "spell_rejected",
         "reason" => reason
       }) do
    case safe_rejection_reason(reason) do
      {:ok, safe_reason} -> "Толкователь отверг формулу: «#{safe_reason}»"
      :error -> generic_spell_rejection()
    end
  end

  defp spell_creation_failure_message(%{"failure_kind" => "spell_rejected"}),
    do: generic_spell_rejection()

  defp spell_creation_failure_message(%{
         "failure_kind" => "user_error",
         "code" => code
       }) do
    case code do
      "invalid_composition" -> spellbook_error_message(:invalid_composition)
      "invalid_spell_circle" -> spellbook_error_message(:invalid_spell_circle)
      "incomplete_spell_circle" -> spellbook_error_message(:incomplete_spell_circle)
      "invalid_spell_circle_word" -> spellbook_error_message(:invalid_spell_circle_word)
      "invalid_school" -> spellbook_error_message(:invalid_school)
      "school_not_permitted" -> spellbook_error_message(:school_not_permitted)
      "spellbook_location" -> spellbook_error_message(:spellbook_location)
      "travelling" -> spellbook_error_message(:travelling)
      "location_changed" -> spellbook_error_message(:location_changed)
      _other -> generic_composition_error()
    end
  end

  defp spell_creation_failure_message(%{
         "failure_kind" => "validation",
         "fields" => fields
       })
       when is_list(fields) do
    cond do
      "base_spell_id" in fields ->
        "Печать Fundamen не признала выбранную основу и разорвала связь с формулой."

      "school" in fields ->
        "Печать Schola не признала выбранную школу и погасла."

      "formula" in fields or "incantation_slots" in fields ->
        "Словесные печати не удержали формулу, и круг рассыпался до толкования."

      true ->
        spell_persistence_error()
    end
  end

  defp spell_creation_failure_message(%{
         "failure_kind" => "provider_configuration"
       }),
       do: spellbook_error_message(:missing_api_key)

  defp spell_creation_failure_message(%{"failure_kind" => "transport_error"}),
    do: provider_connection_error()

  defp spell_creation_failure_message(%{
         "failure_kind" => "invalid_provider_response"
       }),
       do:
         "Ответ толкователя пришёл искажённым, и круг рассеял его ради безопасности. Повторите ритуал."

  defp spell_creation_failure_message(%{
         "failure_kind" => "provider_error",
         "provider_status" => status
       })
       when is_integer(status),
       do: provider_status_error(status)

  defp spell_creation_failure_message(_outcome),
    do:
      "Круг погас из-за сбоя в Башне, а не из-за вашей формулы. Попробуйте повторить ритуал позже."

  defp safe_rejection_reason(reason) when is_binary(reason) do
    if String.valid?(reason) do
      normalized_reason =
        reason
        |> String.trim()
        |> String.replace(~r/\s+/u, " ")

      cond do
        normalized_reason == "" -> :error
        byte_size(normalized_reason) > @max_visible_rejection_bytes -> :error
        Regex.match?(@rejection_control_pattern, normalized_reason) -> :error
        not Regex.match?(@rejection_cyrillic_pattern, normalized_reason) -> :error
        Regex.match?(@rejection_latin_pattern, normalized_reason) -> :error
        true -> {:ok, normalized_reason}
      end
    else
      :error
    end
  end

  defp safe_rejection_reason(_reason), do: :error

  defp provider_status_error(status) when status in [401, 403] do
    "Печать допуска к дальнему толкователю погасла. Формула здесь ни при чём; Башне требуется вмешательство хранителя."
  end

  defp provider_status_error(429) do
    "Дальний хор толкователей перегружен. Круг не стал искажать замысел; повторите ритуал немного позже."
  end

  defp provider_status_error(status) when status >= 500 do
    "Дальний толкователь сейчас молчит. Формула здесь ни при чём; повторите ритуал, когда связь с Башней укрепится."
  end

  defp provider_status_error(_status) do
    "Толкователь отвернулся до чтения формулы. Круг можно начертить снова немного позже."
  end

  defp provider_connection_error do
    "Связь Башни с дальним толкователем оборвалась прежде, чем он прочёл формулу. Попробуйте повторить ритуал."
  end

  defp spell_persistence_error do
    "Книга не смогла закрепить уже сложившиеся печати. Формула здесь ни при чём; повторите ритуал."
  end

  defp generic_spell_rejection do
    "Толкователь отверг формулу, но письмена причины расплылись по странице. Измените сочетание печатей и попробуйте снова."
  end

  defp generic_composition_error do
    "Печати не узнали начертание и рассыпались прежде, чем круг успел призвать толкователя."
  end
end
