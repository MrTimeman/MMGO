defmodule MMGOWeb.LectureLive do
  @moduledoc """
  Scoped comprehension check for one real Academy lecture.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @impl true
  def mount(%{"term_id" => term_id}, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        case Play.academy_lecture_state(character, term_id) do
          {:ok, state} ->
            {:ok,
             socket
             |> assign(:page_title, "Лекция Академии")
             |> assign(:term_id, term_id)
             |> assign(:state, state)
             |> assign(:submitted, false)
             |> assign(:result, nil)
             |> assign(:error, nil)
             |> assign(:lecture_form, lecture_form(state))}

          {:error, _reason} ->
            {:ok,
             socket
             |> put_flash(:error, "Эта лекция больше не открыта для текущего термина.")
             |> push_navigate(to: ~p"/academy")}
        end
    end
  end

  @impl true
  def handle_event("submit", %{"lecture" => answers}, socket) do
    case Play.submit_scoped_academy_lecture(
           socket.assigns.current_scope.character,
           socket.assigns.term_id,
           answers
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:submitted, true)
         |> assign(:result, result)
         |> assign(:error, nil)}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Академия не приняла ответы: лекция уже изменилась или закрылась."
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-lecture-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="academy-lecture-back"
              navigate={~p"/academy"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← В Академию
            </.link>
            <span
              id="academy-lecture-progress"
              class="rounded border border-violet-300/35 bg-violet-950/25 px-3 py-2 text-sm text-violet-100"
            >
              Лекция {@state.lecture.number} из {@state.lectures_required}
            </span>
          </div>

          <header class="rounded-2xl border border-violet-400/25 bg-gradient-to-br from-violet-950/40 via-stone-950 to-sky-950/25 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.25em] text-violet-200/75">
              термин {@state.term.term_number} · аудитория Академии
            </p>
            <h1 class="mt-2 font-serif text-3xl text-violet-50">{@state.lecture.title}</h1>
            <p id="academy-lecture-body" class="mt-4 text-sm leading-7 text-stone-300">
              {@state.lecture.body}
            </p>
            <p class="mt-4 text-sm text-amber-100">
              После этой лекции потолок финальной оценки: {@state.current_final_ceiling}.
            </p>
          </header>

          <div
            :if={@error}
            id="academy-lecture-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <%= if @submitted do %>
            <section
              id="academy-lecture-result"
              class="rounded-2xl border border-emerald-400/25 bg-emerald-950/15 p-6 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">
                лекция внесена в ведомость
              </p>
              <h2 class="mt-2 font-serif text-3xl text-emerald-100">
                {@result.correct_answers} / {@result.question_count}
              </h2>
              <p class="mt-3 text-sm leading-6 text-stone-300">
                Академия начислила знания и подняла потолок финала до {@result.final_ceiling}. Следующая лекция или клубное окно уже отражены в вашей ведомости.
              </p>
              <.link
                id="academy-lecture-return"
                navigate={~p"/academy"}
                class="mt-5 inline-flex rounded-lg bg-emerald-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-emerald-200"
              >
                Вернуться к термину
              </.link>
            </section>
          <% else %>
            <.form
              for={@lecture_form}
              id="academy-lecture-form"
              phx-submit="submit"
              class="space-y-4 rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
            >
              <p class="text-sm text-stone-400">
                Короткая проверка фиксирует, что вы прочитали материал. Оценка не скрывает ответов и не принимает данные о персонаже из браузера.
              </p>
              <.input
                :for={question <- @state.lecture.questions}
                field={@lecture_form[question.key]}
                type="select"
                label={question.label}
                options={question.options}
              />
              <button
                id="academy-lecture-submit"
                type="submit"
                class="w-full rounded-lg bg-violet-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-violet-200"
              >
                Внести лекцию в ведомость
              </button>
            </.form>
          <% end %>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp lecture_form(state) do
    state.lecture.questions
    |> Map.new(&{&1.key, ""})
    |> to_form(as: :lecture)
  end
end
