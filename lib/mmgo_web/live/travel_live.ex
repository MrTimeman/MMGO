defmodule MMGOWeb.TravelLive do
  @moduledoc """
  The server-authoritative view of the local player's active journey.

  Travel advances in `MMGO.Travel` and completes through its scheduled worker;
  this LiveView only presents that state and refreshes it for the player.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @refresh_interval 15_000

  @impl true
  def mount(_params, session, socket) do
    case travel_state(session) do
      {:ok, %{journey: nil}} ->
        {:ok,
         socket
         |> put_flash(:info, "You do not have an active journey.")
         |> push_navigate(to: ~p"/map")}

      {:ok, state} ->
        socket = assign_travel_state(socket, state)

        if connected?(socket) do
          Process.send_after(self(), :refresh_travel, @refresh_interval)
        end

        {:ok, socket}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/play/continue")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_travel(socket)}
  end

  @impl true
  def handle_info(:refresh_travel, socket) do
    socket = refresh_travel(socket)

    if connected?(socket) do
      Process.send_after(self(), :refresh_travel, @refresh_interval)
    end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="trv-scene">
        <div id="travel-screen" class="trv-shell">
          <.link id="travel-back-to-map" navigate={~p"/map"} class="trv-exit">← На карту</.link>

          <header class="trv-head">
            <p class="trv-eyebrow">Переход · в пути</p>
            <h1 class="trv-route">
              {@journey.from_location.name} <span class="trv-route__arrow">→</span>
              {@journey.to_location.name}
            </h1>
            <div class="trv-stats">
              <div class="trv-stat">
                <span class="trv-stat__num">{@progress.elapsed_game_days}</span>
                <span class="trv-stat__cap">дней в пути</span>
              </div>
              <div class="trv-stat">
                <span class="trv-stat__num">{@progress.remaining_game_days}</span>
                <span class="trv-stat__cap">дней осталось</span>
              </div>
              <div class="trv-stat">
                <span class="trv-stat__num">{format_remaining(@progress.remaining_seconds)}</span>
                <span class="trv-stat__cap">до прибытия</span>
              </div>
            </div>
          </header>

          <section class="trv-path" aria-label="Текущий переход">
            <ol id="travel-waypoints" class="trv-wp">
              <li
                :for={{waypoint, index} <- Enum.with_index(@waypoints)}
                id={"travel-waypoint-#{index}"}
                class={[
                  "trv-wp__row",
                  index < @waypoint_index && "is-done",
                  index == @waypoint_index && "is-here",
                  index > @waypoint_index && "is-ahead"
                ]}
              >
                <span class="trv-wp__mark"></span>
                <div class="trv-wp__info">
                  <span class="trv-wp__name">
                    {waypoint.name}
                    <span :if={index == @waypoint_index} class="trv-wp__you">вы здесь</span>
                  </span>
                  <span class="trv-wp__note">{waypoint.note}</span>
                </div>
              </li>
            </ol>
          </section>

          <section id="travel-progress-panel" class="trv-panel">
            <div class="trv-panel__head">
              <h2 class="trv-panel__title">Ход путешествия</h2>
              <span class="trv-panel__meta">{@progress.percent}% пройдено</span>
            </div>
            <div class="trv-bar">
              <div class="trv-bar__fill" style={"width:#{@progress.percent}%"}></div>
            </div>
            <p class="trv-panel__sub">
              Прибытие: {format_datetime(@journey.arrival_at)}.
            </p>
          </section>

          <section id="travel-supplies-panel" class="trv-panel">
            <div class="trv-panel__head">
              <h2 class="trv-panel__title">Провизия и груз</h2>
              <span class="trv-panel__meta">{@food_units} ед. осталось в котомке</span>
            </div>
            <div class="trv-carry">
              <div class="trv-carry__head">
                <span>Груз на отправлении</span>
                <span class={["trv-carry__num", @carried_weight > @carry_capacity && "is-over"]}>
                  {@carried_weight} / {@carry_capacity}
                </span>
              </div>
              <div class="trv-bar trv-bar--slim">
                <div
                  class="trv-bar__fill trv-bar__fill--stone"
                  style={"width:#{bar_pct(@carried_weight, @carry_capacity)}%"}
                >
                </div>
              </div>
            </div>
            <p class="trv-panel__sub">
              На этот переход уже израсходовано {@journey.food_units_consumed} ед. еды.
              <span :if={@journey.encumbrance_penalty_days > 0}>
                Перегруз добавил {@journey.encumbrance_penalty_days} дн.
              </span>
            </p>
          </section>

          <section class="trv-panel" aria-label="Дорожный журнал">
            <div class="trv-panel__head">
              <h2 class="trv-panel__title">Дорожный журнал</h2>
            </div>
            <ul id="travel-log" class="trv-log">
              <li :for={entry <- @log} class="trv-log__row">
                <span class="trv-log__dot"></span>
                <span class="trv-log__text">{entry}</span>
              </li>
            </ul>
          </section>

          <div class="trv-acts">
            <.link id="travel-open-inventory" navigate={~p"/inventory"} class="trv-btn">
              Открыть котомку
            </.link>
            <button
              id="travel-refresh"
              type="button"
              class="trv-btn trv-btn--gold"
              phx-click="refresh"
            >
              Обновить переход
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp refresh_travel(socket) do
    case Play.travel_state(socket.assigns.character.id) do
      {:ok, %{journey: nil}} ->
        socket
        |> put_flash(:info, "You have arrived at your destination.")
        |> push_navigate(to: ~p"/map")

      {:ok, state} ->
        assign_travel_state(socket, state)

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/play/continue")
    end
  end

  defp travel_state(%{"demo_character_id" => character_id}) when is_binary(character_id),
    do: Play.travel_state(character_id)

  defp travel_state(_session), do: {:error, :missing_session}

  defp assign_travel_state(socket, state) do
    journey = state.journey

    socket
    |> assign(:page_title, "В пути")
    |> assign(:character, state.character)
    |> assign(:journey, journey)
    |> assign(:progress, state.journey_progress)
    |> assign(:food_units, state.food_units)
    |> assign(:carried_weight, journey.carried_weight)
    |> assign(:carry_capacity, journey.carry_capacity)
    |> assign(:waypoints, journey_waypoints(journey))
    |> assign(:waypoint_index, waypoint_index(state.journey_progress))
    |> assign(:log, journey_log(journey, state.journey_progress))
  end

  defp journey_waypoints(journey) do
    [
      %{name: journey.from_location.name, note: "точка отправления"},
      %{name: "В пути", note: "переход идёт на серверном времени мира"},
      %{name: journey.to_location.name, note: "место назначения"}
    ]
  end

  defp waypoint_index(%{percent: percent}) when percent >= 100, do: 2
  defp waypoint_index(_progress), do: 1

  defp journey_log(journey, progress) do
    [
      "Отправление: #{format_datetime(journey.started_at)}.",
      "На переход списано #{journey.food_units_consumed} ед. еды.",
      "Пройдено #{progress.elapsed_game_days} из #{journey.travel_days} игровых дней."
    ]
  end

  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m · %H:%M UTC")

  defp format_remaining(seconds) when seconds >= 3_600, do: "~#{div(seconds, 3_600)}ч"
  defp format_remaining(seconds) when seconds >= 60, do: "~#{div(seconds, 60)}м"
  defp format_remaining(_seconds), do: "сейчас"

  defp bar_pct(_value, max) when max <= 0, do: 0

  defp bar_pct(value, max),
    do: value |> Kernel./(max) |> Kernel.*(100) |> min(100) |> max(0) |> round()
end
