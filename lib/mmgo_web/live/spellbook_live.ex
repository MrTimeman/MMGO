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
         |> assign(:inscription_form, inscription_form())
         |> assign_spellbook_state(state)
         |> reset_compose_form()}

      {:error, reason} ->
        {:ok, redirect_for_spellbook_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("compose", %{"composition" => attrs}, socket) when is_map(attrs) do
    case Play.compile_spell(socket.assigns.current_scope.character, attrs) do
      {:ok, result} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> reset_compose_form()
         |> assign(:last_spell, compiled_spell(result))
         |> assign(:compose_error, nil)
         |> assign(:action_feedback, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:compose_form, compose_form(attrs))
         |> assign(:compose_error, spellbook_error_message(reason))
         |> assign(:last_spell, nil)}
    end
  end

  def handle_event("compose", _params, socket) do
    {:noreply,
     socket
     |> assign(:compose_error, spellbook_error_message(:invalid_composition))
     |> assign(:last_spell, nil)}
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
         |> assign(:action_feedback, %{kind: :success, message: "Заклинание внесено в переплёт."})}

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

  @impl true
  def handle_event("activate", %{"id" => grimoire_id}, socket) do
    case Play.activate_grimoire(socket.assigns.current_scope.character, grimoire_id) do
      {:ok, _grimoire} ->
        {:noreply,
         socket
         |> reload_spellbook()
         |> assign(:action_feedback, %{kind: :success, message: "Боевой гримуар выбран."})}

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="spellbook-screen" class="mx-auto max-w-6xl space-y-6 pb-10">
        <header class="overflow-hidden rounded-[2rem] border border-amber-900/20 bg-stone-950 px-6 py-7 text-amber-50 shadow-2xl sm:px-8">
          <div class="flex flex-col gap-6 sm:flex-row sm:items-end sm:justify-between">
            <div class="max-w-2xl space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.28em] text-amber-300">
                Кабинет формул
              </p>
              <h1 class="font-serif text-3xl font-semibold tracking-tight sm:text-4xl">
                Гримуар {"·"} {@character.name}
              </h1>
              <p class="text-sm leading-6 text-stone-300">
                Составление доступно здесь: <span
                  id="spellbook-location"
                  class="font-semibold text-amber-200"
                >{@composition_location.name}</span>.
                Основа и школа всегда проверяются хранителем круга.
              </p>
            </div>

            <.link
              id="spellbook-back-to-map"
              navigate={~p"/map"}
              class="inline-flex min-h-11 items-center justify-center rounded-xl border border-amber-200/30 px-4 py-2 text-sm font-semibold text-amber-50 transition hover:border-amber-200 hover:bg-amber-100/10"
            >
              <.icon name="hero-map" class="mr-2 size-4" /> Вернуться к карте
            </.link>
          </div>
        </header>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1.12fr)_minmax(19rem,0.88fr)]">
          <section
            id="spell-compose-panel"
            class="rounded-[2rem] border border-amber-950/15 bg-[#ece0bd] p-5 shadow-lg sm:p-8"
          >
            <div class="mb-6 flex items-start justify-between gap-4 border-b border-amber-950/15 pb-5">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-amber-900/70">
                  Новая запись
                </p>
                <h2 class="mt-2 font-serif text-2xl font-semibold text-stone-950">
                  Создание заклинания
                </h2>
              </div>
              <span class="rounded-full border border-amber-900/20 bg-amber-100/70 px-3 py-1 text-xs font-semibold text-amber-950">
                {length(@permitted_schools)} школ
              </span>
            </div>

            <%= if @spells == [] do %>
              <div
                id="spell-library-empty"
                class="rounded-2xl border border-dashed border-amber-950/30 bg-amber-50/45 p-6"
              >
                <h3 class="font-serif text-xl font-semibold text-stone-950">Библиотека ещё пуста</h3>
                <p class="mt-2 max-w-xl text-sm leading-6 text-stone-700">
                  Изучите начальное заклинание или вернитесь к обучению, затем выберите основу для новой формулы.
                </p>
              </div>
            <% else %>
              <.form
                for={@compose_form}
                id="spell-compose-form"
                phx-submit="compose"
                class="space-y-1"
              >
                <.input
                  field={@compose_form[:base_spell_id]}
                  id="spell-compose-base"
                  type="select"
                  label="Основа заклинания"
                  options={spell_options(@spells)}
                  prompt="Выберите известную основу"
                  required
                />
                <.input
                  field={@compose_form[:school]}
                  id="spell-compose-school"
                  type="select"
                  label="Школа"
                  options={school_options(@permitted_schools)}
                  prompt="Выберите школу"
                  required
                />
                <.input
                  field={@compose_form[:formula]}
                  id="spell-compose-formula"
                  type="text"
                  label="Латинская формула"
                  placeholder="Ignis Radius"
                  autocomplete="off"
                  maxlength="180"
                  required
                />
                <p class="-mt-1 text-sm leading-6 text-stone-700">
                  От 1 до 6 латинских слов, до 180 байт. Формула проверяется на стороне мира.
                </p>

                <button
                  id="spell-compose-submit"
                  type="submit"
                  phx-disable-with="Формула проверяется…"
                  class="mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#a9791f] px-5 py-3 text-sm font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-amber-800 focus:outline-none focus:ring-2 focus:ring-amber-700 focus:ring-offset-2 focus:ring-offset-[#ece0bd]"
                >
                  <.icon name="hero-sparkles" class="mr-2 size-5" /> Сотворить заклинание
                </button>
              </.form>
            <% end %>

            <div
              :if={@compose_error}
              id="spell-compose-error"
              role="alert"
              class="mt-5 rounded-xl border border-[#7c2b22]/30 bg-[#7c2b22]/10 px-4 py-3 text-sm leading-6 text-[#5e1d16]"
            >
              {@compose_error}
            </div>

            <article
              :if={@last_spell}
              id={"spell-compose-result-#{@last_spell.id}"}
              class="mt-6 rounded-2xl border border-emerald-900/20 bg-emerald-50/70 p-5"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-800">
                Формула сохранена
              </p>
              <h3 class="mt-2 font-serif text-xl font-semibold text-stone-950">{@last_spell.name}</h3>
              <p class="mt-1 text-sm text-stone-700">
                {@last_spell.formula} {"·"} {school_label(@last_spell.school)}
              </p>
              <p class="mt-3 text-sm leading-6 text-stone-700">{lineage_label(@last_spell)}</p>
            </article>
          </section>

          <aside
            id="spellbook-loadout-summary"
            class="rounded-[2rem] border border-stone-900/10 bg-white/85 p-5 shadow-lg sm:p-6"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">
              Боевая раскладка
            </p>
            <%= if @active_grimoire do %>
              <h2 class="mt-3 font-serif text-2xl font-semibold text-stone-950">
                {@active_grimoire.name}
              </h2>
              <p class="mt-2 text-sm leading-6 text-stone-600">
                {entry_count(@active_grimoire)} / {@active_grimoire.capacity} формул {"·"} {@active_grimoire.weight} стоун
              </p>
              <span class="mt-5 inline-flex rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900">
                Активный гримуар
              </span>
            <% else %>
              <h2 class="mt-3 font-serif text-2xl font-semibold text-stone-950">
                Боевой гримуар не выбран
              </h2>
              <p class="mt-2 text-sm leading-6 text-stone-600">
                Заполните хотя бы один переплёт и отметьте его для ближайшей дуэли.
              </p>
            <% end %>

            <div
              :if={@action_feedback}
              id="spellbook-action-feedback"
              class={feedback_class(@action_feedback.kind)}
            >
              {@action_feedback.message}
            </div>
          </aside>
        </div>

        <section
          id="spell-library"
          class="rounded-[2rem] border border-stone-900/10 bg-white/85 p-5 shadow-lg sm:p-8"
        >
          <div class="flex flex-col gap-2 border-b border-stone-900/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">
                Личная библиотека
              </p>
              <h2 class="mt-2 font-serif text-2xl font-semibold text-stone-950">
                Известные заклинания
              </h2>
            </div>
            <span class="text-sm text-stone-500">{length(@spells)} записей</span>
          </div>

          <p
            :if={@spells == []}
            id="spell-library-empty-copy"
            class="mt-5 text-sm leading-6 text-stone-600"
          >
            В библиотеке ещё нет заклинаний, которые можно положить в переплёт.
          </p>

          <div :if={@spells != []} class="mt-5 grid gap-3 md:grid-cols-2">
            <article
              :for={spell <- @spells}
              id={"spell-library-#{spell.id}"}
              class="rounded-2xl border border-stone-200 bg-stone-50/80 p-4 transition hover:-translate-y-0.5 hover:border-amber-300"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <h3 class="font-serif text-lg font-semibold text-stone-950">{spell.name}</h3>
                  <p class="mt-1 text-sm text-stone-600">{spell.formula}</p>
                </div>
                <span class="rounded-full border border-amber-900/15 bg-amber-50 px-2.5 py-1 text-xs font-semibold text-amber-900">
                  {school_label(spell.school)}
                </span>
              </div>
              <p class="mt-3 text-sm leading-6 text-stone-600">
                {spell.description || "Устойчивое заклинание из вашей библиотеки."}
              </p>
            </article>
          </div>
        </section>

        <section
          id="grimoire-loadouts"
          class="rounded-[2rem] border border-stone-900/10 bg-white/85 p-5 shadow-lg sm:p-8"
        >
          <div class="flex flex-col gap-2 border-b border-stone-900/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">
                Носимые книги
              </p>
              <h2 class="mt-2 font-serif text-2xl font-semibold text-stone-950">
                Гримуары и нагрузка
              </h2>
            </div>
            <span class="text-sm text-stone-500">{length(@grimoires)} переплётов</span>
          </div>

          <div
            :if={@grimoires == []}
            id="grimoire-empty"
            class="mt-5 rounded-2xl border border-dashed border-stone-300 bg-stone-50 p-6"
          >
            <h3 class="font-serif text-xl font-semibold text-stone-950">Нет чистого переплёта</h3>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-stone-600">
              Активные и запечатанные книги нельзя переписывать. Новый физический гримуар покупается на рынке.
            </p>
          </div>

          <div :if={@grimoires != []} class="mt-5 grid gap-5 xl:grid-cols-2">
            <article
              :for={grimoire <- @grimoires}
              id={"grimoire-#{grimoire.id}"}
              class={[
                "rounded-2xl border p-5",
                active_grimoire?(grimoire, @active_grimoire) && "border-amber-400 bg-amber-50/70",
                not active_grimoire?(grimoire, @active_grimoire) && "border-stone-200 bg-stone-50/70"
              ]}
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                    {grimoire_status_label(grimoire.status)}
                  </p>
                  <h3 class="mt-1 font-serif text-xl font-semibold text-stone-950">
                    {grimoire.name}
                  </h3>
                  <p class="mt-1 text-sm text-stone-600">
                    {entry_count(grimoire)} / {grimoire.capacity} ячеек {"·"} {grimoire.weight} стоун
                  </p>
                </div>
                <span
                  :if={active_grimoire?(grimoire, @active_grimoire)}
                  class="rounded-full bg-amber-200 px-3 py-1 text-xs font-semibold text-amber-950"
                >
                  боевой
                </span>
              </div>

              <ol :if={grimoire_entries(grimoire) != []} class="mt-4 space-y-2">
                <li
                  :for={entry <- sorted_entries(grimoire)}
                  id={"grimoire-entry-#{entry.id}"}
                  class="flex items-center justify-between gap-3 rounded-xl border border-stone-200 bg-white/75 px-3 py-2 text-sm"
                >
                  <span class="min-w-0 truncate font-medium text-stone-800">
                    {entry_label(entry)}
                  </span>
                  <span class="shrink-0 text-xs text-stone-500">слот {entry.slot_index}</span>
                </li>
              </ol>

              <p
                :if={grimoire_entries(grimoire) == []}
                class="mt-4 rounded-xl border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-600"
              >
                В переплёте пока нет формул.
              </p>

              <.form
                :if={
                  writable_grimoire?(grimoire, @writable_grimoires) and
                    uninscribed_spells(grimoire, @spells) != []
                }
                for={@inscription_form}
                id={"grimoire-inscribe-form-#{grimoire.id}"}
                phx-submit="inscribe"
                class="mt-5 rounded-xl border border-amber-900/15 bg-amber-50/70 p-4"
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
                  prompt="Выберите заклинание"
                  required
                />
                <button
                  id={"grimoire-inscribe-#{grimoire.id}"}
                  type="submit"
                  class="inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-amber-900/30 bg-white px-4 py-2 text-sm font-semibold text-amber-950 transition hover:border-amber-700 hover:bg-amber-100"
                >
                  Записать выбранное заклинание
                </button>
              </.form>

              <p
                :if={
                  writable_grimoire?(grimoire, @writable_grimoires) and
                    uninscribed_spells(grimoire, @spells) == []
                }
                id={"grimoire-no-spells-#{grimoire.id}"}
                class="mt-5 text-sm leading-6 text-stone-600"
              >
                Все известные формулы уже записаны или библиотека пока пуста.
              </p>

              <p
                :if={not writable_grimoire?(grimoire, @writable_grimoires)}
                id={"grimoire-write-once-#{grimoire.id}"}
                class="mt-5 text-sm leading-6 text-stone-600"
              >
                Этот переплёт уже запечатан: его состав нельзя изменить.
              </p>

              <button
                :if={not active_grimoire?(grimoire, @active_grimoire)}
                id={"grimoire-activate-#{grimoire.id}"}
                type="button"
                phx-click="activate"
                phx-value-id={grimoire.id}
                class="mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-stone-900 px-4 py-2 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-stone-700"
              >
                Сделать боевым гримуаром
              </button>
            </article>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp reload_spellbook(socket) do
    case Play.spellbook_state(socket.assigns.current_scope.character) do
      {:ok, state} -> assign_spellbook_state(socket, state)
      {:error, reason} -> redirect_for_spellbook_error(socket, reason)
    end
  end

  defp assign_spellbook_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:spells, state.spells)
    |> assign(:grimoires, state.grimoires)
    |> assign(:active_grimoire, state.active_grimoire)
    |> assign(:permitted_schools, state.permitted_schools)
    |> assign(:composition_location, state.composition_location)
    |> assign(:writable_grimoires, Map.get(state, :writable_grimoires, []))
  end

  defp redirect_for_spellbook_error(socket, :travelling) do
    socket
    |> put_flash(:error, "Вы в пути. Дождитесь прибытия, чтобы открыть гримуар.")
    |> push_navigate(to: ~p"/travel")
  end

  defp redirect_for_spellbook_error(socket, :spellbook_location) do
    socket
    |> put_flash(:error, "Здесь магию не составить. Доберитесь до Башни или своей базы.")
    |> push_navigate(to: ~p"/map")
  end

  defp redirect_for_spellbook_error(socket, _reason) do
    socket
    |> put_flash(
      :error,
      "Не удалось открыть гримуар. Вернитесь к игровому входу и попробуйте снова."
    )
    |> push_navigate(to: ~p"/play")
  end

  defp reset_compose_form(socket), do: assign(socket, :compose_form, compose_form())

  defp compose_form(attrs \\ %{}) do
    to_form(
      %{
        "base_spell_id" => Map.get(attrs, "base_spell_id", ""),
        "school" => Map.get(attrs, "school", ""),
        "formula" => Map.get(attrs, "formula", "")
      },
      as: :composition
    )
  end

  defp inscription_form do
    to_form(%{"grimoire_id" => "", "spell_id" => ""}, as: :inscription)
  end

  defp compiled_spell(%{spell: spell}), do: spell
  defp compiled_spell(spell), do: spell

  defp spell_options(spells), do: Enum.map(spells, &{"#{&1.name} — #{&1.formula}", &1.id})

  defp school_options(schools), do: Enum.map(schools, &{school_label(&1), &1})

  defp school_label(school), do: Map.get(@school_labels, to_string(school), to_string(school))

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
  defp grimoire_status_label(status), do: to_string(status)

  defp feedback_class(:success),
    do:
      "mt-5 rounded-xl border border-emerald-900/20 bg-emerald-50 px-4 py-3 text-sm leading-6 text-emerald-900"

  defp feedback_class(:error),
    do:
      "mt-5 rounded-xl border border-[#7c2b22]/30 bg-[#7c2b22]/10 px-4 py-3 text-sm leading-6 text-[#5e1d16]"

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

  defp spellbook_error_message(:invalid_inscription),
    do: "Выберите свой переплёт и заклинание для записи."

  defp spellbook_error_message(:invalid_grimoire), do: "Выберите гримуар из своей библиотеки."
  defp spellbook_error_message(%Ecto.Changeset{}), do: generic_composition_error()
  defp spellbook_error_message(_reason), do: generic_composition_error()

  defp generic_composition_error do
    "Формула не сложилась. Проверьте основу, школу и от 1 до 6 латинских слов, затем попробуйте снова."
  end
end
