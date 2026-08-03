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
    assigns =
      assigns
      |> assign(:ready_count, Enum.count(assigns.members, &member_ready?/1))
      |> assign(:member_count, length(assigns.members))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="party-screen" class="pty-scene">
        <div class="pty-shell">
          <.link id="party-back-to-map" navigate={~p"/map"} class="pty-exit">
            ← На карту
          </.link>

          <header class="pty-banner">
            <span class="pty-banner__crest">◆</span>
            <p class="pty-banner__eyebrow">Отряд · {location_name(@location)}</p>
            <h1 class="pty-banner__name">{if @party, do: @party.name, else: "Путники"}</h1>
          </header>

          <div :if={@error} id="party-error" class="pty-notice pty-notice--error">
            <span>☒</span> {@error}
          </div>

          <section :if={is_nil(@party)} id="party-create" class="pty-empty">
            <p class="pty-empty__glyph">☾</p>
            <h2 class="pty-empty__title">Вы путешествуете в одиночку</h2>
            <p class="pty-empty__text">
              Соберите спутников у одного костра. Лидер приглашает только путников рядом, а
              каждый отвечает за себя.
            </p>
            <.form
              for={@create_form}
              id="party-create-form"
              phx-submit="create"
              class="pty-form"
            >
              <.input
                field={@create_form[:name]}
                type="text"
                label="Имя отряда"
                placeholder="Вольные путники"
              />
              <button id="party-create-submit" type="submit" class="pty-btn pty-btn--gold">
                Собрать отряд
              </button>
            </.form>
          </section>

          <section :if={@party} id="party-active" class="pty-charter">
            <p class="pty-charter__folio">
              Походный устав · {location_name(@location)}
            </p>
            <section class="pty-readiness">
              <div class="pty-readiness__seal" aria-hidden="true">✦</div>
              <div class="pty-readiness__copy">
                <span class="pty-readiness__label">Готовность к экспедиции</span>
                <strong>{@ready_count} из {@member_count}</strong>
                <p>
                  Каждый путник ставит собственную печать. В глубину отряд входит только вместе.
                </p>
              </div>
            </section>

            <ul id="party-members" class="pty-members">
              <li
                :for={membership <- @members}
                id={"party-member-#{membership.character_id}"}
                class="pty-card"
              >
                <span class="pty-face-token" aria-hidden="true">
                  {member_initial(membership.character.name)}
                </span>
                <div class="pty-card__body">
                  <div class="pty-card__top">
                    <h3 class="pty-card__name">
                      {membership.character.name}
                      <span
                        :if={@party.leader_character_id == membership.character_id}
                        class="pty-card__crown"
                        title="лидер отряда"
                      >
                        ✦
                      </span>
                    </h3>
                    <span class="pty-card__lvl">ур. {membership.character.level}</span>
                  </div>
                  <span class="pty-card__class">{party_role_label(membership.role)}</span>
                  <div class="pty-card__chips">
                    <span class={[
                      "pty-tag",
                      if(member_ready?(membership), do: "pty-tag--good", else: "pty-tag--warn")
                    ]}>
                      {if member_ready?(membership), do: "печать поставлена", else: "не готов"}
                    </span>
                  </div>
                </div>
              </li>
            </ul>

            <div class="pty-command">
              <button
                :if={@self_ready?}
                id="party-mark-unready"
                type="button"
                phx-click="ready"
                phx-value-value="false"
                class="pty-btn pty-btn--ghost"
              >
                Снять печать
              </button>
              <button
                :if={not @self_ready?}
                id="party-mark-ready"
                type="button"
                phx-click="ready"
                phx-value-value="true"
                class="pty-btn pty-btn--gold"
              >
                Поставить печать готовности
              </button>
              <button
                :if={@leader? and is_nil(@active_expedition)}
                id="party-start-expedition"
                type="button"
                phx-click="start_expedition"
                class="pty-btn pty-btn--gold"
              >
                Начать экспедицию
              </button>
              <.link
                :if={@active_expedition}
                id="party-open-expedition"
                navigate={~p"/dungeon"}
                class="pty-btn pty-btn--gold"
              >
                Открыть экспедицию
              </.link>
              <button
                id="party-leave"
                type="button"
                phx-click="leave"
                class="pty-leave"
              >
                Покинуть отряд
              </button>
            </div>

            <section class="pty-loot">
              <h2 class="pty-loot__title">Делёж добычи</h2>
              <div id="party-loot-policies" class="pty-loot__opts">
                <button
                  :for={{label, value} <- @loot_policies}
                  id={"party-loot-#{value}"}
                  type="button"
                  phx-click="loot_policy"
                  phx-value-value={value}
                  disabled={not @leader?}
                  class={[
                    "pty-loot__opt",
                    @loot_policy == value && "is-on"
                  ]}
                >
                  {label}
                </button>
              </div>
              <p class="pty-loot__desc">{loot_policy_description(@loot_policy)}</p>
              <p class="pty-loot__xp">
                Это договорённость отряда, а не невидимый замок: доступный трофей технически
                может взять любой участник.
              </p>
            </section>

            <section :if={@leader?} class="pty-invite">
              <div class="pty-invite__head">
                <h2 class="pty-invite__title">Позвать к костру</h2>
                <span class="pty-invite__place">{location_name(@location)}</span>
              </div>
              <.form
                :if={@invite_options != []}
                for={@invite_form}
                id="party-invite-form"
                phx-submit="invite"
                class="pty-form"
              >
                <.input
                  field={@invite_form[:character_id]}
                  type="select"
                  label="Путники рядом"
                  prompt="Выберите спутника"
                  options={@invite_options}
                />
                <button id="party-send-invite" type="submit" class="pty-btn pty-btn--ghost">
                  Отправить приглашение
                </button>
              </.form>
              <p :if={@invite_options == []} class="pty-pending__empty">
                Рядом нет свободных путников.
              </p>
            </section>
          </section>

          <section
            :if={@pending_invitations != []}
            id="party-invitations"
            class="pty-invite pty-invite--incoming"
          >
            <div class="pty-invite__head">
              <h2 class="pty-invite__title">Письма у костра</h2>
              <span class="pty-invite__place">ждут ответа</span>
            </div>
            <ul class="pty-pending">
              <li
                :for={invitation <- @pending_invitations}
                id={"party-invitation-#{invitation.id}"}
                class="pty-pending__row"
              >
                <div>
                  <strong class="pty-pending__name">{invitation.party.name}</strong>
                  <span class="pty-pending__note">зовёт {inviter_name(invitation)}</span>
                </div>
                <div class="pty-pending__actions">
                  <button
                    id={"party-accept-#{invitation.id}"}
                    type="button"
                    phx-click="accept"
                    phx-value-invitation-id={invitation.id}
                    class="pty-btn pty-btn--gold"
                  >
                    Принять
                  </button>
                  <button
                    id={"party-reject-#{invitation.id}"}
                    type="button"
                    phx-click="reject"
                    phx-value-invitation-id={invitation.id}
                    class="pty-btn pty-btn--ghost"
                  >
                    Отклонить
                  </button>
                </div>
              </li>
            </ul>
          </section>

          <button id="party-refresh" type="button" phx-click="refresh" class="pty-refresh">
            ↻ перечитать лист отряда
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
  defp member_initial(name), do: name |> String.trim() |> String.first() || "?"
  defp party_role_label(:leader), do: "предводитель"
  defp party_role_label(:member), do: "участник"
  defp party_role_label(_role), do: "участник"
  defp location_name(nil), do: "неизвестное место"
  defp location_name(location), do: location.name
  defp inviter_name(%{inviter_character: nil}), do: "неизвестный путник"
  defp inviter_name(%{inviter_character: inviter}), do: inviter.name
  defp loot_policy_description("leader"), do: "Лидер вписывает имя получателя рядом с трофеем."
  defp loot_policy_description("free_for_all"), do: "Кто первым поднял трофей, тот его и несёт."
  defp loot_policy_description(_policy), do: "Добыча переходит от одного участника к следующему."
  defp error_message(:travelling), do: "Нельзя приглашать спутников во время пути."
  defp error_message(:party_or_target_not_found), do: "Отряд или путник больше не доступны."
  defp error_message(:party_not_found), do: "Активный отряд не найден."
  defp error_message(:not_party_leader), do: "Экспедицию может начать только лидер."

  defp error_message(_reason),
    do: "Команда отряда не выполнена: проверьте состав, готовность и место."
end
