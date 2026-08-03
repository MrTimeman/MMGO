defmodule MMGOWeb.DuelLive do
  @moduledoc """
  Scoped consensual-duel lobby.

  Permanent rules restrict challenges by location and wager. The temporary
  beta sandbox exposes zero-stake challenges to every active player profile.
  Acceptance still transfers both players into the persisted combat flow;
  this LiveView never invents a bot or accepts on behalf of an opponent.
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
    with {:ok, stake} <- parse_stake(stake_raw, socket.assigns.unrestricted_playtest?),
         {:ok, _result} <- Play.challenge_duel(socket.assigns.character, opponent_id, stake) do
      {:noreply,
       socket
       |> put_flash(:info, challenge_sent_message(socket.assigns.unrestricted_playtest?))
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
  def render(%{character: _character} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="duel-screen" class="duel-scene">
        <div class="duel-stage">
          <.link id="duel-back-to-map" navigate={~p"/map"} class="duel-exit">
            ← покинуть круг
          </.link>

          <header class="duel-mast">
            <p>
              {if(@unrestricted_playtest?,
                do: "испытательный круг · весь реалм",
                else: "круг поединка · #{location_label(@location)}"
              )}
            </p>
            <h1>Вызов на дуэль</h1>
            <span id="duel-identity">{@character.name} · кошель {@balance} ◈</span>
          </header>

          <div :if={@error} id="duel-error" class="duel__parchment duel-error" role="alert">
            <span class="duel__badge duel__badge--rejected">печать не принята</span>
            <p class="duel__text">{@error}</p>
          </div>

          <section id="duel-lobby" class="duel">
            <article class="duel__parchment duel__parchment--challenge">
              <p class="duel__salutation">Достопочтенный соперник,</p>
              <p class="duel__text">
                Настоящим письмом {@character.name} предлагает честный поединок.
                <%= if @unrestricted_playtest? do %>
                  Это свободная тренировочная дуэль без ставки и географических ограничений.
                <% else %>
                  Ставка переходит под печать только после согласия обеих сторон.
                <% end %>
              </p>

              <div class="duel__vs-row">
                <span class="duel__vs-side">
                  <strong class="duel__vs-name">{@character.name}</strong>
                  <small>вызывающий</small>
                </span>
                <span class="duel__vs-sep">против</span>
                <span class="duel__vs-side">
                  <strong class="duel__vs-name">имя будет вписано</strong>
                  <small>соперник</small>
                </span>
              </div>

              <p
                :if={not @unrestricted_playtest? and @location.safe_zone}
                id="duel-safe-zone"
                class="duel-seal-note duel-seal-note--safe"
              >
                Городская печать запрещает поединки в этой безопасной зоне.
              </p>

              <p
                :if={(@unrestricted_playtest? or not @location.safe_zone) and @opponents == []}
                id="duel-opponents-empty"
                class="duel__question"
              >
                Сейчас рядом нет игрока, готового принять письмо.
              </p>

              <.form
                :if={(@unrestricted_playtest? or not @location.safe_zone) and @opponents != []}
                for={@challenge_form}
                id="duel-challenge-form"
                phx-submit="challenge"
                class="duel-challenge-form"
              >
                <.input
                  field={@challenge_form[:opponent_id]}
                  type="select"
                  label="Кому адресован вызов"
                  prompt="Выберите игрока"
                  options={@opponent_options}
                  class="duel-field"
                />
                <.input
                  :if={@unrestricted_playtest?}
                  field={@challenge_form[:stake]}
                  type="hidden"
                  value="0"
                />
                <.input
                  :if={not @unrestricted_playtest?}
                  field={@challenge_form[:stake]}
                  type="number"
                  label="Ставка под печатью"
                  min="1"
                  inputmode="numeric"
                  class="duel-field"
                />
                <button id="duel-challenge" type="submit" class="duel__btn duel__btn--wax">
                  Запечатать и отправить
                </button>
              </.form>

              <p class="duel__ministry">— реестр поединков Министерства Магии</p>
            </article>
          </section>

          <section :if={@incoming != []} id="duel-incoming" class="duel-stack">
            <p class="duel-stack__label">Письма, ожидающие вашей подписи</p>
            <article
              :for={duel <- @incoming}
              id={"duel-incoming-#{duel.id}"}
              class="duel__parchment"
            >
              <p class="duel__salutation">{@character.name},</p>
              <div class="duel__vs-row">
                <span class="duel__vs-side">
                  <strong class="duel__vs-name">{duel.challenger_character.name}</strong>
                  <small>бросает вызов</small>
                </span>
                <span class="duel__vs-sep">
                  {if(duel.stake_amount == 0, do: "режим", else: "ставка")}
                </span>
                <span class="duel__stake">
                  {if(duel.stake_amount == 0, do: "тренировка", else: "#{duel.stake_amount} ◈")}
                </span>
              </div>
              <p class="duel__question">Примете ли вы условия?</p>
              <div class="duel__actions">
                <button
                  id={"duel-accept-#{duel.id}"}
                  type="button"
                  phx-click="accept"
                  phx-value-duel-id={duel.id}
                  class="duel__btn duel__btn--accept"
                >
                  Принять
                </button>
                <button
                  id={"duel-reject-#{duel.id}"}
                  type="button"
                  phx-click="reject"
                  phx-value-duel-id={duel.id}
                  class="duel__btn duel__btn--reject"
                >
                  Отклонить
                </button>
              </div>
              <p class="duel__ministry">
                {if(duel.stake_amount == 0,
                  do: "— без ставки, по взаимному согласию",
                  else: "— ставка с каждой стороны"
                )}
              </p>
            </article>
          </section>

          <section :if={@outgoing != []} id="duel-outgoing" class="duel-stack">
            <p class="duel-stack__label">Отправленные письма</p>
            <article
              :for={duel <- @outgoing}
              id={"duel-outgoing-#{duel.id}"}
              class="duel__parchment duel__parchment--waiting"
            >
              <span class="duel__badge">ожидает ответа</span>
              <p class="duel__salutation">{duel.opponent_character.name},</p>
              <p class="duel__text">
                <%= if duel.stake_amount == 0 do %>
                  Свободный тренировочный вызов отправлен.
                <% else %>
                  Вызов отправлен со ставкой <strong class="duel__stake">{duel.stake_amount} ◈</strong>.
                <% end %>
              </p>
              <button
                id={"duel-cancel-#{duel.id}"}
                type="button"
                phx-click="cancel"
                phx-value-duel-id={duel.id}
                class="duel__btn duel__btn--reject"
              >
                Отозвать письмо
              </button>
              <p class="duel__ministry">— до принятия печать можно снять</p>
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
    |> assign(:unrestricted_playtest?, state.unrestricted_playtest?)
    |> assign(:incoming, state.incoming)
    |> assign(:outgoing, state.outgoing)
    |> assign(:opponents, state.opponents)
    |> assign(:opponent_options, Enum.map(state.opponents, &{&1.name, &1.id}))
    |> assign(
      :challenge_form,
      to_form(
        %{
          "opponent_id" => "",
          "stake" => if(state.unrestricted_playtest?, do: "0", else: "100")
        },
        as: :duel_challenge
      )
    )
  end

  defp refresh_lobby(socket) do
    case Play.duel_lobby_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_lobby(state)
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Круг поединка сейчас недоступен.")
    end
  end

  defp parse_stake(stake, unrestricted_playtest?) when is_binary(stake) do
    case Integer.parse(stake) do
      {0, ""} when unrestricted_playtest? -> {:ok, 0}
      {amount, ""} when amount > 0 -> {:ok, amount}
      _other -> {:error, :invalid_stake}
    end
  end

  defp parse_stake(_stake, _unrestricted_playtest?), do: {:error, :invalid_stake}

  defp challenge_sent_message(true), do: "Свободный тренировочный вызов отправлен."

  defp challenge_sent_message(false),
    do: "Вызов отправлен. Ставка будет внесена только после принятия."

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
