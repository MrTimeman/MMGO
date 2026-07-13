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
      <main id="thesis-defense-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-5xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="thesis-defense-back"
              navigate={~p"/academy"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← В Академию
            </.link>
            <button
              id="thesis-defense-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200 transition hover:border-stone-400"
            >
              Обновить протокол
            </button>
          </div>

          <header class="overflow-hidden rounded-2xl border border-violet-400/30 bg-gradient-to-br from-violet-950/45 via-stone-950 to-sky-950/30 p-7 shadow-2xl">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="max-w-3xl">
                <p class="text-xs font-semibold uppercase tracking-[0.25em] text-violet-200/75">
                  Академия наук · открытая защита
                </p>
                <h1 class="mt-2 font-serif text-3xl text-violet-50">{@state.project.title}</h1>
                <p class="mt-3 text-sm leading-6 text-stone-300">
                  Кандидат: <span class="font-semibold text-stone-100">{@state.candidate.name}</span>. Любой
                  горожанин может наблюдать за протоколом; право голоса остаётся только у назначенной комиссии.
                </p>
              </div>
              <span
                id="thesis-defense-phase"
                class={[
                  "rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em]",
                  phase_class(@state)
                ]}
              >
                {phase_label(@state)}
              </span>
            </div>
          </header>

          <div
            :if={@error}
            id="thesis-defense-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section class="grid gap-4 lg:grid-cols-[1.45fr_1fr]">
            <article class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg">
              <p class="text-xs uppercase tracking-[0.2em] text-stone-500">дело Академии</p>
              <dl class="mt-4 grid gap-4 text-sm sm:grid-cols-2">
                <div>
                  <dt class="text-stone-500">Открытие слушания</dt>
                  <dd id="thesis-defense-opens-at" class="mt-1 text-stone-100">
                    {format_time(@state.opens_at)}
                  </dd>
                </div>
                <div>
                  <dt class="text-stone-500">Закрытие протокола</dt>
                  <dd id="thesis-defense-closes-at" class="mt-1 text-stone-100">
                    {format_time(@state.closes_at)}
                  </dd>
                </div>
                <div>
                  <dt class="text-stone-500">Подано голосов</dt>
                  <dd id="thesis-defense-vote-count" class="mt-1 text-stone-100">
                    {@state.votes_cast} / 3
                  </dd>
                </div>
                <div>
                  <dt class="text-stone-500">Номер дела</dt>
                  <dd id="thesis-project-id" class="mt-1 break-all font-mono text-xs text-stone-400">
                    {@state.project.id}
                  </dd>
                </div>
              </dl>
              <p class="mt-5 border-t border-stone-700 pt-4 text-sm leading-6 text-stone-300">
                {phase_copy(@state)}
              </p>
            </article>

            <article class="rounded-2xl border border-sky-400/20 bg-sky-950/15 p-6 shadow-lg">
              <p class="text-xs uppercase tracking-[0.2em] text-sky-200/70">вердикт</p>
              <%= if terminal?(@state.project.defense_state) do %>
                <h2 id="thesis-defense-outcome" class="mt-2 font-serif text-2xl text-sky-100">
                  {outcome_label(@state.project.defense_state)}
                </h2>
                <p class="mt-3 text-sm leading-6 text-stone-300">
                  Решение зафиксировано Академией. Принятый тезис получает публикацию и открывает путь к профессорству.
                </p>
              <% else %>
                <h2 id="thesis-defense-pending" class="mt-2 font-serif text-2xl text-sky-100">
                  Решение ожидается
                </h2>
                <p class="mt-3 text-sm leading-6 text-stone-300">
                  Итог появляется только после полной комиссии и закрытия окна слушания. Неполный протокол продлевается,
                  а не превращается в автоматическое одобрение.
                </p>
              <% end %>
            </article>
          </section>

          <section class="rounded-2xl border border-violet-400/20 bg-stone-900/80 p-6 shadow-lg">
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-violet-200/70">комиссия</p>
                <h2 class="mt-1 font-serif text-2xl text-violet-50">Назначенные профессора</h2>
              </div>
              <span class="text-sm text-stone-400">{@state.votes_cast} зарегистрировано</span>
            </div>

            <p
              :if={not @state.commission_ready?}
              id="thesis-commission-unavailable"
              class="mt-4 rounded-lg border border-amber-400/30 bg-amber-950/20 px-4 py-3 text-sm text-amber-100"
            >
              Комиссия ещё не укомплектована тремя активными профессорами. Защита остаётся открытой, но решение не будет принято без полного состава.
            </p>

            <ul id="thesis-defense-panel" class="mt-5 grid gap-3 md:grid-cols-3">
              <li
                :for={panelist <- @state.panel}
                id={"thesis-panel-#{panelist.character.id}"}
                class="rounded-xl border border-stone-700 bg-stone-950/65 p-4"
              >
                <p class="font-medium text-stone-100">{panelist.character.name}</p>
                <p class="mt-1 text-xs uppercase tracking-[0.14em] text-stone-500">
                  {role_label(panelist.role)}
                </p>
                <p class="mt-4 text-sm text-stone-300">{vote_label(panelist.vote)}</p>
              </li>
            </ul>
          </section>

          <section
            :if={@state.can_vote?}
            id="thesis-vote-controls"
            class="rounded-2xl border border-emerald-400/25 bg-emerald-950/15 p-6 shadow-lg"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">ваш голос комиссии</p>
            <h2 class="mt-1 font-serif text-2xl text-emerald-50">Занесите решение в протокол</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Голос необратим. Сервер сверит ваш профессорский статус, состав комиссии и окно слушания перед сохранением.
            </p>
            <div class="mt-5 grid gap-3 sm:grid-cols-3">
              <button
                id="thesis-vote-accept"
                type="button"
                phx-click="vote"
                phx-value-vote="accept"
                class="rounded-lg bg-emerald-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-emerald-200"
              >
                Принять
              </button>
              <button
                id="thesis-vote-revisions"
                type="button"
                phx-click="vote"
                phx-value-vote="accept_with_revisions"
                class="rounded-lg border border-amber-300/50 bg-amber-950/25 px-4 py-3 text-sm font-semibold text-amber-100 transition hover:bg-amber-950/50"
              >
                Принять с правками
              </button>
              <button
                id="thesis-vote-reject"
                type="button"
                phx-click="vote"
                phx-value-vote="reject"
                class="rounded-lg border border-rose-300/50 bg-rose-950/25 px-4 py-3 text-sm font-semibold text-rose-100 transition hover:bg-rose-950/50"
              >
                Отклонить
              </button>
            </div>
          </section>

          <section
            :if={@state.attempt_history != []}
            id="thesis-defense-history"
            class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-stone-500">предыдущие слушания</p>
            <ul class="mt-4 space-y-2 text-sm text-stone-300">
              <li
                :for={attempt <- @state.attempt_history}
                class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-stone-700/80 bg-stone-950/50 px-4 py-3"
              >
                <span>{history_outcome_label(attempt)}</span>
                <span class="text-xs text-stone-500">{Map.get(attempt, "resolved_at", "—")}</span>
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
       do: "border-emerald-300/45 bg-emerald-950/35 text-emerald-100"

  defp phase_class(%{project: %{defense_state: :rejected}}),
    do: "border-rose-300/45 bg-rose-950/35 text-rose-100"

  defp phase_class(_defense), do: "border-violet-300/40 bg-violet-950/35 text-violet-100"

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
