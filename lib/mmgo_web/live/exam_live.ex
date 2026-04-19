defmodule MMGOWeb.ExamLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy

  @exam_duration_seconds 300

  @impl true
  def mount(%{"term_id" => term_id}, _session, socket) do
    term = Academy.get_term!(term_id)
    started_at = DateTime.utc_now()
    expires_at = DateTime.add(started_at, @exam_duration_seconds, :second)

    if connected?(socket) do
      Process.send_after(self(), :tick, 1_000)
    end

    {:ok,
     socket
     |> assign(:page_title, "Exam — Term #{term.term_number}")
     |> assign(:term, term)
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
    score = grade_answers(socket.assigns.answers)

    case Academy.submit_exam(term.id, score) do
      {:ok, _updated_term} ->
        socket
        |> assign(:submitted, true)
        |> assign(:score, score)

      {:error, _changeset} ->
        put_flash(socket, :error, "Could not submit exam.")
    end
  end

  defp grade_answers(answers) do
    correct = %{
      "q1" => "b",
      "q2" => "a",
      "q3" => "c",
      "q4" => "b",
      "q5" => "d"
    }

    correct_count =
      Enum.count(correct, fn {q, expected} ->
        Map.get(answers, q) == expected
      end)

    round(correct_count / map_size(correct) * 100)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="exam-room">
      <h1>Term <%= @term.term_number %> Exam</h1>

      <%= if @submitted do %>
        <div class="exam-result">
          <h2>Exam submitted</h2>
          <p>Your score: <strong><%= @score %> / 100</strong></p>
          <.link navigate={~p"/academy/study-desk"}>Back to Study Desk</.link>
        </div>
      <% else %>
        <div class="exam-timer">
          Time remaining: <strong><%= @seconds_remaining %>s</strong>
        </div>

        <form phx-submit="submit">
          <fieldset>
            <legend>Question 1: What is the capital of the Realm?</legend>
            <label><input type="radio" name="q1" value="a" phx-click="answer" phx-value-question="q1" phx-value-answer="a" /> Ironhold</label>
            <label><input type="radio" name="q1" value="b" phx-click="answer" phx-value-question="q1" phx-value-answer="b" /> Ashgate</label>
            <label><input type="radio" name="q1" value="c" phx-click="answer" phx-value-question="q1" phx-value-answer="c" /> Emberveil</label>
          </fieldset>

          <fieldset>
            <legend>Question 2: Which element is associated with healing?</legend>
            <label><input type="radio" name="q2" value="a" phx-click="answer" phx-value-question="q2" phx-value-answer="a" /> Life</label>
            <label><input type="radio" name="q2" value="b" phx-click="answer" phx-value-question="q2" phx-value-answer="b" /> Fire</label>
            <label><input type="radio" name="q2" value="c" phx-click="answer" phx-value-question="q2" phx-value-answer="c" /> Chaos</label>
          </fieldset>

          <fieldset>
            <legend>Question 3: The Charity Fund is administered by which body?</legend>
            <label><input type="radio" name="q3" value="a" phx-click="answer" phx-value-question="q3" phx-value-answer="a" /> The Merchant Guild</label>
            <label><input type="radio" name="q3" value="b" phx-click="answer" phx-value-question="q3" phx-value-answer="b" /> The Dungeon Council</label>
            <label><input type="radio" name="q3" value="c" phx-click="answer" phx-value-question="q3" phx-value-answer="c" /> The Academy</label>
          </fieldset>

          <fieldset>
            <legend>Question 4: How many schools of magic exist?</legend>
            <label><input type="radio" name="q4" value="a" phx-click="answer" phx-value-question="q4" phx-value-answer="a" /> 6</label>
            <label><input type="radio" name="q4" value="b" phx-click="answer" phx-value-question="q4" phx-value-answer="b" /> 8</label>
            <label><input type="radio" name="q4" value="c" phx-click="answer" phx-value-question="q4" phx-value-answer="c" /> 12</label>
          </fieldset>

          <fieldset>
            <legend>Question 5: What triggers Expulsion from Basic Education?</legend>
            <label><input type="radio" name="q5" value="a" phx-click="answer" phx-value-question="q5" phx-value-answer="a" /> Missing 3 terms</label>
            <label><input type="radio" name="q5" value="b" phx-click="answer" phx-value-question="q5" phx-value-answer="b" /> Missing 5 terms</label>
            <label><input type="radio" name="q5" value="c" phx-click="answer" phx-value-question="q5" phx-value-answer="c" /> Missing 6 terms</label>
            <label><input type="radio" name="q5" value="d" phx-click="answer" phx-value-question="q5" phx-value-answer="d" /> Missing 7 or more terms</label>
          </fieldset>

          <button type="submit">Submit Exam</button>
        </form>
      <% end %>
    </div>
    """
  end
end
