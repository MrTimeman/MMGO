defmodule MMGOWeb.DuelLive do
  @moduledoc """
  Scoped wagered-duel lobby.

  A player can challenge only a real, stationary character at the same
  non-safe location. Acceptance transfers both players into the persisted
  combat flow; this LiveView never invents a bot, accepts on behalf of an
  opponent, or resolves a turn locally.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case Play.active_duel_combat_state(character) do
      {:ok, state} ->
        {:ok, push_navigate(socket, to: ~p"/combat/#{state.combat.id}")}

      {:error, :no_active_duel} ->
        load_lobby(socket, character)

      {:error, _reason} ->
        load_lobby(socket, character, "Не удалось проверить текущий поединок.")
    end
  end

  @impl true
  def handle_event(
        "challenge",
        %{"duel_challenge" => %{"opponent_id" => opponent_id, "stake" => stake_raw}},
        socket
      ) do
    with {:ok, stake} <- parse_stake(stake_raw),
         {:ok, _result} <- Play.challenge_duel(socket.assigns.character, opponent_id, stake) do
      {:noreply,
       socket
       |> put_flash(:info, "Вызов отправлен. Ставка будет внесена только после принятия.")
       |> refresh_lobby()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event("challenge", _params, socket) do
    {:noreply, assign(socket, :error, "Выберите соперника и положительную ставку.")}
  end

  @impl true
  def handle_event("accept", %{"duel-id" => duel_id}, socket) do
    case Play.accept_duel(socket.assigns.character, duel_id) do
      {:ok, %{duel: duel}} when is_binary(duel.combat_id) ->
        {:noreply, push_navigate(socket, to: ~p"/combat/#{duel.combat_id}")}

      {:ok, _result} ->
        {:noreply, assign(socket, :error, "Поединок принят, но круг боя ещё не готов.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("reject", %{"duel-id" => duel_id}, socket) do
    case Play.reject_duel(socket.assigns.character, duel_id) do
      {:ok, _result} ->
        {:noreply, socket |> put_flash(:info, "Вызов отклонён.") |> refresh_lobby()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("cancel", %{"duel-id" => duel_id}, socket) do
    case Play.cancel_pending_duel(socket.assigns.character, duel_id) do
      {:ok, _result} ->
        {:noreply, socket |> put_flash(:info, "Непринятый вызов отменён.") |> refresh_lobby()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="duel-screen" class="game-root min-h-full overflow-y-auto px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="duel-back-to-map" navigate={~p"/map"} class="map-back-link">
            ← Карта мира
          </.link>

          <header class="border-b border-amber-500/20 pb-5">
            <p class="text-xs uppercase tracking-[0.22em] text-amber-300/70">
              {location_label(@location)} · круг поединка
            </p>
            <h1 class="mt-2 font-serif text-3xl text-amber-200">Дуэль</h1>
            <p id="duel-identity" class="mt-2 text-sm text-stone-400">
              {@character.name} · кошель: {@balance} ◈
            </p>
          </header>

          <div
            :if={@error}
            id="duel-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section
            id="duel-lobby"
            class="rounded-xl border border-stone-700 bg-stone-900/70 p-6 shadow-xl"
          >
            <h2 class="font-serif text-xl text-stone-100">Вызвать игрока</h2>
            <p class="mt-2 max-w-xl text-sm leading-6 text-stone-400">
              Оба игрока должны стоять здесь. Ставка попадёт в эскроу только после принятия;
              начатый бой нельзя отменить ради возврата — только завершить или бежать.
            </p>

            <p
              :if={@location.safe_zone}
              id="duel-safe-zone"
              class="mt-5 rounded-md border border-sky-400/30 bg-sky-950/30 px-4 py-3 text-sm text-sky-100"
            >
              Это безопасная зона. Поединки здесь запрещены — выйдите в опасную местность.
            </p>

            <p
              :if={not @location.safe_zone and @opponents == []}
              id="duel-opponents-empty"
              class="mt-5 text-sm text-stone-400"
            >
              Рядом нет готовых к вызову игроков.
            </p>

            <.form
              :if={not @location.safe_zone and @opponents != []}
              for={@challenge_form}
              id="duel-challenge-form"
              phx-submit="challenge"
              class="mt-5 grid gap-3 sm:grid-cols-[1fr_10rem_auto] sm:items-end"
            >
              <.input
                field={@challenge_form[:opponent_id]}
                type="select"
                label="Соперник"
                prompt="Выберите игрока"
                options={@opponent_options}
              />
              <.input
                field={@challenge_form[:stake]}
                type="number"
                label="Ставка"
                min="1"
                inputmode="numeric"
              />
              <button
                id="duel-challenge"
                type="submit"
                class="mb-4 rounded-md bg-amber-300 px-5 py-3 font-serif font-semibold text-stone-950 transition hover:bg-amber-200"
              >
                Отправить вызов
              </button>
            </.form>
          </section>

          <section
            :if={@incoming != []}
            id="duel-incoming"
            class="rounded-xl border border-emerald-500/30 bg-emerald-950/20 p-5"
          >
            <h2 class="font-serif text-xl text-emerald-100">Вам бросили вызов</h2>
            <article
              :for={duel <- @incoming}
              id={"duel-incoming-#{duel.id}"}
              class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/50 p-4"
            >
              <div>
                <p class="font-medium text-stone-100">{duel.challenger_character.name}</p>
                <p class="text-sm text-stone-400">Ставка: {duel.stake_amount} ◈ с каждой стороны</p>
              </div>
              <div class="flex gap-2">
                <button
                  id={"duel-accept-#{duel.id}"}
                  type="button"
                  phx-click="accept"
                  phx-value-duel-id={duel.id}
                  class="rounded-md bg-emerald-300 px-3 py-2 text-sm font-semibold text-stone-950"
                >
                  Принять
                </button>
                <button
                  id={"duel-reject-#{duel.id}"}
                  type="button"
                  phx-click="reject"
                  phx-value-duel-id={duel.id}
                  class="rounded-md border border-stone-600 px-3 py-2 text-sm text-stone-200"
                >
                  Отклонить
                </button>
              </div>
            </article>
          </section>

          <section
            :if={@outgoing != []}
            id="duel-outgoing"
            class="rounded-xl border border-amber-500/25 bg-amber-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-amber-100">Ожидают ответа</h2>
            <article
              :for={duel <- @outgoing}
              id={"duel-outgoing-#{duel.id}"}
              class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/50 p-4"
            >
              <div>
                <p class="font-medium text-stone-100">{duel.opponent_character.name}</p>
                <p class="text-sm text-stone-400">Ставка: {duel.stake_amount} ◈ с каждой стороны</p>
              </div>
              <button
                id={"duel-cancel-#{duel.id}"}
                type="button"
                phx-click="cancel"
                phx-value-duel-id={duel.id}
                class="rounded-md border border-stone-600 px-3 py-2 text-sm text-stone-200"
              >
                Отменить вызов
              </button>
            </article>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_lobby(socket, character, initial_error \\ nil) do
    case Play.duel_lobby_state(character) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(:page_title, "Дуэль")
         |> assign(:error, initial_error)
         |> assign_lobby(state)}

      {:error, :travelling} ->
        {:ok,
         socket
         |> put_flash(:error, "Нельзя вызывать на дуэль во время пути.")
         |> push_navigate(to: ~p"/travel")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Круг поединка сейчас недоступен.")
         |> push_navigate(to: ~p"/map")}
    end
  end

  defp assign_lobby(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:location, state.location)
    |> assign(:balance, state.balance)
    |> assign(:incoming, state.incoming)
    |> assign(:outgoing, state.outgoing)
    |> assign(:opponents, state.opponents)
    |> assign(:opponent_options, Enum.map(state.opponents, &{&1.name, &1.id}))
    |> assign(
      :challenge_form,
      to_form(%{"opponent_id" => "", "stake" => "100"}, as: :duel_challenge)
    )
  end

  defp refresh_lobby(socket) do
    case Play.duel_lobby_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_lobby(state)
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Круг поединка сейчас недоступен.")
    end
  end

  defp parse_stake(stake) when is_binary(stake) do
    case Integer.parse(stake) do
      {amount, ""} when amount > 0 -> {:ok, amount}
      _other -> {:error, :invalid_stake}
    end
  end

  defp parse_stake(_stake), do: {:error, :invalid_stake}

  defp location_label(location), do: location.name

  defp error_message(:opponent_not_found), do: "Этот игрок больше не находится рядом."
  defp error_message(:invalid_stake), do: "Укажите положительную ставку."
  defp error_message(:duel_not_found), do: "Вызов больше недоступен."
  defp error_message(:not_challenged_player), do: "Принять вызов может только приглашённый игрок."
  defp error_message(:not_challenger), do: "Отменить вызов может только тот, кто его отправил."
  defp error_message(:travelling), do: "Нельзя управлять дуэлью во время пути."
  defp error_message(:location_not_found), do: "Текущее место не определено."

  defp error_message(_reason),
    do: "Команда поединка не выполнена. Проверьте место, ставку и кошелёк."
end
