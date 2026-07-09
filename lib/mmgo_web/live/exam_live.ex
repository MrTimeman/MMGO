defmodule MMGOWeb.ExamLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGO.Accounts
  alias MMGOWeb.LocationGate

  @exam_duration_seconds 300

  @impl true
  def mount(%{"term_id" => term_id}, session, socket) do
    character = socket.assigns[:current_character] || load_character(session)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :city) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          term = Academy.get_term!(term_id)
          started_at = DateTime.utc_now()
          expires_at = DateTime.add(started_at, @exam_duration_seconds, :second)

          if connected?(socket) do
            Process.send_after(self(), :tick, 1_000)
          end

          {:ok,
           socket
           |> assign(:page_title, "Exam — Term #{term.term_number}")
           |> assign(:character, character)
           |> assign(:term, term)
           |> assign(:expires_at, expires_at)
           |> assign(:seconds_remaining, @exam_duration_seconds)
           |> assign(:submitted, false)
           |> assign(:score, nil)
           |> assign(:answers, %{})}
      end
    end
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

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    Accounts.get_character!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

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
      <a href={~p"/academy/study-desk"} class="map-back-link">← К учебному столу</a>
      <h1>Экзамен термина {@term.term_number}</h1>

      <%= if @submitted do %>
        <div class="exam-result">
          <h2>Ведомость закрыта</h2>
          <p>Ваш результат: <strong>{@score} / 100</strong></p>
          <p>Секретарь уносит лист к кафедре. Средний балл пересчитают после проверки.</p>
          <.link navigate={~p"/academy/study-desk"}>Вернуться к столу</.link>
        </div>
      <% else %>
        <div class="exam-timer">
          Осталось времени: <strong>{@seconds_remaining} с</strong>
        </div>

        <form phx-submit="submit">
          <fieldset>
            <legend>Вопрос 1. Как зовётся столица княжества?</legend>
            <label>
              <input
                type="radio"
                name="q1"
                value="a"
                phx-click="answer"
                phx-value-question="q1"
                phx-value-answer="a"
              /> Железная Крепь
            </label>
            <label>
              <input
                type="radio"
                name="q1"
                value="b"
                phx-click="answer"
                phx-value-question="q1"
                phx-value-answer="b"
              /> Врата Зари
            </label>
            <label>
              <input
                type="radio"
                name="q1"
                value="c"
                phx-click="answer"
                phx-value-question="q1"
                phx-value-answer="c"
              /> Пепельная Завеса
            </label>
          </fieldset>

          <fieldset>
            <legend>Вопрос 2. Какая школа связана с исцелением?</legend>
            <label>
              <input
                type="radio"
                name="q2"
                value="a"
                phx-click="answer"
                phx-value-question="q2"
                phx-value-answer="a"
              /> Жизнь
            </label>
            <label>
              <input
                type="radio"
                name="q2"
                value="b"
                phx-click="answer"
                phx-value-question="q2"
                phx-value-answer="b"
              /> Огонь
            </label>
            <label>
              <input
                type="radio"
                name="q2"
                value="c"
                phx-click="answer"
                phx-value-question="q2"
                phx-value-answer="c"
              /> Хаос
            </label>
          </fieldset>

          <fieldset>
            <legend>Вопрос 3. Кто ведает Фондом Просвещения?</legend>
            <label>
              <input
                type="radio"
                name="q3"
                value="a"
                phx-click="answer"
                phx-value-question="q3"
                phx-value-answer="a"
              /> Торговая гильдия
            </label>
            <label>
              <input
                type="radio"
                name="q3"
                value="b"
                phx-click="answer"
                phx-value-question="q3"
                phx-value-answer="b"
              /> Совет Подземелья
            </label>
            <label>
              <input
                type="radio"
                name="q3"
                value="c"
                phx-click="answer"
                phx-value-question="q3"
                phx-value-answer="c"
              /> Академия
            </label>
          </fieldset>

          <fieldset>
            <legend>Вопрос 4. Сколько школ магии признаёт Академия?</legend>
            <label>
              <input
                type="radio"
                name="q4"
                value="a"
                phx-click="answer"
                phx-value-question="q4"
                phx-value-answer="a"
              /> 6
            </label>
            <label>
              <input
                type="radio"
                name="q4"
                value="b"
                phx-click="answer"
                phx-value-question="q4"
                phx-value-answer="b"
              /> 8
            </label>
            <label>
              <input
                type="radio"
                name="q4"
                value="c"
                phx-click="answer"
                phx-value-question="q4"
                phx-value-answer="c"
              /> 12
            </label>
          </fieldset>

          <fieldset>
            <legend>Вопрос 5. Что ведёт к отчислению с базового образования?</legend>
            <label>
              <input
                type="radio"
                name="q5"
                value="a"
                phx-click="answer"
                phx-value-question="q5"
                phx-value-answer="a"
              /> Пропуск 3 терминов
            </label>
            <label>
              <input
                type="radio"
                name="q5"
                value="b"
                phx-click="answer"
                phx-value-question="q5"
                phx-value-answer="b"
              /> Пропуск 5 терминов
            </label>
            <label>
              <input
                type="radio"
                name="q5"
                value="c"
                phx-click="answer"
                phx-value-question="q5"
                phx-value-answer="c"
              /> Пропуск 6 терминов
            </label>
            <label>
              <input
                type="radio"
                name="q5"
                value="d"
                phx-click="answer"
                phx-value-question="q5"
                phx-value-answer="d"
              /> Пропуск 7 и более терминов
            </label>
          </fieldset>

          <button type="submit">Сдать работу</button>
        </form>
      <% end %>
    </div>
    """
  end
end
