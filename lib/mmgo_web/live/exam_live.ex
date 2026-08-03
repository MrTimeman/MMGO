defmodule MMGOWeb.ExamLive do
  @moduledoc """
  Server-scored midterm/final surface for the scoped active Academy term.
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
        case Play.start_current_academy_exam(character, term_id) do
          {:ok, state} ->
            seconds_remaining = seconds_remaining(state.deadline_at)

            if connected?(socket) and seconds_remaining > 0 do
              Process.send_after(self(), :tick, 1_000)
            end

            {:ok,
             socket
             |> assign(
               :page_title,
               "#{phase_label(state.phase)} · термин #{state.term.term_number}"
             )
             |> assign(:term, state.term)
             |> assign(:phase, state.phase)
             |> assign(:midterm_skippable?, state.midterm_skippable?)
             |> assign(:lecture_final_ceiling, state.progress.lecture_final_ceiling)
             |> assign(:questions, state.questions)
             |> assign(:exam_attempt_id, state.exam_attempt_id)
             |> assign(:expires_at, state.deadline_at)
             |> assign(:seconds_remaining, seconds_remaining)
             |> assign(:submitted, false)
             |> assign(:score, nil)
             |> assign(:error, nil)
             |> assign(:exam_form, to_form(empty_answers(state.questions), as: :exam))}

          {:error, _reason} ->
            {:ok,
             socket
             |> put_flash(:error, "Этот экзамен не открыт для вашего текущего термина.")
             |> push_navigate(to: ~p"/academy")}
        end
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    remaining = DateTime.diff(socket.assigns.expires_at, DateTime.utc_now(), :second)

    cond do
      socket.assigns.submitted ->
        {:noreply, socket}

      remaining > 0 ->
        Process.send_after(self(), :tick, 1_000)
        {:noreply, assign(socket, :seconds_remaining, remaining)}

      true ->
        {:noreply, expire_exam(socket)}
    end
  end

  @impl true
  def handle_event("submit", %{"exam" => answers}, socket) do
    {:noreply, submit_exam(socket, answers)}
  end

  @impl true
  def handle_event("skip_midterm", _params, socket) do
    case Play.skip_current_academy_midterm(
           socket.assigns.current_scope.character,
           socket.assigns.term.id
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Промежуточный экзамен пропущен: итоговый открыт с потолком 80 баллов."
         )
         |> push_navigate(to: ~p"/academy/exam/#{socket.assigns.term.id}")}

      {:error, _reason} ->
        {:noreply,
         assign(socket, :error, "Промежуточный экзамен уже нельзя пропустить в этом термине.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-exam-screen" class="acd-assessment acd-assessment--exam">
        <div class="acd-assessment__desk">
          <div class="acd-assessment__tools">
            <.link
              id="academy-exam-back"
              navigate={~p"/academy"}
              class="acd-assessment__exit"
            >
              ← покинуть аудиторию
            </.link>
            <span
              id="academy-exam-timer"
              class="acd-clock-seal"
            >
              <span>до сбора листов</span>
              <strong>{@seconds_remaining} с</strong>
            </span>
          </div>

          <header class="acd-exam-cover">
            <span class="acd-exam-cover__cord" aria-hidden="true"></span>
            <span class="acd-exam-cover__seal" aria-hidden="true">A</span>
            <p class="acd-assessment__kicker">
              термин {@term.term_number}
            </p>
            <h1>{phase_label(@phase)}</h1>
            <p class="acd-exam-cover__copy">
              Ответы оцениваются на сервере. Промежуточный экзамен открывает итоговый, а итоговый балл завершает термин и выставляет оценку записанным курсам.
            </p>
            <p id="academy-exam-lecture-ceiling" class="acd-exam-cover__note">
              Потолок финальной оценки от лекций: {@lecture_final_ceiling}.
            </p>
          </header>

          <div
            :if={@error}
            id="academy-exam-error"
            class="acd-red-ink"
          >
            {@error}
          </div>

          <%= if @submitted do %>
            <section
              id="academy-exam-result"
              class="acd-result-sheet"
            >
              <span class="acd-result-sheet__stamp" aria-hidden="true">✓</span>
              <p class="acd-result-sheet__kicker">
                ведомость сохранена
              </p>
              <h2>{@score} / 100</h2>
              <p class="acd-result-sheet__copy">
                {result_copy(@phase)}
              </p>
              <.link
                id="academy-exam-return"
                navigate={~p"/academy"}
                class="acd-result-sheet__return"
              >
                Закрыть ведомость
              </.link>
            </section>
          <% else %>
            <.form
              for={@exam_form}
              id="academy-exam-form"
              phx-submit="submit"
              class="acd-exam-folio"
            >
              <div class="acd-exam-folio__heading">
                <span>Экзаменационный лист</span>
                <small>отметьте по одному ответу в каждой строке</small>
              </div>
              <.input
                :for={question <- @questions}
                field={@exam_form[question.key]}
                type="select"
                label={question.label}
                options={question.options}
                class="acd-paper-control"
              />
              <button
                id="academy-exam-submit"
                type="submit"
                class="acd-quill-button"
              >
                Поставить подпись и сдать {String.downcase(phase_label(@phase))}
              </button>
            </.form>
            <button
              :if={@midterm_skippable?}
              id="academy-skip-midterm"
              type="button"
              phx-click="skip_midterm"
              class="acd-margin-note-button"
            >
              Пропустить промежуточный экзамен (потолок итогового: 80)
            </button>
          <% end %>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp submit_exam(socket, answers) do
    case Play.submit_current_academy_exam(
           socket.assigns.current_scope.character,
           socket.assigns.term.id,
           answers
         ) do
      {:ok, %{score: score}} ->
        socket
        |> assign(:submitted, true)
        |> assign(:score, score)
        |> assign(:error, nil)

      {:error, :academy_exam_expired} ->
        assign(socket, :error, "Время экзамена истекло. Результат ведомости уже фиксируется.")

      {:error, _reason} ->
        assign(socket, :error, "Академия не приняла ведомость. Обновите состояние термина.")
    end
  end

  defp expire_exam(socket) do
    case Play.expire_current_academy_exam(
           socket.assigns.current_scope.character,
           socket.assigns.term.id,
           socket.assigns.exam_attempt_id
         ) do
      {:ok, _state} ->
        socket
        |> put_flash(:error, "Время экзамена истекло; ведомость закрыта.")
        |> push_navigate(to: ~p"/academy")

      {:error, :exam_not_due} ->
        Process.send_after(self(), :tick, 250)
        assign(socket, :seconds_remaining, 0)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Время экзамена истекло. Академия обновляет ведомость.")
        |> push_navigate(to: ~p"/academy")
    end
  end

  defp seconds_remaining(%DateTime{} = expires_at),
    do: max(DateTime.diff(expires_at, DateTime.utc_now(), :second), 0)

  defp empty_answers(questions), do: Map.new(questions, &{&1.key, ""})
  defp phase_label(:midterm), do: "Промежуточный экзамен"
  defp phase_label(:final), do: "Итоговый экзамен"
  defp phase_label(_phase), do: "Экзамен"

  defp result_copy(:midterm),
    do: "Промежуточный экзамен завершён: теперь в ведомости открыт итоговый."

  defp result_copy(:final),
    do: "Итоговый экзамен завершён: балл термина и оценки курсов сохранены."

  defp result_copy(_phase), do: "Результат сохранён в ведомости."
end
