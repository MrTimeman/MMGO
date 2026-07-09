defmodule MMGOWeb.DuelLive do
  @moduledoc """
  A local PvP duel surface backed by the real PvP and combat contexts.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, session, socket) do
    case session_character(session, :demo_character_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/play/continue")}

      character ->
        case LocationGate.gate(socket, character, :tower) do
          {:halt, socket} ->
            {:ok, socket}

          {:ok, socket} ->
            {:ok,
             socket
             |> assign(:page_title, "Дуэль")
             |> assign(:character, character)
             |> assign(:opponent, session_character(session, :demo_opponent_id))
             |> assign(:duel_state, active_duel_state(character))
             |> assign(:error, nil)}
        end
    end
  end

  @impl true
  def handle_event("challenge_bot", _params, socket) do
    case socket.assigns.opponent do
      nil ->
        {:noreply,
         assign(socket, :error, "Local opponent not set up. Visit /play/continue first.")}

      opponent ->
        case Play.start_demo_duel(socket.assigns.character, opponent.id) do
          {:ok, state} -> {:noreply, apply_duel_state(socket, state)}
          {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
        end
    end
  end

  @impl true
  def handle_event("cast_spell", %{"spell_id" => spell_id}, socket) do
    case Play.cast_and_resolve_duel_turn(socket.assigns.character, spell_id) do
      {:ok, state} -> {:noreply, apply_duel_state(socket, state)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("wait", _params, socket) do
    case Play.wait_and_resolve_duel_turn(socket.assigns.character) do
      {:ok, state} -> {:noreply, apply_duel_state(socket, state)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("cancel_duel", _params, socket) do
    case Play.cancel_active_duel(socket.assigns.character) do
      {:ok, _duel} ->
        {:noreply,
         socket
         |> assign(:duel_state, nil)
         |> assign(:error, nil)
         |> put_flash(:info, "The duel was cancelled and the wager was refunded.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main id="duel-screen" class="game-root min-h-full overflow-y-auto px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl">
          <.link id="duel-back-to-map" navigate={~p"/map"} class="map-back-link">← World map</.link>

          <header class="mb-8 border-b border-amber-500/20 pb-5">
            <p class="text-xs uppercase tracking-[0.22em] text-amber-300/70">Башня · круг поединка</p>
            <h1 class="mt-2 font-serif text-3xl text-amber-200">Дуэль</h1>
            <p id="duel-identity" class="mt-2 text-sm text-stone-400">
              {@character.name}
              <span :if={@opponent} class="text-stone-600"> против    {@opponent.name}</span>
            </p>
          </header>

          <div
            :if={@error}
            id="duel-error"
            class="mb-5 rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <%= if is_nil(@duel_state) do %>
            <section
              id="duel-lobby"
              class="rounded-xl border border-stone-700 bg-stone-900/70 p-6 shadow-xl"
            >
              <h2 class="font-serif text-xl text-stone-100">Круг свободен</h2>
              <p class="mt-2 max-w-xl text-sm leading-6 text-stone-400">
                Вызов создаёт настоящую ставку: по 100 монет с каждой стороны. Локальный соперник
                принимает вызов сразу, затем каждый ваш ход попадает в серверный combat engine.
              </p>
              <button
                :if={@opponent}
                id="duel-challenge-bot"
                type="button"
                phx-click="challenge_bot"
                class="mt-5 rounded-md bg-amber-300 px-5 py-2.5 font-serif font-semibold text-stone-950 transition hover:bg-amber-200"
              >
                Challenge {@opponent.name}
              </button>
              <.link
                :if={is_nil(@opponent)}
                id="duel-setup-opponent"
                navigate={~p"/play/continue"}
                class="mt-5 inline-block text-sm text-amber-200 underline"
              >
                Set up the local opponent
              </.link>
            </section>
          <% else %>
            <section id="duel-combat-state" class="space-y-5">
              <div class="rounded-xl border border-stone-700 bg-stone-900/70 p-5 shadow-xl">
                <div class="flex flex-wrap items-baseline justify-between gap-3">
                  <div>
                    <p class="text-xs uppercase tracking-[0.16em] text-stone-500">Статус</p>
                    <p id="duel-status" class="mt-1 font-serif text-xl text-amber-200">
                      {status_name(@duel_state.duel.status)} · ход {@duel_state.combat.turn_number}
                    </p>
                  </div>
                  <p id="duel-stakes" class="text-sm text-stone-400">
                    Ставка {@duel_state.duel.stake_amount} · банк {@duel_state.duel.pot_amount}
                  </p>
                </div>

                <div id="duel-sides" class="mt-5 grid gap-3 sm:grid-cols-2">
                  <article
                    :for={side <- @duel_state.sides}
                    id={"duel-side-#{side.id}"}
                    class="rounded-lg border border-stone-700/80 bg-stone-950/50 p-4"
                  >
                    <div class="flex items-center justify-between gap-2">
                      <h2 class="font-serif text-lg text-stone-100">{side.label}</h2>
                      <span class="text-sm text-amber-200">
                        {side.shared_hp} / {side.max_shared_hp}
                      </span>
                    </div>
                    <div class="mt-3 h-2 overflow-hidden rounded bg-stone-800">
                      <div
                        class="h-full rounded bg-amber-400 transition-[width] duration-500"
                        style={"width:#{hp_percent(side.shared_hp, side.max_shared_hp)}%"}
                      >
                      </div>
                    </div>
                    <p class="mt-3 text-sm text-stone-400">{Enum.join(side.participants, ", ")}</p>
                  </article>
                </div>
              </div>

              <%= if @duel_state.duel.status == :active do %>
                <section
                  id="duel-actions"
                  class="rounded-xl border border-amber-500/25 bg-stone-900/70 p-5"
                >
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <h2 class="font-serif text-xl text-amber-200">Ваш ход</h2>
                      <p class="mt-1 text-sm text-stone-400">
                        Выберите подготовленное заклинание. Соперник ждёт, затем движок одновременно
                        разрешает ход и фиксирует результат.
                      </p>
                    </div>
                    <button
                      id="duel-wait"
                      type="button"
                      phx-click="wait"
                      class="rounded-md border border-stone-600 px-3 py-2 text-sm text-stone-300 transition hover:border-stone-400 hover:text-white"
                    >
                      Выждать
                    </button>
                  </div>

                  <div id="duel-spells" class="mt-4 flex flex-wrap gap-2">
                    <button
                      :for={spell <- @duel_state.prepared_spells}
                      id={"duel-cast-#{spell.id}"}
                      type="button"
                      phx-click="cast_spell"
                      phx-value-spell_id={spell.id}
                      class="rounded-md bg-amber-300 px-4 py-2 text-sm font-semibold text-stone-950 transition hover:bg-amber-200"
                    >
                      {spell.name}
                      <span class="ml-1 text-stone-700">· усталость {spell.fatigue_cost}</span>
                    </button>
                    <p
                      :if={@duel_state.prepared_spells == []}
                      id="duel-no-spells"
                      class="text-sm text-stone-500"
                    >
                      В активном гримуаре нет доступных заклинаний.
                    </p>
                  </div>

                  <button
                    id="duel-cancel"
                    type="button"
                    phx-click="cancel_duel"
                    class="mt-5 text-sm text-stone-500 underline transition hover:text-stone-300"
                  >
                    Отменить дуэль и вернуть ставку
                  </button>
                </section>
              <% else %>
                <section
                  id="duel-outcome"
                  class="rounded-xl border border-amber-500/35 bg-amber-950/15 p-5"
                >
                  <h2 class="font-serif text-xl text-amber-200">{outcome_title(@duel_state.duel)}</h2>
                  <p class="mt-2 text-sm text-stone-300">{outcome_note(@duel_state.duel)}</p>
                </section>
              <% end %>

              <section id="duel-events" class="rounded-xl border border-stone-700 bg-stone-900/70 p-5">
                <h2 class="font-serif text-xl text-stone-100">Последние события</h2>
                <p
                  :if={@duel_state.events == []}
                  id="duel-no-events"
                  class="mt-3 text-sm text-stone-500"
                >
                  Первый ход ещё не разрешён.
                </p>
                <ol class="mt-3 space-y-2 text-sm text-stone-400">
                  <li :for={event <- @duel_state.events} id={"duel-event-#{event.id}"}>
                    <span class="text-amber-300">Ход {event.turn_number}</span>
                    <span class="text-stone-600">·</span>
                    {event_name(event.event_type)}
                  </li>
                </ol>
              </section>
            </section>
          <% end %>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp active_duel_state(character) do
    case Play.active_duel_combat_state(character) do
      {:ok, state} -> state
      {:error, :no_active_duel} -> nil
      {:error, _reason} -> nil
    end
  end

  defp apply_duel_state(socket, state) do
    socket
    |> assign(:duel_state, state)
    |> assign(:error, nil)
  end

  defp session_character(session, key) do
    with id when is_binary(id) <- session[to_string(key)],
         {:ok, %{character: character}} <- Play.load_demo_state(id) do
      character
    else
      _other -> nil
    end
  end

  defp hp_percent(_hp, max_hp) when max_hp <= 0, do: 0

  defp hp_percent(hp, max_hp),
    do: hp |> Kernel./(max_hp) |> Kernel.*(100) |> min(100) |> max(0) |> round()

  defp status_name(:active), do: "В бою"
  defp status_name(:resolved), do: "Завершена"
  defp status_name(:cancelled), do: "Отменена"
  defp status_name(status), do: status |> to_string() |> String.capitalize()

  defp outcome_title(%{winner_character: %{name: name}}), do: "Победитель: #{name}"
  defp outcome_title(%{status: :cancelled}), do: "Дуэль отменена"
  defp outcome_title(_duel), do: "Дуэль завершена"

  defp outcome_note(%{status: :resolved}), do: "Ставка рассчитана сервером и записана в реестр."
  defp outcome_note(%{status: :cancelled}), do: "Ставка возвращена сервером."
  defp outcome_note(_duel), do: "Результат зафиксирован."

  defp event_name(event_type) do
    event_type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  defp error_message(:spell_not_prepared),
    do: "That spell is not prepared in your active grimoire."

  defp error_message(:no_active_duel), do: "There is no active duel."
  defp error_message(:missing_opponent), do: "The local opponent is unavailable."
  defp error_message(reason), do: "The duel could not be updated: #{inspect(reason)}"
end
