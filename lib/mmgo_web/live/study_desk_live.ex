defmodule MMGOWeb.StudyDeskLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:page_title, "Учебный стол")
         |> assign(:character, character)
         |> refresh_desk()}
    end
  end

  @impl true
  def handle_event("begin_term", _params, socket) do
    enrollment = socket.assigns.enrollment

    case enrollment && Academy.begin_term(enrollment.id) do
      {:ok, _term} ->
        {:noreply,
         socket
         |> put_flash(:info, "Следующий термин открыт.")
         |> refresh_desk()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, error_message(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "Нет действующей учебной записи.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="study-desk-screen" class="study-desk">
        <div class="study-desk__folio">
          <.link id="study-desk-back" navigate={~p"/academy"} class="map-back-link">
            ← В холл Академии
          </.link>
          <header class="study-desk__heading">
            <p>Личная зачётная книга</p>
            <h1>Учебный стол</h1>
            <span>Архив Академии · экземпляр студента</span>
          </header>

          <%= if @enrollment do %>
            <section id="study-desk-enrollment" class="desk-enrollment desk-sheet">
              <div class="desk-sheet__pin" aria-hidden="true"></div>
              <p class="desk-sheet__kicker">Зачётная запись</p>
              <h2>{program_label(@enrollment.program_type)}</h2>
              <dl class="desk-enrollment__facts">
                <div>
                  <dt>Путь</dt>
                  <dd>{track_label(@enrollment.track)}</dd>
                </div>
                <div>
                  <dt>Состояние</dt>
                  <dd>{status_label(@enrollment.status)}</dd>
                </div>
                <div>
                  <dt>Средний балл</dt>
                  <dd>{@gpa || "экзаменов ещё нет"}</dd>
                </div>
                <div>
                  <dt>Провалено терминов</dt>
                  <dd>{@failed_count}</dd>
                </div>
                <div>
                  <dt>Завершение программы</dt>
                  <dd>{format_time(@enrollment.expected_completion_at)}</dd>
                </div>
              </dl>
            </section>

            <section id="study-desk-terms" class="desk-terms desk-sheet">
              <div class="desk-terms__heading">
                <div>
                  <p class="desk-sheet__kicker">Архив сроков</p>
                  <h2>Термины</h2>
                </div>
                <span>{length(@terms)} записей</span>
              </div>
              <div class="terms-table-wrap">
                <table id="study-desk-terms-table" class="terms-table">
                  <thead>
                    <tr>
                      <th>Термин</th>
                      <th>Состояние</th>
                      <th>Оценка</th>
                      <th>Действие</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for term <- @terms do %>
                      <tr id={"study-desk-term-#{term.id}"} class={"terms-table__row--#{term.status}"}>
                        <td data-label="Термин">{term.term_number}</td>
                        <td data-label="Состояние">{status_label(term.status)}</td>
                        <td data-label="Оценка">{term.exam_score || "—"}</td>
                        <td data-label="Действие">
                          <.link :if={term.status == :active} navigate={~p"/academy/timetable"}>
                            к расписанию
                          </.link>
                          <span :if={term.status != :active}>—</span>
                        </td>
                      </tr>
                    <% end %>
                    <%= if @terms == [] do %>
                      <tr class="terms-table__empty">
                        <td colspan="4">
                          Ни один термин не открыт. На столе лежит чистая ведомость.
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <div id="study-desk-term-actions" class="desk-terms__actions">
                <button
                  :if={is_nil(@current_term) && term_startable?(@next_term_schedule)}
                  id="study-desk-begin-term"
                  type="button"
                  phx-click="begin_term"
                >
                  Открыть следующий термин
                </button>
                <p :if={is_nil(@current_term) && term_waiting?(@next_term_schedule)}>
                  Следующий термин откроется {format_time(@next_term_schedule.starts_at)}.
                </p>
                <p :if={is_nil(@current_term) && is_nil(@next_term_schedule)}>
                  Все предусмотренные сроки уже внесены в книгу.
                </p>
              </div>
            </section>
          <% else %>
            <section id="study-desk-empty" class="desk-sheet desk-sheet--empty">
              <p>
                Вы пока не числитесь на программе. Посмотрите <.link navigate={
                  ~p"/academy/bulletin-board"
                }>доску объявлений</.link>, где писарь вывешивает набор и расписание.
              </p>
            </section>
          <% end %>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    messages = Enum.map(changeset.errors, fn {_field, {message, _opts}} -> message end)

    cond do
      "the next term has not opened yet" in messages ->
        "Следующий термин ещё не открыт. Дата указана на ведомости."

      "a term is already active" in messages ->
        "Текущий термин уже открыт."

      "all program terms have already been recorded" in messages ->
        "Все предусмотренные программой термины уже внесены в ведомость."

      "enrollment is not active" in messages ->
        "Учебная запись уже закрыта."

      true ->
        "Учебный архив отклонил действие. Обновите ведомость и попробуйте ещё раз."
    end
  end

  defp refresh_desk(socket) do
    enrollment = Academy.current_enrollment(socket.assigns.character.id)
    terms = if enrollment, do: Academy.list_terms_for_enrollment(enrollment.id), else: []
    current_term = if enrollment, do: Academy.current_term(enrollment.id), else: nil

    next_term_schedule =
      if enrollment && is_nil(current_term) do
        Academy.term_schedule(enrollment, length(terms) + 1)
      end

    socket
    |> assign(:enrollment, enrollment)
    |> assign(:terms, terms)
    |> assign(:current_term, current_term)
    |> assign(:next_term_schedule, next_term_schedule)
    |> assign(:gpa, if(enrollment, do: Academy.gpa_for_enrollment(enrollment.id), else: nil))
    |> assign(
      :failed_count,
      if(enrollment, do: Academy.failed_terms_count(enrollment.id), else: 0)
    )
  end

  defp term_startable?(%{starts_at: starts_at}),
    do: DateTime.compare(DateTime.utc_now(), starts_at) != :lt

  defp term_startable?(_schedule), do: false

  defp term_waiting?(%{starts_at: starts_at}),
    do: DateTime.compare(DateTime.utc_now(), starts_at) == :lt

  defp term_waiting?(_schedule), do: false
  defp format_time(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y · %H:%M")

  defp program_label(:basic_education), do: "Базовое образование"
  defp program_label(:academy_core), do: "Ядро Академии"
  defp program_label(:extended_study), do: "Расширенный курс"
  defp program_label(:academia), do: "Академия наук"
  defp program_label(_other), do: "Учебная программа"

  defp track_label(nil), do: "—"
  defp track_label(:wizardry), do: "Чародейство"
  defp track_label(:alchemy), do: "Алхимия"
  defp track_label(:mastery), do: "Мастерство"
  defp track_label(_other), do: "Общий путь"

  defp status_label(:active), do: "идёт"
  defp status_label(:completed), do: "завершён"
  defp status_label(:failed), do: "провален"
  defp status_label(:pending), do: "не открывался"
  defp status_label(:scheduled), do: "назначен"
  defp status_label(_other), do: "ожидает"
end
