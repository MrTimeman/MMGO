defmodule MMGOWeb.ClubEventLive do
  use MMGOWeb, :live_view

  alias MMGO.Clubs

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    event = Clubs.get_event!(event_id)
    character = socket.assigns[:current_character]
    attended = character && already_attended?(event, character.id)

    {:ok,
     socket
     |> assign(:page_title, "Club Event — #{event.kind}")
     |> assign(:event, event)
     |> assign(:character, character)
     |> assign(:attended, attended)}
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
      <h1>Club Event</h1>

      <section class="event-details">
        <p>Type: <strong>{@event.kind}</strong></p>
        <p>Club: <strong>{@event.club && @event.club.name}</strong></p>
        <p>
          Scheduled: <strong>{Calendar.strftime(@event.scheduled_at, "%Y-%m-%d %H:%M UTC")}</strong>
        </p>
        <p>Status: <strong>{@event.status}</strong></p>
      </section>

      <section class="event-description">
        {event_description(@event.kind)}
      </section>

      <section class="event-action">
        <%= if @attended do %>
          <p>You have attended this event. <strong>+XP awarded.</strong></p>
        <% else %>
          <%= if @event.status in [:scheduled, :active] do %>
            <button phx-click="attend">Attend Event</button>
          <% else %>
            <p>This event has ended.</p>
          <% end %>
        <% end %>
      </section>

      <div class="event-nav">
        <.link navigate={~p"/academy/bulletin-board"}>Back to Bulletin Board</.link>
      </div>
    </div>
    """
  end

  defp already_attended?(event, character_id) do
    Enum.any?(event.attendances || [], &(&1.character_id == character_id))
  end

  defp event_description(:general_meeting),
    do: "A lore circle gathering. Share knowledge and build friendships."

  defp event_description(:duel_tournament),
    do: "Friendly PvP — no wager, no loot transfer. Test your skills on the ladder."

  defp event_description(:research_session),
    do: "Collaborative notes session. Contributions count toward future Academia XP."

  defp event_description(:expedition_briefing),
    do: "Study a simulated dungeon map. Good plans boost your next real run."

  defp event_description(_), do: ""
end
