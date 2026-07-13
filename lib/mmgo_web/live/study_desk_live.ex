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
        enrollment = Academy.current_enrollment(character.id)
        terms = if enrollment, do: Academy.list_terms_for_enrollment(enrollment.id), else: []
        gpa = if enrollment, do: Academy.gpa_for_enrollment(enrollment.id), else: nil
        failed_count = if enrollment, do: Academy.failed_terms_count(enrollment.id), else: 0

        {:ok,
         socket
         |> assign(:page_title, "Учебный стол")
         |> assign(:character, character)
         |> assign(:enrollment, enrollment)
         |> assign(:terms, terms)
         |> assign(:gpa, gpa)
         |> assign(:failed_count, failed_count)}
    end
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="study-desk">
        <a href={~p"/academy"} class="map-back-link">← В холл Академии</a>
        <h1>Учебный стол</h1>

        <%= if @enrollment do %>
          <section class="desk-enrollment">
            <h2>Зачётная запись</h2>
            <p>Программа: <strong>{program_label(@enrollment.program_type)}</strong></p>
            <p>Путь: <strong>{track_label(@enrollment.track)}</strong></p>
            <p>Статус: <strong>{status_label(@enrollment.status)}</strong></p>
            <p>Средний балл: <strong>{@gpa || "экзаменов ещё нет"}</strong></p>
            <p>Проваленные термины: <strong>{@failed_count}</strong></p>
            <p>
              Ожидаемое завершение:
              <strong>{Calendar.strftime(@enrollment.expected_completion_at, "%d.%m.%Y")}</strong>
            </p>
          </section>

          <section class="desk-terms">
            <h2>Термины</h2>
            <table class="terms-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Состояние</th>
                  <th>Экзамен</th>
                  <th>Действие</th>
                </tr>
              </thead>
              <tbody>
                <%= for term <- @terms do %>
                  <tr>
                    <td>{term.term_number}</td>
                    <td>{status_label(term.status)}</td>
                    <td>{term.exam_score || "—"}</td>
                    <td>
                      <%= if term.status == :active do %>
                        <.link navigate={~p"/academy/exam/#{term.id}"}>сдать экзамен</.link>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
                <%= if @terms == [] do %>
                  <tr>
                    <td colspan="4">
                      <div class="acd-empty">
                        Ни один термин не открыт. На столе лежит чистая ведомость.
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>

            <%= if Academy.current_term(@enrollment.id) == nil do %>
              <button phx-click="begin_term">Начать следующий термин</button>
            <% end %>
          </section>
        <% else %>
          <p>
            Вы пока не числитесь на программе. Посмотрите <.link navigate={
              ~p"/academy/bulletin-board"
            }>доску объявлений</.link>,
            где писарь вывешивает набор и расписание.
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp program_label(:basic), do: "Базовое образование"
  defp program_label(:academy_core), do: "Academy Core"
  defp program_label(:extended_study), do: "Расширенный курс"
  defp program_label(:academia), do: "Академия наук"
  defp program_label(other), do: other || "—"

  defp track_label(nil), do: "—"
  defp track_label(:wizardry), do: "Чародейство"
  defp track_label(:alchemy), do: "Алхимия"
  defp track_label(:mastery), do: "Мастерство"
  defp track_label(other), do: other

  defp status_label(:active), do: "идёт"
  defp status_label(:completed), do: "завершён"
  defp status_label(:failed), do: "провален"
  defp status_label(:scheduled), do: "назначен"
  defp status_label(other), do: other || "—"
end
