defmodule MMGOWeb.ExamLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy

  @exam_duration_seconds 300

  @impl true
  def mount(%{"term_id" => term_id}, _session, socket) do
    term = Academy.get_term!(term_id)
    questions = build_questions(term)
    started_at = DateTime.utc_now()
    expires_at = DateTime.add(started_at, @exam_duration_seconds, :second)

    if connected?(socket) do
      Process.send_after(self(), :tick, 1_000)
    end

    {:ok,
     socket
     |> assign(:page_title, "Exam — Term #{term.term_number}")
     |> assign(:term, term)
     |> assign(:questions, questions)
     |> assign(:expires_at, expires_at)
     |> assign(:seconds_remaining, @exam_duration_seconds)
     |> assign(:submitted, false)
     |> assign(:score, nil)
     |> assign(:answers, %{})}
  end

  @impl true
  def handle_info(:tick, socket) do
    remaining = DateTime.diff(socket.assigns.expires_at, DateTime.utc_now(), :second)

    if remaining > 0 and not socket.assigns.submitted do
      Process.send_after(self(), :tick, 1_000)
      {:noreply, assign(socket, :seconds_remaining, remaining)}
    else
      if not socket.assigns.submitted do
        {:noreply, auto_submit(socket)}
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("answer", %{"question" => q, "answer" => a}, socket) do
    answers = Map.put(socket.assigns.answers, q, a)
    {:noreply, assign(socket, :answers, answers)}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    {:noreply, auto_submit(socket)}
  end

  defp auto_submit(socket) do
    term = socket.assigns.term
    score = grade_answers(socket.assigns.questions, socket.assigns.answers)

    case Academy.submit_exam(term.id, score) do
      {:ok, _updated_term} ->
        socket
        |> assign(:submitted, true)
        |> assign(:score, score)

      {:error, _changeset} ->
        put_flash(socket, :error, "Could not submit exam.")
    end
  end

  defp grade_answers(questions, answers) do
    correct_count =
      Enum.count(questions, fn question ->
        Map.get(answers, question.id) == question.correct
      end)

    round(correct_count / max(length(questions), 1) * 100)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl space-y-6">
        <section class="overflow-hidden rounded-[2rem] border border-stone-200 bg-[radial-gradient(circle_at_top,_rgba(251,191,36,0.18),_transparent_24rem),linear-gradient(180deg,_#fffaf2,_#f6efe1)] p-6 shadow-[0_24px_70px_rgba(120,93,46,0.08)] sm:p-8">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.34em] text-amber-700">
                Final Assessment
              </p>
              <h1 class="font-['Cormorant_Garamond'] text-5xl font-semibold text-stone-950 sm:text-6xl">
                Term {@term.term_number} Exam
              </h1>
              <p class="max-w-2xl text-sm leading-6 text-stone-600 sm:text-base">
                This exam now draws from the term itself: lecture attendance, office hours, phase rhythm, and midterm preparation.
              </p>
            </div>

            <div
              id="exam-timer"
              class="rounded-[1.25rem] border border-stone-200 bg-white px-5 py-4 text-right shadow-[0_10px_30px_rgba(15,23,42,0.05)]"
            >
              <p class="text-[11px] font-semibold uppercase tracking-[0.24em] text-stone-500">
                Time Remaining
              </p>
              <p class="mt-2 text-2xl font-semibold text-stone-950">
                {format_timer(@seconds_remaining)}
              </p>
            </div>
          </div>
        </section>

        <%= if @submitted do %>
          <section class="rounded-[1.75rem] border border-emerald-200 bg-emerald-50 p-8 text-center shadow-[0_18px_55px_rgba(16,185,129,0.08)]">
            <h2 class="text-3xl font-semibold text-emerald-950">Exam submitted</h2>
            <p class="mt-3 text-sm leading-6 text-emerald-900">
              Final score: <strong>{@score} / 100</strong>
            </p>
            <.link
              id="exam-back-study-desk"
              navigate={~p"/academy/study-desk"}
              class="mt-6 inline-flex rounded-full border border-emerald-900 bg-emerald-900 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-emerald-950"
            >
              Back to study desk
            </.link>
          </section>
        <% else %>
          <div class="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,0.75fr)]">
            <section class="space-y-4">
              <form id="exam-form" phx-submit="submit" class="space-y-4">
                <%= for question <- @questions do %>
                  <fieldset
                    id={"exam-question-#{question.id}"}
                    class="rounded-[1.6rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.05)]"
                  >
                    <legend class="text-lg font-semibold text-stone-950">
                      {question.prompt}
                    </legend>
                    <div class="mt-4 grid gap-3">
                      <label
                        :for={option <- question.options}
                        class="flex cursor-pointer items-start gap-3 rounded-[1rem] border border-stone-200 bg-stone-50 px-4 py-4 text-sm leading-6 text-stone-700 transition hover:border-amber-300 hover:bg-amber-50"
                      >
                        <input
                          id={"#{question.id}-#{option.id}"}
                          type="radio"
                          name={question.id}
                          value={option.id}
                          checked={Map.get(@answers, question.id) == option.id}
                          phx-click="answer"
                          phx-value-question={question.id}
                          phx-value-answer={option.id}
                          class="mt-1 size-4 border-stone-300 text-amber-600 focus:ring-amber-500"
                        />
                        <span>{option.label}</span>
                      </label>
                    </div>
                  </fieldset>
                <% end %>

                <button
                  id="exam-submit"
                  type="submit"
                  class="w-full rounded-[1.35rem] border border-stone-900 bg-stone-900 px-5 py-4 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-black"
                >
                  Submit exam
                </button>
              </form>
            </section>

            <aside class="space-y-4">
              <div class="rounded-[1.6rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.05)]">
                <p class="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
                  Term Context
                </p>
                <dl class="mt-4 space-y-4 text-sm text-stone-600">
                  <.context_row label="Current phase" value={format_phase(Academy.term_phase(@term))} />
                  <.context_row
                    label="Exam ceiling"
                    value={Integer.to_string(Academy.exam_score_ceiling(@term))}
                  />
                  <.context_row
                    label="Lectures attended"
                    value={Integer.to_string(length(@term.metadata["lectures"] || []))}
                  />
                  <.context_row
                    label="Office hours"
                    value={
                      if(is_map(@term.metadata["office_hours"]), do: "Attended", else: "Not attended")
                    }
                  />
                  <.context_row
                    label="Midterm"
                    value={format_midterm(get_in(@term.metadata, ["midterm", "score"]))}
                  />
                </dl>
              </div>

              <div class="rounded-[1.6rem] border border-amber-200 bg-amber-50 p-6 text-sm leading-6 text-amber-950 shadow-[0_18px_55px_rgba(245,158,11,0.08)]">
                The final score is still capped by the term ceiling. Strong preparation matters even when every answer is correct.
              </div>
            </aside>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp context_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 border-b border-stone-100 pb-3 last:border-b-0 last:pb-0">
      <dt class="text-stone-500">{@label}</dt>
      <dd class="text-right font-semibold text-stone-950">{@value}</dd>
    </div>
    """
  end

  defp build_questions(term) do
    metadata = term.metadata || %{}
    lecture_count = length(metadata["lectures"] || [])

    lecture_title =
      metadata["lectures"] |> List.last() |> then(&((&1 || %{})["title"] || "No lecture"))

    office_hours? = is_map(metadata["office_hours"])
    midterm_score = get_in(metadata, ["midterm", "score"])
    exam_ceiling = Academy.exam_score_ceiling(term)

    [
      %{
        id: "phase",
        prompt: "Which phase directly precedes the term break?",
        correct: "midterm",
        options:
          option_set([
            {"lecture_phase", "Lecture phase"},
            {"club_window", "Club window"},
            {"midterm", "Midterm"},
            {"enrollment_window", "Enrollment window"}
          ])
      },
      %{
        id: "lecture",
        prompt: "Which lecture was most recently recorded for this term?",
        correct: "latest",
        options:
          option_set([
            {"latest", lecture_title},
            {"clinic", "Office-hour clinic"},
            {"archives", "Archive review"},
            {"none", "No lecture was recorded"}
          ])
      },
      %{
        id: "ceiling",
        prompt: "What is the current exam score ceiling for this term?",
        correct: "exact",
        options:
          option_set([
            {"exact", Integer.to_string(exam_ceiling)},
            {"minus", Integer.to_string(max(exam_ceiling - 5, 0))},
            {"plus", Integer.to_string(min(exam_ceiling + 5, 100))},
            {"base", "70"}
          ])
      },
      %{
        id: "office_hours",
        prompt: "Have office hours already been attended for this term?",
        correct: if(office_hours?, do: "yes", else: "no"),
        options:
          option_set([
            {"yes", "Yes"},
            {"no", "No"},
            {"pending", "Scheduled but not attended"},
            {"unknown", "Unknown"}
          ])
      },
      %{
        id: "midterm",
        prompt: "What midterm outcome is recorded for this term?",
        correct: "actual",
        options:
          option_set([
            {"actual",
             if(is_integer(midterm_score),
               do: Integer.to_string(midterm_score),
               else: "No midterm recorded"
             )},
            {"lecture_count", "#{lecture_count} lectures"},
            {"ceiling", "Ceiling only, no score"},
            {"repeat", "Repeat term required"}
          ])
      }
    ]
  end

  defp option_set(options) do
    Enum.map(options, fn {id, label} -> %{id: id, label: label} end)
  end

  defp format_timer(seconds_remaining) do
    minutes = div(max(seconds_remaining, 0), 60)
    seconds = rem(max(seconds_remaining, 0), 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, seconds]) |> IO.iodata_to_binary()
  end

  defp format_phase(phase) when is_atom(phase),
    do: phase |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_phase(phase), do: to_string(phase)

  defp format_midterm(nil), do: "Not recorded"
  defp format_midterm(score), do: Integer.to_string(score)
end
