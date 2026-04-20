defmodule MMGOWeb.StudyDeskLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Study Desk")
     |> assign(:character, socket.assigns[:current_character])
     |> load_academy_state()}
  end

  @impl true
  def handle_event("begin_term", _params, socket) do
    enrollment = socket.assigns.enrollment

    case enrollment && Academy.begin_term(enrollment.id) do
      {:ok, _term} ->
        {:noreply, socket |> load_academy_state() |> put_flash(:info, "A new term has begun.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, error_message(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "No active enrollment.")}
    end
  end

  @impl true
  def handle_event("advance_phase", _params, socket) do
    case socket.assigns.current_term do
      nil ->
        {:noreply, put_flash(socket, :error, "No active term.")}

      term ->
        case Academy.advance_term_phase(term.id) do
          {:ok, _updated_term} ->
            {:noreply, socket |> load_academy_state() |> put_flash(:info, "Term phase advanced.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, error_message(changeset))}
        end
    end
  end

  @impl true
  def handle_event("attend_lecture", _params, socket) do
    case socket.assigns.current_term do
      nil ->
        {:noreply, put_flash(socket, :error, "No active term.")}

      term ->
        lecture_number = socket.assigns.term_summary.lecture_count + 1

        case Academy.record_lecture_attendance(term.id, %{
               title: "Applied Theory #{lecture_number}",
               comprehension_score: 82 + rem(lecture_number * 7, 13)
             }) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> load_academy_state()
             |> put_flash(:info, "Lecture recorded and knowledge XP awarded.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, error_message(changeset))}
        end
    end
  end

  @impl true
  def handle_event("attend_office_hours", _params, socket) do
    case socket.assigns.current_term do
      nil ->
        {:noreply, put_flash(socket, :error, "No active term.")}

      term ->
        case Academy.attend_office_hours(term.id) do
          {:ok, _updated_term} ->
            {:noreply,
             socket
             |> load_academy_state()
             |> put_flash(:info, "Office hours attended. Exam ceiling increased.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, error_message(changeset))}
        end
    end
  end

  @impl true
  def handle_event("submit_midterm", _params, socket) do
    case socket.assigns.current_term do
      nil ->
        {:noreply, put_flash(socket, :error, "No active term.")}

      term ->
        score = min(72 + socket.assigns.term_summary.lecture_count * 6, 96)

        case Academy.submit_midterm(term.id, score) do
          {:ok, _updated_term} ->
            {:noreply,
             socket
             |> load_academy_state()
             |> put_flash(:info, "Midterm submitted with score #{score}.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, error_message(changeset))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl space-y-6">
        <section class="overflow-hidden rounded-[2rem] border border-stone-200 bg-[radial-gradient(circle_at_top,_rgba(251,191,36,0.18),_transparent_24rem),linear-gradient(180deg,_#fffaf2,_#f6efe1)] p-6 shadow-[0_24px_70px_rgba(120,93,46,0.08)] sm:p-8">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
            <div class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.34em] text-amber-700">
                Academy Workflow
              </p>
              <h1 class="font-['Cormorant_Garamond'] text-5xl font-semibold text-stone-950 sm:text-6xl">
                Study Desk
              </h1>
              <p class="max-w-2xl text-sm leading-6 text-stone-600 sm:text-base">
                Run the full term rhythm from one surface: phase pacing, lectures, office hours,
                midterm preparation, and the final exam gate.
              </p>
            </div>

            <%= if @enrollment do %>
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <.metric_card
                  id="desk-metric-program"
                  label="Program"
                  value={format_program(@enrollment.program_type)}
                />
                <.metric_card
                  id="desk-metric-track"
                  label="Track"
                  value={format_track(@enrollment.track)}
                />
                <.metric_card id="desk-metric-gpa" label="GPA" value={format_gpa(@gpa)} />
                <.metric_card
                  id="desk-metric-failed"
                  label="Failed Terms"
                  value={Integer.to_string(@failed_count)}
                />
              </div>
            <% end %>
          </div>
        </section>

        <%= if @enrollment do %>
          <div class="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
            <section class="space-y-6">
              <div class="rounded-[1.75rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.06)]">
                <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
                      Current Enrollment
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-stone-950">Academic status</h2>
                  </div>

                  <%= if is_nil(@current_term) do %>
                    <button
                      id="study-desk-begin-term"
                      type="button"
                      phx-click="begin_term"
                      class="rounded-full border border-stone-900 bg-stone-900 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-black"
                    >
                      Begin next term
                    </button>
                  <% else %>
                    <.link
                      id="study-desk-open-exam"
                      navigate={~p"/academy/exam/#{@current_term.id}"}
                      class="rounded-full border border-amber-300 bg-amber-100 px-5 py-3 text-sm font-semibold text-amber-950 transition hover:-translate-y-0.5 hover:border-amber-500"
                    >
                      Open final exam
                    </.link>
                  <% end %>
                </div>

                <dl class="mt-6 grid gap-4 sm:grid-cols-2">
                  <.detail_row label="Status" value={format_status(@enrollment.status)} />
                  <.detail_row
                    label="Expected completion"
                    value={Calendar.strftime(@enrollment.expected_completion_at, "%Y-%m-%d")}
                  />
                  <.detail_row label="Funding" value={format_funding(@enrollment.funding_type)} />
                  <.detail_row
                    label="Hall of fame"
                    value={if(@enrollment.metadata["hall_of_fame"], do: "Yes", else: "No")}
                  />
                </dl>
              </div>

              <div class="rounded-[1.75rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.06)]">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
                      Active Term
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-stone-950">
                      {term_heading(@current_term)}
                    </h2>
                  </div>
                  <%= if @current_term do %>
                    <span
                      id="study-desk-phase-badge"
                      class="rounded-full border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-900"
                    >
                      {format_phase(@term_summary.phase)}
                    </span>
                  <% end %>
                </div>

                <%= if @current_term do %>
                  <div class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <.metric_card
                      id="study-desk-ceiling"
                      label="Exam Ceiling"
                      value={Integer.to_string(@term_summary.exam_ceiling)}
                    />
                    <.metric_card
                      id="study-desk-lectures"
                      label="Lectures"
                      value={Integer.to_string(@term_summary.lecture_count)}
                    />
                    <.metric_card
                      id="study-desk-office-hours"
                      label="Office Hours"
                      value={if(@term_summary.office_hours?, do: "Done", else: "Open")}
                    />
                    <.metric_card
                      id="study-desk-midterm"
                      label="Midterm"
                      value={format_midterm(@term_summary.midterm_score)}
                    />
                  </div>

                  <div class="mt-6 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                    <button
                      id="study-desk-advance-phase"
                      type="button"
                      phx-click="advance_phase"
                      class="rounded-[1.25rem] border border-stone-300 bg-stone-50 px-4 py-4 text-left text-sm font-semibold text-stone-900 transition hover:-translate-y-0.5 hover:border-stone-900"
                    >
                      Advance phase
                    </button>
                    <button
                      id="study-desk-attend-lecture"
                      type="button"
                      phx-click="attend_lecture"
                      class="rounded-[1.25rem] border border-sky-200 bg-sky-50 px-4 py-4 text-left text-sm font-semibold text-sky-950 transition hover:-translate-y-0.5 hover:border-sky-500"
                    >
                      Attend lecture
                    </button>
                    <button
                      id="study-desk-office-hours-button"
                      type="button"
                      phx-click="attend_office_hours"
                      class="rounded-[1.25rem] border border-violet-200 bg-violet-50 px-4 py-4 text-left text-sm font-semibold text-violet-950 transition hover:-translate-y-0.5 hover:border-violet-500"
                    >
                      Attend office hours
                    </button>
                    <button
                      id="study-desk-submit-midterm"
                      type="button"
                      phx-click="submit_midterm"
                      class="rounded-[1.25rem] border border-amber-200 bg-amber-50 px-4 py-4 text-left text-sm font-semibold text-amber-950 transition hover:-translate-y-0.5 hover:border-amber-500"
                    >
                      Submit midterm
                    </button>
                  </div>

                  <div class="mt-6 rounded-[1.4rem] border border-stone-200 bg-stone-50 p-5">
                    <p class="text-sm font-semibold uppercase tracking-[0.24em] text-stone-500">
                      Term Notes
                    </p>
                    <ul class="mt-4 space-y-3 text-sm leading-6 text-stone-600">
                      <li id="study-desk-note-phase">
                        Current phase:
                        <strong class="text-stone-900">{format_phase(@term_summary.phase)}</strong>
                      </li>
                      <li id="study-desk-note-ceiling">
                        Exam ceiling:
                        <strong class="text-stone-900">{@term_summary.exam_ceiling}</strong>
                        via lecture, midterm, and office-hour boosts.
                      </li>
                      <li id="study-desk-note-midterm">
                        Midterm status:
                        <strong class="text-stone-900">
                          {format_midterm(@term_summary.midterm_score)}
                        </strong>
                      </li>
                    </ul>
                  </div>
                <% else %>
                  <div class="mt-6 rounded-[1.4rem] border border-dashed border-stone-300 bg-stone-50 p-6 text-sm leading-6 text-stone-600">
                    No term is active. Start the next term to open the lecture, office-hour, and midterm loop.
                  </div>
                <% end %>
              </div>

              <div class="rounded-[1.75rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.06)]">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
                      Record
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-stone-950">Terms</h2>
                  </div>
                  <.link
                    navigate={~p"/academy/bulletin-board"}
                    class="text-sm font-semibold text-stone-600 underline decoration-stone-300 underline-offset-4 transition hover:text-stone-950"
                  >
                    Bulletin board
                  </.link>
                </div>

                <div class="mt-6 overflow-hidden rounded-[1.2rem] border border-stone-200">
                  <table class="min-w-full divide-y divide-stone-200 text-left text-sm">
                    <thead class="bg-stone-50 text-stone-500">
                      <tr>
                        <th class="px-4 py-3 font-semibold">#</th>
                        <th class="px-4 py-3 font-semibold">Status</th>
                        <th class="px-4 py-3 font-semibold">Phase</th>
                        <th class="px-4 py-3 font-semibold">Score</th>
                        <th class="px-4 py-3 font-semibold">Exam</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-stone-200 bg-white">
                      <%= for term <- @terms do %>
                        <tr id={"study-desk-term-#{term.term_number}"} class="text-stone-700">
                          <td class="px-4 py-3 font-semibold text-stone-950">{term.term_number}</td>
                          <td class="px-4 py-3">{format_status(term.status)}</td>
                          <td class="px-4 py-3">{format_phase(Academy.term_phase(term))}</td>
                          <td class="px-4 py-3">{term.exam_score || "—"}</td>
                          <td class="px-4 py-3">
                            <%= if term.status == :active do %>
                              <.link
                                navigate={~p"/academy/exam/#{term.id}"}
                                class="font-semibold text-amber-800 underline decoration-amber-300 underline-offset-4"
                              >
                                Take exam
                              </.link>
                            <% else %>
                              —
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </section>

            <aside class="space-y-6">
              <div class="rounded-[1.75rem] border border-stone-200 bg-white p-6 shadow-[0_18px_55px_rgba(15,23,42,0.06)]">
                <p class="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
                  Honors
                </p>
                <h2 class="mt-2 text-2xl font-semibold text-stone-950">Completion standing</h2>
                <dl class="mt-5 space-y-4 text-sm text-stone-600">
                  <.detail_row
                    label="Scholarship eligible"
                    value={
                      if(@enrollment.metadata["merit_scholarship_eligible"], do: "Yes", else: "No")
                    }
                  />
                  <.detail_row
                    label="Outcome tier"
                    value={format_tier(@enrollment.metadata["outcome_tier"])}
                  />
                  <.detail_row
                    label="Percentile"
                    value={format_percentile(@enrollment.metadata["rank_percentile"])}
                  />
                </dl>
              </div>
            </aside>
          </div>
        <% else %>
          <section class="rounded-[1.75rem] border border-dashed border-stone-300 bg-white p-8 text-center shadow-[0_18px_55px_rgba(15,23,42,0.05)]">
            <h2 class="text-2xl font-semibold text-stone-950">No active enrollment</h2>
            <p class="mx-auto mt-3 max-w-xl text-sm leading-6 text-stone-600">
              Visit the bulletin board to inspect courses, club events, and the current academy cohort.
            </p>
            <.link
              id="study-desk-bulletin-link"
              navigate={~p"/academy/bulletin-board"}
              class="mt-6 inline-flex rounded-full border border-stone-900 bg-stone-900 px-5 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-black"
            >
              Open bulletin board
            </.link>
          </section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-[1.2rem] border border-stone-200 bg-stone-50 px-4 py-4">
      <p class="text-[11px] font-semibold uppercase tracking-[0.24em] text-stone-500">{@label}</p>
      <p class="mt-2 text-lg font-semibold text-stone-950">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 border-b border-stone-100 pb-3 last:border-b-0 last:pb-0">
      <dt class="text-stone-500">{@label}</dt>
      <dd class="text-right font-semibold text-stone-950">{@value}</dd>
    </div>
    """
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp load_academy_state(socket) do
    character = socket.assigns.character
    enrollment = character && Academy.current_enrollment(character.id)
    terms = if enrollment, do: Academy.list_terms_for_enrollment(enrollment.id), else: []
    gpa = if enrollment, do: Academy.gpa_for_enrollment(enrollment.id), else: nil
    failed_count = if enrollment, do: Academy.failed_terms_count(enrollment.id), else: 0
    current_term = if enrollment, do: Academy.current_term(enrollment.id), else: nil

    assign(socket,
      enrollment: enrollment,
      terms: terms,
      gpa: gpa,
      failed_count: failed_count,
      current_term: current_term,
      term_summary: term_summary(current_term)
    )
  end

  defp term_summary(nil) do
    %{
      phase: :enrollment_window,
      exam_ceiling: 70,
      lecture_count: 0,
      office_hours?: false,
      midterm_score: nil
    }
  end

  defp term_summary(term) do
    metadata = term.metadata || %{}

    %{
      phase: Academy.term_phase(term),
      exam_ceiling: Academy.exam_score_ceiling(term),
      lecture_count: length(metadata["lectures"] || []),
      office_hours?: is_map(metadata["office_hours"]),
      midterm_score: get_in(metadata, ["midterm", "score"])
    }
  end

  defp term_heading(nil), do: "No active term"
  defp term_heading(term), do: "Term #{term.term_number}"

  defp format_program(program_type) when is_atom(program_type) do
    program_type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_program(program_type), do: to_string(program_type || "—")

  defp format_track(nil), do: "—"

  defp format_track(track) when is_atom(track),
    do: track |> Atom.to_string() |> String.capitalize()

  defp format_track(track), do: to_string(track)

  defp format_gpa(nil), do: "No exams yet"
  defp format_gpa(gpa), do: :erlang.float_to_binary(gpa, decimals: 2)

  defp format_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_status(status), do: to_string(status)

  defp format_phase(phase) when is_atom(phase),
    do: phase |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_phase(phase), do: to_string(phase)

  defp format_midterm(nil), do: "Not taken"
  defp format_midterm(score), do: Integer.to_string(score)

  defp format_funding(funding_type) when is_atom(funding_type),
    do: funding_type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_funding(funding_type), do: to_string(funding_type || "—")

  defp format_tier(nil), do: "—"
  defp format_tier(tier) when is_atom(tier), do: tier |> Atom.to_string() |> String.capitalize()
  defp format_tier(tier), do: to_string(tier)

  defp format_percentile(nil), do: "—"
  defp format_percentile(percentile), do: "#{Float.round(percentile, 1)}%"
end
