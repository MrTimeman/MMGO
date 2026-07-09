defmodule MMGOWeb.ClubEventLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts
  alias MMGO.Clubs
  alias MMGOWeb.LocationGate

  @impl true
  def mount(%{"event_id" => event_id}, session, socket) do
    character = socket.assigns[:current_character] || load_character(session)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :city) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          event = Clubs.get_event!(event_id)
          attended = already_attended?(event, character.id)

          {:ok,
           socket
           |> assign(:page_title, "Клубное событие — #{event_kind_label(event.kind)}")
           |> assign(:event, event)
           |> assign(:character, character)
           |> assign(:attended, attended)}
      end
    end
  end

  @impl true
  def handle_event("attend", _params, socket) do
    character = socket.assigns.character
    event = socket.assigns.event

    case Clubs.attend_event(event, character) do
      {:ok, _attendance} ->
        {:noreply,
         socket
         |> assign(:attended, true)
         |> put_flash(:info, "You attended the event!")}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="club-event">
      <a href={~p"/academy/bulletin-board"} class="map-back-link">← К доске</a>
      <h1>Клубное событие</h1>

      <section class="event-details">
        <p>Вид: <strong>{event_kind_label(@event.kind)}</strong></p>
        <p>Клуб: <strong>{@event.club && @event.club.name}</strong></p>
        <p>
          Назначено: <strong>{Calendar.strftime(@event.scheduled_at, "%d.%m %H:%M UTC")}</strong>
        </p>
        <p>Состояние: <strong>{status_label(@event.status)}</strong></p>
      </section>

      <section class="event-description">
        {event_description(@event.kind)}
      </section>

      <section class="event-action">
        <%= if @attended do %>
          <p>Вы отмечены в протоколе клуба. <strong>Знания и престиж начислены.</strong></p>
        <% else %>
          <%= if @event.status in [:scheduled, :active] do %>
            <button phx-click="attend">Присутствовать</button>
          <% else %>
            <p>Событие уже завершено, протокол закрыт.</p>
          <% end %>
        <% end %>
      </section>

      <div class="event-nav">
        <.link navigate={~p"/academy/bulletin-board"}>Вернуться к объявлениям</.link>
      </div>
    </div>
    """
  end

  defp already_attended?(event, character_id) do
    Enum.any?(event.attendances || [], &(&1.character_id == character_id))
  end

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    Accounts.get_character!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

  defp event_description(:general_meeting),
    do:
      "Круг преданий: студенты читают заметки, спорят о хрониках и заводят связи для будущих партий."

  defp event_description(:duel_tournament),
    do:
      "Дружеский бой без ставок и потери добычи. Победы идут в лестницу клуба, поражения остаются учебными."

  defp event_description(:research_session),
    do:
      "Общие заметки. Вклад сохранится и позже вернётся долей опыта, когда исследование дойдёт до Академии наук."

  defp event_description(:expedition_briefing),
    do:
      "Разбор учебной карты подземелья. Хороший план усилит следующий настоящий поход участников."

  defp event_description(_), do: ""

  defp event_kind_label(:general_meeting), do: "общий круг"
  defp event_kind_label(:duel_tournament), do: "дуэльный турнир"
  defp event_kind_label(:research_session), do: "исследовательская встреча"
  defp event_kind_label(:expedition_briefing), do: "экспедиционный разбор"
  defp event_kind_label(other), do: other || "событие"

  defp status_label(:scheduled), do: "назначено"
  defp status_label(:active), do: "идёт"
  defp status_label(:completed), do: "завершено"
  defp status_label(:cancelled), do: "отменено"
  defp status_label(other), do: other || "—"
end
