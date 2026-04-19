defmodule MMGOWeb.StudyDeskLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns[:current_character]

    {enrollment, terms, gpa, failed_count} =
      if character do
        enrollment = Academy.current_enrollment(character.id)
        terms = if enrollment, do: Academy.list_terms_for_enrollment(enrollment.id), else: []
        gpa = if enrollment, do: Academy.gpa_for_enrollment(enrollment.id), else: nil
        failed = if enrollment, do: Academy.failed_terms_count(enrollment.id), else: 0
        {enrollment, terms, gpa, failed}
      else
        {nil, [], nil, 0}
      end

    {:ok,
     socket
     |> assign(:page_title, "Study Desk")
     |> assign(:character, character)
     |> assign(:enrollment, enrollment)
     |> assign(:terms, terms)
     |> assign(:gpa, gpa)
     |> assign(:failed_count, failed_count)}
  end

  @impl true
  def handle_event("begin_term", _params, socket) do
    enrollment = socket.assigns.enrollment

    case enrollment && Academy.begin_term(enrollment.id) do
      {:ok, _term} ->
        terms = Academy.list_terms_for_enrollment(enrollment.id)
        {:noreply, assign(socket, :terms, terms)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, error_message(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "No active enrollment.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="study-desk">
      <h1>Study Desk</h1>

      <%= if @enrollment do %>
        <section class="desk-enrollment">
          <h2>Current Enrollment</h2>
          <p>Program: <strong><%= @enrollment.program_type %></strong></p>
          <p>Track: <strong><%= @enrollment.track || "—" %></strong></p>
          <p>Status: <strong><%= @enrollment.status %></strong></p>
          <p>GPA: <strong><%= @gpa || "No exams yet" %></strong></p>
          <p>Failed terms: <strong><%= @failed_count %></strong></p>
          <p>Expected completion: <strong><%= Calendar.strftime(@enrollment.expected_completion_at, "%Y-%m-%d") %></strong></p>
        </section>

        <section class="desk-terms">
          <h2>Terms</h2>
          <table class="terms-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Status</th>
                <th>Exam Score</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              <%= for term <- @terms do %>
                <tr>
                  <td><%= term.term_number %></td>
                  <td><%= term.status %></td>
                  <td><%= term.exam_score || "—" %></td>
                  <td>
                    <%= if term.status == :active do %>
                      <.link navigate={~p"/academy/exam/#{term.id}"}>Take Exam</.link>
                    <% end %>
                  </td>
                </tr>
              <% end %>
              <%= if @terms == [] do %>
                <tr><td colspan="4">No terms started yet.</td></tr>
              <% end %>
            </tbody>
          </table>

          <%= if Academy.current_term(@enrollment.id) == nil do %>
            <button phx-click="begin_term">Begin Next Term</button>
          <% end %>
        </section>
      <% else %>
        <p>You are not currently enrolled. Visit the <.link navigate={~p"/academy/bulletin-board"}>Bulletin Board</.link> for enrollment info.</p>
      <% end %>
    </div>
    """
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end
end
