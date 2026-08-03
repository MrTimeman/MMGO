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
      <main id="academy-lecture-screen" class="acd-assessment acd-assessment--lecture">
        <div class="acd-assessment__desk">
          <div class="acd-assessment__tools">
            <.link
              id="academy-lecture-back"
              navigate={~p"/academy"}
              class="acd-assessment__exit"
            >
              ← покинуть аудиторию
            </.link>
            <span
              id="academy-lecture-progress"
              class="acd-lecture-ticket"
            >
              Лекция {@state.lecture.number} из {@state.lectures_required}
            </span>
          </div>

          <header class="acd-lecture-book">
            <span class="acd-lecture-book__spine" aria-hidden="true"></span>
            <span class="acd-lecture-book__bookmark" aria-hidden="true"></span>
            <p class="acd-assessment__kicker">
              термин {@state.term.term_number} · аудитория Академии
            </p>
            <h1>{@state.lecture.title}</h1>
            <p id="academy-lecture-body" class="acd-lecture-book__body">
              {@state.lecture.body}
            </p>
            <p class="acd-lecture-book__margin">
              После этой лекции потолок финальной оценки: {@state.current_final_ceiling}.
            </p>
          </header>

          <div
            :if={@error}
            id="academy-lecture-error"
            class="acd-red-ink"
          >
            {@error}
          </div>

          <%= if @submitted do %>
            <section
              id="academy-lecture-result"
              class="acd-result-sheet"
            >
              <span class="acd-result-sheet__stamp" aria-hidden="true">✓</span>
              <p class="acd-result-sheet__kicker">
                лекция внесена в ведомость
              </p>
              <h2>
                {@result.correct_answers} / {@result.question_count}
              </h2>
              <p class="acd-result-sheet__copy">
                Академия начислила знания и подняла потолок финала до {@result.final_ceiling}. Следующая лекция или клубное окно уже отражены в вашей ведомости.
              </p>
              <.link
                id="academy-lecture-return"
                navigate={~p"/academy"}
                class="acd-result-sheet__return"
              >
                Закрыть конспект
              </.link>
            </section>
          <% else %>
            <.form
              for={@lecture_form}
              id="academy-lecture-form"
              phx-submit="submit"
              class="acd-lecture-folio"
            >
              <p class="acd-lecture-folio__instruction">
                Короткая проверка фиксирует, что вы прочитали материал. Оценка не скрывает ответов и не принимает данные о персонаже из браузера.
              </p>
              <.input
                :for={question <- @state.lecture.questions}
                field={@lecture_form[question.key]}
                type="select"
                label={question.label}
                options={question.options}
                class="acd-paper-control"
              />
              <button
                id="academy-lecture-submit"
                type="submit"
                class="acd-quill-button acd-quill-button--lecture"
              >
                Подписать конспект и внести в ведомость
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
