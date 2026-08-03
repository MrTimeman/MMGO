defmodule MMGOWeb.ThesisDefenseLive do
  @moduledoc """
  Scoped public thesis-defense ceremony backed by the persisted Academia state.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        {:ok, socket |> assign(:page_title, "Защита тезиса") |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_params(%{"id" => project_id}, _uri, socket) do
    {:noreply, load_defense(socket, project_id)}
  end

  @impl true
  def handle_event("vote", %{"vote" => vote}, socket) do
    case Play.submit_scoped_thesis_vote(
           socket.assigns.current_scope.character,
           socket.assigns.state.project.id,
           vote
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Голос комиссии занесён в протокол.")
         |> assign(:error, nil)
         |> assign(:state, state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_defense(socket, socket.assigns.state.project.id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="thesis-defense-screen" class="acd-defense">
        <div class="acd-defense__hall">
          <div class="acd-defense__tools">
            <.link
              id="thesis-defense-back"
              navigate={~p"/academy"}
              class="acd-defense__exit"
            >
              ← покинуть зал Совета
            </.link>
            <button
              id="thesis-defense-refresh"
              type="button"
              phx-click="refresh"
              class="acd-defense__refresh"
            >
              сверить протокол
            </button>
          </div>

          <header class="acd-protocol-cover">
            <span class="acd-protocol-cover__hinge" aria-hidden="true"></span>
            <span class="acd-protocol-cover__crest" aria-hidden="true">A</span>
            <div class="acd-protocol-cover__head">
              <div>
                <p class="acd-protocol-cover__kicker">
                  Академия наук · открытая защита
                </p>
                <h1>{@state.project.title}</h1>
                <p class="acd-protocol-cover__copy">
                  Кандидат: <strong>{@state.candidate.name}</strong>. Любой
                  горожанин может наблюдать за протоколом; право голоса остаётся только у назначенной комиссии.
                </p>
              </div>
              <span
                id="thesis-defense-phase"
                class={["acd-phase-seal", phase_class(@state)]}
              >
                {phase_label(@state)}
              </span>
            </div>
          </header>

          <div
            :if={@error}
            id="thesis-defense-error"
            class="acd-red-ink"
          >
            {@error}
          </div>

          <section class="acd-dossier-grid">
            <article class="acd-dossier">
              <p class="acd-dossier__kicker">дело Академии</p>
              <dl class="acd-dossier__facts">
                <div>
                  <dt>Открытие слушания</dt>
                  <dd id="thesis-defense-opens-at">
                    {format_time(@state.opens_at)}
                  </dd>
                </div>
                <div>
                  <dt>Закрытие протокола</dt>
                  <dd id="thesis-defense-closes-at">
                    {format_time(@state.closes_at)}
                  </dd>
                </div>
                <div>
                  <dt>Подано голосов</dt>
                  <dd id="thesis-defense-vote-count">
                    {@state.votes_cast} / 3
                  </dd>
                </div>
                <div>
                  <dt>Номер дела</dt>
                  <dd id="thesis-project-id" class="acd-dossier__id">
                    {@state.project.id}
                  </dd>
                </div>
              </dl>
              <p class="acd-dossier__note">
                {phase_copy(@state)}
              </p>
            </article>

            <article class="acd-verdict-card">
              <span class="acd-verdict-card__wax" aria-hidden="true">✦</span>
              <p class="acd-verdict-card__kicker">вердикт</p>
              <%= if terminal?(@state.project.defense_state) do %>
                <h2 id="thesis-defense-outcome">
                  {outcome_label(@state.project.defense_state)}
                </h2>
                <p>
                  Решение зафиксировано Академией. Принятый тезис получает публикацию и открывает путь к профессорству.
                </p>
              <% else %>
                <h2 id="thesis-defense-pending">
                  Решение ожидается
                </h2>
                <p>
                  Итог появляется только после полной комиссии и закрытия окна слушания. Неполный протокол продлевается,
                  а не превращается в автоматическое одобрение.
                </p>
              <% end %>
            </article>
          </section>

          <section class="acd-panel-table">
            <div class="acd-panel-table__head">
              <div>
                <p>комиссия</p>
                <h2>Назначенные профессора</h2>
              </div>
              <span>{@state.votes_cast} зарегистрировано</span>
            </div>

            <p
              :if={not @state.commission_ready?}
              id="thesis-commission-unavailable"
              class="acd-panel-table__warning"
            >
              Комиссия ещё не укомплектована тремя активными профессорами. Защита остаётся открытой, но решение не будет принято без полного состава.
            </p>

            <ul id="thesis-defense-panel" class="acd-panel">
              <li
                :for={panelist <- @state.panel}
                id={"thesis-panel-#{panelist.character.id}"}
                class="acd-panelist"
              >
                <span class="acd-panelist__portrait" aria-hidden="true">
                  {String.first(panelist.character.name)}
                </span>
                <p class="acd-panelist__name">{panelist.character.name}</p>
                <p class="acd-panelist__role">
                  {role_label(panelist.role)}
                </p>
                <p class="acd-panelist__vote">{vote_label(panelist.vote)}</p>
              </li>
            </ul>
          </section>

          <section
            :if={@state.can_vote?}
            id="thesis-vote-controls"
            class="acd-ballot"
          >
            <span class="acd-ballot__clip" aria-hidden="true"></span>
            <p class="acd-ballot__kicker">ваш голос комиссии</p>
            <h2>Занесите решение в протокол</h2>
            <p class="acd-ballot__copy">
              Голос необратим. Сервер сверит ваш профессорский статус, состав комиссии и окно слушания перед сохранением.
            </p>
            <div class="acd-ballot__choices">
              <button
                id="thesis-vote-accept"
                type="button"
                phx-click="vote"
                phx-value-vote="accept"
                class="acd-vote-button acd-vote-button--accept"
              >
                Принять
              </button>
              <button
                id="thesis-vote-revisions"
                type="button"
                phx-click="vote"
                phx-value-vote="accept_with_revisions"
                class="acd-vote-button acd-vote-button--revise"
              >
                Принять с правками
              </button>
              <button
                id="thesis-vote-reject"
                type="button"
                phx-click="vote"
                phx-value-vote="reject"
                class="acd-vote-button acd-vote-button--reject"
              >
                Отклонить
              </button>
            </div>
          </section>

          <section
            :if={@state.attempt_history != []}
            id="thesis-defense-history"
            class="acd-history-ledger"
          >
            <p class="acd-history-ledger__title">предыдущие слушания</p>
            <ul>
              <li :for={attempt <- @state.attempt_history}>
                <span>{history_outcome_label(attempt)}</span>
                <time>{Map.get(attempt, "resolved_at", "—")}</time>
              </li>
            </ul>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_defense(socket, project_id) do
    case Play.thesis_defense_state(socket.assigns.current_scope.character, project_id) do
      {:ok, state} ->
        socket |> assign(:error, nil) |> assign(:state, state)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Эта защита недоступна из текущего города или мира.")
        |> push_navigate(to: ~p"/academy")
    end
  end

  defp phase_label(%{project: %{defense_state: state}})
       when state in [:accepted, :accepted_with_revisions, :rejected],
       do: outcome_label(state)

  defp phase_label(%{opens_at: opens_at}) when is_struct(opens_at, DateTime) do
    if DateTime.compare(DateTime.utc_now(), opens_at) == :lt, do: "назначена", else: "слушание"
  end

  defp phase_label(_defense), do: "ожидание"

  defp phase_class(%{project: %{defense_state: state}})
       when state in [:accepted, :accepted_with_revisions],
       do: "is-accepted"

  defp phase_class(%{project: %{defense_state: :rejected}}),
    do: "is-rejected"

  defp phase_class(_defense), do: "is-pending"

  defp phase_copy(%{project: %{defense_state: state}})
       when state in [:accepted, :accepted_with_revisions],
       do: "Тезис опубликован в реестре Академии; академическая карьера кандидата подтверждена."

  defp phase_copy(%{project: %{defense_state: :rejected}}),
    do:
      "Вторая неудачная защита закрыла путь к профессорскому назначению, сохранив остальные академические заслуги кандидата."

  defp phase_copy(%{commission_ready?: false}),
    do:
      "Академия ждёт полного состава комиссии. Никакой вердикт не выводится из пустого или неполного голосования."

  defp phase_copy(%{opens_at: opens_at}) when is_struct(opens_at, DateTime) do
    if DateTime.compare(DateTime.utc_now(), opens_at) == :lt do
      "Комиссия сформирована. До открытия слушания протокол доступен только для чтения."
    else
      "Слушание идёт по времени мира. После закрытия окна работник Академии проверит полный протокол."
    end
  end

  defp phase_copy(_defense), do: "Защита ожидает назначения времени и комиссии."

  defp terminal?(state), do: state in [:accepted, :accepted_with_revisions, :rejected]

  defp outcome_label(:accepted), do: "Принято"
  defp outcome_label(:accepted_with_revisions), do: "Принято с правками"
  defp outcome_label(:rejected), do: "Отклонено"
  defp outcome_label(_state), do: "Ожидает решения"

  defp role_label(:advisor), do: "наставник"
  defp role_label(:panelist), do: "член комиссии"
  defp role_label(_role), do: "комиссия"

  defp vote_label(nil), do: "Голос ещё не внесён"
  defp vote_label(%{"vote" => "accept"}), do: "Голос: принять"
  defp vote_label(%{"vote" => "accept_with_revisions"}), do: "Голос: принять с правками"
  defp vote_label(%{"vote" => "reject"}), do: "Голос: отклонить"
  defp vote_label(_vote), do: "Голос в протоколе"

  defp history_outcome_label(%{"outcome" => "reject"}), do: "Отклонено — назначена переработка"
  defp history_outcome_label(%{"outcome" => "accept"}), do: "Принято"
  defp history_outcome_label(%{"outcome" => "accept_with_revisions"}), do: "Принято с правками"
  defp history_outcome_label(_attempt), do: "Решение комиссии"

  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "не назначено"

  defp error_message(:academy_location_unavailable), do: "Защиту можно посещать только из города."
  defp error_message(:thesis_vote_unavailable), do: "Ваш голос сейчас недоступен."
  defp error_message(:thesis_defense_not_found), do: "Защита не найдена."
  defp error_message(%Ecto.Changeset{}), do: "Академия отклонила это действие. Обновите протокол."
  defp error_message(_reason), do: "Не удалось обновить защиту."
end
