defmodule MMGOWeb.PartyLive do
  @moduledoc """
  Scoped party, invitation, readiness, and expedition lobby.
  """
  use MMGOWeb, :live_view

  alias MMGO.{Parties, Play}

  @loot_policies [
    {"По кругу", "round_robin"},
    {"Решает лидер", "leader"},
    {"Первый взял", "free_for_all"}
  ]

  @impl true
  def mount(_params, _session, socket),
    do: load_party(socket, socket.assigns.current_scope.character)

  @impl true
  def handle_event("create", %{"party_create" => attrs}, socket) do
    case Play.create_party(socket.assigns.character, attrs) do
      {:ok, _state} -> {:noreply, socket |> put_flash(:info, "Отряд создан.") |> refresh_party()}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("invite", %{"party_invite" => %{"character_id" => character_id}}, socket) do
    case Play.invite_to_party(socket.assigns.character, character_id) do
      {:ok, _state} ->
        {:noreply, socket |> put_flash(:info, "Приглашение отправлено.") |> refresh_party()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("accept", %{"invitation-id" => invitation_id}, socket) do
    case Play.accept_party_invitation(socket.assigns.character, invitation_id) do
      {:ok, _state} ->
        {:noreply, socket |> put_flash(:info, "Вы вступили в отряд.") |> refresh_party()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("reject", %{"invitation-id" => invitation_id}, socket) do
    case Play.reject_party_invitation(socket.assigns.character, invitation_id) do
      {:ok, _state} ->
        {:noreply, socket |> put_flash(:info, "Приглашение отклонено.") |> refresh_party()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("ready", %{"value" => value}, socket) do
    case Play.set_party_ready(socket.assigns.character, value == "true") do
      {:ok, _state} -> {:noreply, refresh_party(socket)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("loot_policy", %{"value" => policy}, socket) do
    case Play.set_party_loot_policy(socket.assigns.character, policy) do
      {:ok, _state} -> {:noreply, refresh_party(socket)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("leave", _params, socket) do
    case Play.leave_party(socket.assigns.character) do
      {:ok, _state} ->
        {:noreply, socket |> put_flash(:info, "Вы покинули отряд.") |> refresh_party()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("start_expedition", _params, socket) do
    case Play.start_party_expedition(socket.assigns.character) do
      {:ok, %{expedition: _expedition}} -> {:noreply, push_navigate(socket, to: ~p"/dungeon")}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_party(socket)}

  @impl true
  def handle_info({:party_updated, _party_id}, socket), do: {:noreply, refresh_party(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="party-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="party-back-to-map" navigate={~p"/map"} class="map-back-link">← Карта мира</.link>
          <header class="rounded-xl border border-cyan-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-cyan-300/70">
              отряд · {location_name(@location)}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-cyan-100">Путники</h1>
          </header>

          <div
            :if={@error}
            id="party-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section
            :if={is_nil(@party)}
            id="party-create"
            class="rounded-xl border border-cyan-500/25 bg-cyan-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-cyan-100">Собрать отряд</h2>
            <p class="mt-2 text-sm text-stone-400">
              Лидер приглашает только реальных путников рядом; каждый принимает приглашение сам.
            </p>
            <.form
              for={@create_form}
              id="party-create-form"
              phx-submit="create"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <.input
                field={@create_form[:name]}
                type="text"
                label="Название"
                placeholder="Вольные делверы"
              />
              <button
                id="party-create-submit"
                type="submit"
                class="mb-4 rounded-md bg-cyan-300 px-4 py-3 font-semibold text-stone-950 hover:bg-cyan-200"
              >
                Создать
              </button>
            </.form>
          </section>

          <section
            :if={@party}
            id="party-active"
            class="rounded-xl border border-cyan-500/25 bg-cyan-950/15 p-6"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.18em] text-cyan-300/70">активный отряд</p>
                <h2 class="mt-1 font-serif text-2xl text-cyan-100">{@party.name}</h2>
              </div>
              <button
                id="party-leave"
                type="button"
                phx-click="leave"
                class="rounded border border-stone-500 px-3 py-2 text-sm text-stone-200"
              >
                Покинуть
              </button>
            </div>

            <ul id="party-members" class="mt-5 space-y-2">
              <li
                :for={membership <- @members}
                id={"party-member-#{membership.character_id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
              >
                <div>
                  <span class="font-medium text-stone-100">{membership.character.name}</span><span class="ml-2 text-stone-400">ур. {membership.character.level} · {membership.role}</span>
                </div>
                <span class={
                  if member_ready?(membership), do: "text-emerald-200", else: "text-amber-200"
                }>
                  {if member_ready?(membership), do: "готов", else: "не готов"}
                </span>
              </li>
            </ul>

            <div class="mt-5 flex flex-wrap gap-2">
              <button
                :if={@self_ready?}
                id="party-mark-unready"
                type="button"
                phx-click="ready"
                phx-value-value="false"
                class="rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
              >
                Снять готовность
              </button>
              <button
                :if={not @self_ready?}
                id="party-mark-ready"
                type="button"
                phx-click="ready"
                phx-value-value="true"
                class="rounded bg-emerald-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Готов к экспедиции
              </button>
              <button
                :if={@leader? and is_nil(@active_expedition)}
                id="party-start-expedition"
                type="button"
                phx-click="start_expedition"
                class="rounded bg-cyan-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Начать экспедицию
              </button>
              <.link
                :if={@active_expedition}
                id="party-open-expedition"
                navigate={~p"/dungeon"}
                class="rounded bg-cyan-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Открыть экспедицию
              </.link>
            </div>

            <div :if={@leader?} class="mt-6 grid gap-4 md:grid-cols-2">
              <.form
                :if={@invite_options != []}
                for={@invite_form}
                id="party-invite-form"
                phx-submit="invite"
              >
                <h3 class="font-serif text-lg text-cyan-100">Позвать спутника</h3>
                <.input
                  field={@invite_form[:character_id]}
                  type="select"
                  label="Рядом"
                  prompt="Выберите путника"
                  options={@invite_options}
                />
                <button
                  id="party-send-invite"
                  type="submit"
                  class="rounded border border-cyan-300/50 px-3 py-2 text-sm text-cyan-100"
                >
                  Пригласить
                </button>
              </.form>
              <div>
                <h3 class="font-serif text-lg text-cyan-100">Делёж добычи</h3>
                <div id="party-loot-policies" class="mt-3 flex flex-wrap gap-2">
                  <button
                    :for={{label, value} <- @loot_policies}
                    id={"party-loot-#{value}"}
                    type="button"
                    phx-click="loot_policy"
                    phx-value-value={value}
                    class={
                      if @loot_policy == value,
                        do: "rounded bg-cyan-300 px-3 py-2 text-sm font-semibold text-stone-950",
                        else: "rounded border border-stone-600 px-3 py-2 text-sm text-stone-200"
                    }
                  >
                    {label}
                  </button>
                </div>
              </div>
            </div>
          </section>

          <section
            :if={@pending_invitations != []}
            id="party-invitations"
            class="rounded-xl border border-emerald-500/25 bg-emerald-950/15 p-6"
          >
            <h2 class="font-serif text-xl text-emerald-100">Приглашения</h2>
            <article
              :for={invitation <- @pending_invitations}
              id={"party-invitation-#{invitation.id}"}
              class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
            >
              <span>{invitation.party.name} · зовёт {inviter_name(invitation)}</span>
              <div class="flex gap-2">
                <button
                  id={"party-accept-#{invitation.id}"}
                  type="button"
                  phx-click="accept"
                  phx-value-invitation-id={invitation.id}
                  class="rounded bg-emerald-300 px-3 py-2 font-semibold text-stone-950"
                >
                  Принять
                </button>
                <button
                  id={"party-reject-#{invitation.id}"}
                  type="button"
                  phx-click="reject"
                  phx-value-invitation-id={invitation.id}
                  class="rounded border border-stone-600 px-3 py-2 text-stone-200"
                >
                  Отклонить
                </button>
              </div>
            </article>
          </section>

          <button
            id="party-refresh"
            type="button"
            phx-click="refresh"
            class="text-sm text-cyan-200 underline decoration-cyan-500/40 underline-offset-4"
          >
            Обновить отряд
          </button>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_party(socket, character) do
    case Play.party_state(character) do
      {:ok, state} ->
        {:ok,
         socket |> assign(:page_title, "Отряд") |> assign(:error, nil) |> assign_party(state)}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/map")}
    end
  end

  defp refresh_party(socket) do
    case Play.party_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_party(state)
      {:error, _reason} -> assign(socket, :error, "Состояние отряда сейчас недоступно.")
    end
  end

  defp assign_party(socket, state) do
    member_ids = MapSet.new(Enum.map(state.members, & &1.character_id))
    self_membership = Enum.find(state.members, &(&1.character_id == state.character.id))

    socket
    |> subscribe_to_party_updates(state)
    |> assign(:character, state.character)
    |> assign(:location, state.location)
    |> assign(:party, state.party)
    |> assign(:members, state.members)
    |> assign(:pending_invitations, state.pending_invitations)
    |> assign(:active_expedition, state.active_expedition)
    |> assign(:loot_policy, state.loot_policy)
    |> assign(:loot_policies, @loot_policies)
    |> assign(
      :leader?,
      not is_nil(state.party) and state.party.leader_character_id == state.character.id
    )
    |> assign(:self_ready?, not is_nil(self_membership) and member_ready?(self_membership))
    |> assign(
      :invite_options,
      state.nearby_characters
      |> Enum.reject(&MapSet.member?(member_ids, &1.id))
      |> Enum.map(&{&1.name, &1.id})
    )
    |> assign(:create_form, to_form(%{"name" => ""}, as: :party_create))
    |> assign(:invite_form, to_form(%{"character_id" => ""}, as: :party_invite))
  end

  defp subscribe_to_party_updates(socket, state) do
    socket
    |> replace_subscription(:character_update_topic, Parties.character_topic(state.character.id))
    |> replace_subscription(
      :party_update_topic,
      if(state.party, do: Parties.party_topic(state.party.id), else: nil)
    )
  end

  defp replace_subscription(socket, assign_name, topic) do
    previous_topic = socket.assigns[assign_name]

    if connected?(socket) and previous_topic != topic do
      if is_binary(previous_topic) do
        Phoenix.PubSub.unsubscribe(MMGO.PubSub, previous_topic)
      end

      if is_binary(topic) do
        Phoenix.PubSub.subscribe(MMGO.PubSub, topic)
      end
    end

    assign(socket, assign_name, topic)
  end

  defp member_ready?(membership), do: Map.get(membership.metadata || %{}, "ready", true) == true
  defp location_name(nil), do: "неизвестное место"
  defp location_name(location), do: location.name
  defp inviter_name(%{inviter_character: nil}), do: "неизвестный путник"
  defp inviter_name(%{inviter_character: inviter}), do: inviter.name
  defp error_message(:travelling), do: "Нельзя приглашать спутников во время пути."
  defp error_message(:party_or_target_not_found), do: "Отряд или путник больше не доступны."
  defp error_message(:party_not_found), do: "Активный отряд не найден."
  defp error_message(:not_party_leader), do: "Экспедицию может начать только лидер."

  defp error_message(_reason),
    do: "Команда отряда не выполнена: проверьте состав, готовность и место."
end
