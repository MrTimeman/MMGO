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
         |> put_flash(:info, "Мидтерм пропущен: финал открыт с потолком 80 баллов.")
         |> push_navigate(to: ~p"/academy/exam/#{socket.assigns.term.id}")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Мидтерм уже нельзя пропустить для этого термина.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-exam-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="academy-exam-back"
              navigate={~p"/academy"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← В Академию
            </.link>
            <span
              id="academy-exam-timer"
              class="rounded border border-amber-300/40 bg-amber-950/25 px-3 py-2 text-sm text-amber-100"
            >
              Осталось: {@seconds_remaining} с
            </span>
          </div>

          <header class="rounded-2xl border border-amber-400/25 bg-gradient-to-br from-amber-950/35 via-stone-950 to-stone-900 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.25em] text-amber-200/75">
              термин {@term.term_number}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-amber-100">{phase_label(@phase)}</h1>
            <p class="mt-3 text-sm leading-6 text-stone-300">
              Ответы оцениваются на сервере. Мидтерм открывает финал, а итоговый балл завершает термин и выставляет оценку записанным курсам.
            </p>
            <p id="academy-exam-lecture-ceiling" class="mt-3 text-sm text-amber-100">
              Потолок финальной оценки от лекций: {@lecture_final_ceiling}.
            </p>
          </header>

          <div
            :if={@error}
            id="academy-exam-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <%= if @submitted do %>
            <section
              id="academy-exam-result"
              class="rounded-2xl border border-emerald-400/25 bg-emerald-950/15 p-6 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">
                ведомость сохранена
              </p>
              <h2 class="mt-2 font-serif text-3xl text-emerald-100">{@score} / 100</h2>
              <p class="mt-3 text-sm leading-6 text-stone-300">
                {result_copy(@phase)}
              </p>
              <.link
                id="academy-exam-return"
                navigate={~p"/academy"}
                class="mt-5 inline-flex rounded-lg bg-emerald-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-emerald-200"
              >
                Вернуться к ведомости
              </.link>
            </section>
          <% else %>
            <.form
              for={@exam_form}
              id="academy-exam-form"
              phx-submit="submit"
              class="space-y-4 rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
            >
              <.input
                :for={question <- @questions}
                field={@exam_form[question.key]}
                type="select"
                label={question.label}
                options={question.options}
              />
              <button
                id="academy-exam-submit"
                type="submit"
                class="w-full rounded-lg bg-amber-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-200"
              >
                Сдать {String.downcase(phase_label(@phase))}
              </button>
            </.form>
            <button
              :if={@midterm_skippable?}
              id="academy-skip-midterm"
              type="button"
              phx-click="skip_midterm"
              class="w-full rounded-lg border border-stone-600 px-4 py-3 text-sm text-stone-200 transition hover:border-amber-300/50"
            >
              Пропустить мидтерм (потолок финала: 80)
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
  defp phase_label(:midterm), do: "Мидтерм"
  defp phase_label(:final), do: "Финал"
  defp phase_label(_phase), do: "Экзамен"
  defp result_copy(:midterm), do: "Мидтерм завершён: теперь в ведомости открыт финал."
  defp result_copy(:final), do: "Финал завершён: итоговый балл термина и оценки курсов сохранены."
  defp result_copy(_phase), do: "Результат сохранён в ведомости."
end
