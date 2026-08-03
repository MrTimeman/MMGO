defmodule MMGOWeb.OrganizationsLive do
  @moduledoc """
  Player organizations (GDD §17), wired to the real `MMGO.Organizations`
  context through `MMGO.Play`.

  Map-first (GDD §5): organization business happens in a city, so mount gates on
  the scoped character's location. Three live actions share this module:

    * `:index` `/orgs`            — the registry: your organizations + invitations
    * `:new`   `/orgs/new`        — founding (shares the index's create form)
    * `:show`  `/orgs/:id[/:tab]` — one organization's members, roles, invites

  All authority derives from the scoped character; org/role/invitee ids from the
  client are validated against real ownership in `MMGO.Play`.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @kinds ~w(guild company council cult)

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case MMGOWeb.LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:page_title, "Организации")
         |> assign(:character, character)
         |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :show -> {:noreply, load_show(socket, params["id"])}
      _index_or_new -> {:noreply, load_index(socket)}
    end
  end

  # ------------------------------------------------------------------
  # Events
  # ------------------------------------------------------------------

  @impl true
  def handle_event("found", %{"organization" => %{"name" => name} = attrs}, socket) do
    kind = attrs["kind"] || "guild"

    case Play.found_organization(socket.assigns.character, kind, name) do
      {:ok, _result} ->
        {:noreply, socket |> assign(:error, nil) |> load_index()}

      {:error, _reason} ->
        {:noreply,
         assign(socket, :error, "Не удалось основать организацию — проверь название и вид.")}
    end
  end

  def handle_event("found", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("accept_invitation", %{"invitation_id" => id}, socket) do
    case Play.accept_org_invitation(socket.assigns.character, id) do
      {:ok, _membership} -> {:noreply, load_index(socket)}
      {:error, _reason} -> {:noreply, assign(socket, :error, "Приглашение уже недействительно.")}
    end
  end

  @impl true
  def handle_event("reject_invitation", %{"invitation_id" => id}, socket) do
    case Play.reject_org_invitation(socket.assigns.character, id) do
      {:ok, _invitation} -> {:noreply, load_index(socket)}
      {:error, _reason} -> {:noreply, load_index(socket)}
    end
  end

  @impl true
  def handle_event("join_open_organization", %{"organization_id" => id}, socket) do
    case Play.join_open_organization(socket.assigns.character, id) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы вступили в организацию по её открытому уставу.")
         |> assign(:error, nil)
         |> load_index()}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Вступить в эту организацию сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event("invite", %{"invite" => %{"handle" => handle, "role_id" => role_id}}, socket) do
    org = socket.assigns.organization

    case Play.invite_to_organization(socket.assigns.character, org.id, handle, role_id) do
      {:ok, _invitation} ->
        {:noreply, socket |> assign(:error, nil) |> load_show(org.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Не удалось пригласить — проверь позывной участника.")}
    end
  end

  @impl true
  def handle_event("add_role", %{"role" => attrs}, socket) do
    org = socket.assigns.organization

    case Play.add_organization_role(socket.assigns.character, org.id, attrs) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Новая роль добавлена в устав организации.")
         |> assign(:error, nil)
         |> load_show(org.id)}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Не удалось добавить роль. Название должно содержать 2–120 символов, а ранг — быть от 0 до 99."
         )}
    end
  end

  @impl true
  def handle_event("deposit_treasury", %{"treasury_deposit" => %{"amount" => amount}}, socket) do
    organization = socket.assigns.organization

    with {:ok, amount} <- parse_positive_amount(amount),
         {:ok, _state} <-
           Play.fund_organization_treasury(socket.assigns.character, organization.id, amount) do
      {:noreply,
       socket
       |> put_flash(:info, "Вклад поступил в казну организации.")
       |> assign(:error, nil)
       |> load_show(organization.id)}
    else
      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Не удалось внести вклад в казну.")}
    end
  end

  @impl true
  def handle_event("assign_treasury_share", %{"treasury_share" => params}, socket) do
    organization = socket.assigns.organization

    with {:ok, share_bps} <- parse_share_percent(params["percent"]),
         {:ok, _state} <-
           Play.assign_organization_treasury_share(
             socket.assigns.character,
             organization.id,
             params["character_id"],
             share_bps
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Доля в казне записана в реестр владения.")
       |> assign(:error, nil)
       |> load_show(organization.id)}
    else
      {:error, _reason} ->
        {:noreply,
         assign(socket, :error, "Долю можно задать целым числом от 0 до 100 процентов.")}
    end
  end

  @impl true
  def handle_event(
        "distribute_treasury_dividend",
        %{"treasury_dividend" => %{"amount" => amount}},
        socket
      ) do
    organization = socket.assigns.organization

    with {:ok, amount} <- parse_positive_amount(amount),
         {:ok, _state} <-
           Play.distribute_organization_treasury_dividend(
             socket.assigns.character,
             organization.id,
             amount
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Доход распределён по долям и записан проводками.")
       |> assign(:error, nil)
       |> load_show(organization.id)}
    else
      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Распределить доход по долям сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event(
        "withdraw_treasury",
        %{"treasury_withdrawal" => %{"handle" => handle, "amount" => amount}},
        socket
      ) do
    organization = socket.assigns.organization

    case parse_positive_amount(amount) do
      {:ok, parsed_amount} ->
        referendum? = treasury_referendum_required?(socket.assigns.treasury_policy, parsed_amount)

        case submit_treasury_withdrawal(
               socket.assigns.character,
               organization.id,
               handle,
               parsed_amount,
               referendum?
             ) do
          {:ok, _state} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               if(referendum?,
                 do: "Выплата вынесена на голосование участников.",
                 else: "Выплата из казны зафиксирована в реестре."
               )
             )
             |> assign(:error, nil)
             |> load_show(organization.id)}

          {:error, _reason} ->
            {:noreply,
             assign(
               socket,
               :error,
               if(referendum?,
                 do: "Не удалось вынести выплату на голосование.",
                 else: "Выплата из казны сейчас недоступна."
               )
             )}
        end

      {:error, _reason} ->
        {:noreply,
         assign(socket, :error, "Сумма выплаты должна быть положительным целым числом.")}
    end
  end

  @impl true
  def handle_event(
        "configure_leadership",
        %{"leadership" => %{"selection" => selection}},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.configure_organization_leadership(
           socket.assigns.character,
           organization.id,
           selection
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Правило выбора главы сохранено в уставе.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Изменить правило выбора главы сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event(
        "configure_membership",
        %{"membership" => %{"admission" => admission}},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.configure_organization_membership(
           socket.assigns.character,
           organization.id,
           admission
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Правило вступления сохранено в уставе.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Изменить правило вступления сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event(
        "configure_succession",
        %{"succession" => %{"on_leader_exit" => on_leader_exit}},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.configure_organization_succession(
           socket.assigns.character,
           organization.id,
           on_leader_exit
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Правило ухода главы сохранено в уставе.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Изменить правило ухода главы сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event(
        "configure_treasury_decision",
        %{"treasury_policy" => %{"decision" => decision}},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.configure_organization_treasury_decision(
           socket.assigns.character,
           organization.id,
           decision
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Правило расходования казны сохранено в уставе.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Изменить правило расходования казны сейчас нельзя.")}
    end
  end

  @impl true
  def handle_event(
        "configure_treasury_role_limit",
        %{"treasury_role_limit" => %{"role_id" => role_id, "limit" => limit}},
        socket
      ) do
    organization = socket.assigns.organization

    with {:ok, direct_payout_limit} <- parse_optional_nonnegative_amount(limit),
         {:ok, _state} <-
           Play.configure_organization_treasury_role_limit(
             socket.assigns.character,
             organization.id,
             role_id,
             direct_payout_limit
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Предел прямой выплаты для роли сохранён в уставе.")
       |> assign(:error, nil)
       |> load_show(organization.id)}
    else
      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Не удалось сохранить предел роли. Укажите целую сумму от нуля или оставьте поле пустым."
         )}
    end
  end

  @impl true
  def handle_event(
        "configure_fast_travel_toll",
        %{
          "fast_travel_toll" => %{
            "origin_location_id" => origin_location_id,
            "destination_location_id" => destination_location_id,
            "amount" => amount
          }
        },
        socket
      ) do
    organization = socket.assigns.organization

    with {:ok, amount} <- parse_nonnegative_amount(amount),
         {:ok, _state} <-
           Play.configure_organization_fast_travel_toll(
             socket.assigns.character,
             organization.id,
             origin_location_id,
             destination_location_id,
             amount
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Тариф маршрута сохранён в реестре организации.")
       |> assign(:error, nil)
       |> load_show(organization.id)}
    else
      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Не удалось сохранить тариф. Нужны разные связанные точки и целая сумма от нуля."
         )}
    end
  end

  @impl true
  def handle_event(
        "cast_treasury_vote",
        %{"proposal_id" => proposal_id, "vote" => vote},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.vote_for_organization_treasury(
           socket.assigns.character,
           organization.id,
           proposal_id,
           vote
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ваш голос по расходу казны записан в реестр.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Этот голос по расходу казны уже нельзя принять.")}
    end
  end

  @impl true
  def handle_event("propose_diplomacy", %{"diplomacy" => params}, socket) do
    organization = socket.assigns.organization

    case Play.propose_organization_diplomacy(
           socket.assigns.character,
           organization.id,
           params["target_organization_id"],
           params["kind"]
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Дипломатический запрос отправлен второй организации.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Этот дипломатический запрос сейчас недоступен.")}
    end
  end

  @impl true
  def handle_event(
        "respond_diplomacy",
        %{"proposal_id" => proposal_id, "decision" => decision},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.respond_to_organization_diplomacy(
           socket.assigns.character,
           organization.id,
           proposal_id,
           decision
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Дипломатический ответ закреплён в уставах обеих сторон.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Этот дипломатический запрос уже недействителен.")}
    end
  end

  @impl true
  def handle_event("nominate_leader", %{"candidate_id" => candidate_id}, socket) do
    organization = socket.assigns.organization

    case Play.nominate_organization_leader(
           socket.assigns.character,
           organization.id,
           candidate_id
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Кандидатура вынесена на голосование участников.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Эту кандидатуру нельзя вынести на голосование.")}
    end
  end

  @impl true
  def handle_event("appoint_leader", %{"candidate_id" => candidate_id}, socket) do
    organization = socket.assigns.organization

    case Play.appoint_organization_leader(
           socket.assigns.character,
           organization.id,
           candidate_id
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Основатель назначил нового главу организации.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Основатель сейчас не может назначить этого главу.")}
    end
  end

  @impl true
  def handle_event(
        "cast_leadership_vote",
        %{"proposal_id" => proposal_id, "vote" => vote},
        socket
      ) do
    organization = socket.assigns.organization

    case Play.vote_for_organization_leader(
           socket.assigns.character,
           organization.id,
           proposal_id,
           vote
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ваш голос записан в реестр организации.")
         |> assign(:error, nil)
         |> load_show(organization.id)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Этот голос уже нельзя принять.")}
    end
  end

  @impl true
  def handle_event("leave", _params, socket) do
    case Play.leave_organization(socket.assigns.character, socket.assigns.organization.id) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы покинули организацию.")
         |> push_navigate(to: ~p"/orgs")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Не удалось покинуть организацию.")}
    end
  end

  @impl true
  def handle_event("fast_travel", %{"destination-id" => destination_id}, socket) do
    case Play.use_organization_fast_travel(
           socket.assigns.character,
           socket.assigns.organization.id,
           destination_id
         ) do
      {:ok, _character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Организация открыла быстрый путь.")
         |> push_navigate(to: ~p"/map")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Этот быстрый путь сейчас недоступен.")}
    end
  end

  # ------------------------------------------------------------------
  # Render
  # ------------------------------------------------------------------

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="org-wrap">
        <.link navigate={~p"/map"} class="org-exit">&larr; к карте</.link>
        <.link navigate={~p"/orgs"} class="org-hall-nav">реестр организаций</.link>

        <h1 class="org-card-name">{@organization.name}</h1>
        <p class="org-card-creed">Устав · {kind_label(@organization.kind)}</p>

        <%= if @error do %>
          <p class="org-app-note" role="alert">{@error}</p>
        <% end %>

        <section id="org-roles" class="org-card">
          <h2 class="org-card-top">Роли</h2>
          <ul class="org-card-list">
            <li
              :for={role <- @organization.roles}
              id={"org-role-#{role.id}"}
              class="org-charter-clause"
            >
              <span>{role.title}</span>
              <span class="org-app-note">
                Ранг {role.rank} · {role_permissions_label(role.permissions)}
              </span>
            </li>
          </ul>
        </section>

        <section :if={@can_manage_roles?} id="org-role-management" class="org-card">
          <h2 class="org-card-top">Управление ролями</h2>
          <p class="org-app-note">
            Новые роли не могут превзойти ранг главы. Разрешения применяются сервером к каждому приглашению и маршруту.
          </p>
          <.form
            for={@role_form}
            id="org-role-form"
            phx-submit="add_role"
            class="org-app-actions"
          >
            <.input field={@role_form[:title]} type="text" label="Название роли" required />
            <.input
              field={@role_form[:rank]}
              type="number"
              label="Ранг (0–99)"
              min="0"
              max="99"
              required
            />
            <.input
              field={@role_form[:permissions]}
              type="select"
              label="Разрешения"
              multiple={true}
              options={role_permission_options()}
            />
            <button id="org-add-role" type="submit" class="org-btn">Добавить роль</button>
          </.form>
        </section>

        <section id="org-members" class="org-card">
          <h2 class="org-card-top">Участники</h2>
          <ul class="org-card-members">
            <li :for={m <- @organization.memberships}>
              {member_name(m)} — {role_title(m)}
            </li>
          </ul>
        </section>

        <section id="org-governance" class="org-card">
          <h2 class="org-card-top">Устав и выборы</h2>
          <p id="org-leadership-mode" class="org-app-note">
            Выбор главы: {leadership_selection_label(@leadership.selection)}
          </p>
          <p id="org-current-leader" class="org-app-note">
            Глава: {member_name(@leadership.leader)}
          </p>

          <.form
            :if={@leadership.can_configure?}
            for={@leadership_form}
            id="org-governance-form"
            phx-submit="configure_leadership"
            class="org-app-actions mt-4"
          >
            <.input
              field={@leadership_form[:selection]}
              type="select"
              label="Правило выбора главы"
              options={leadership_selection_options()}
            />
            <button id="org-save-leadership" type="submit" class="org-btn">
              Сохранить правило
            </button>
          </.form>

          <div class="mt-4 border-t border-stone-700 pt-4">
            <p id="org-membership-mode" class="org-app-note">
              Вступление: {membership_admission_label(@membership_policy.admission)}
            </p>
            <.form
              :if={@can_manage_roles?}
              for={@membership_form}
              id="org-membership-form"
              phx-submit="configure_membership"
              class="org-app-actions mt-3"
            >
              <.input
                field={@membership_form[:admission]}
                type="select"
                label="Правило вступления"
                options={membership_admission_options()}
              />
              <button id="org-save-membership" type="submit" class="org-btn org-btn--ghost">
                Сохранить правило вступления
              </button>
            </.form>
          </div>

          <div class="mt-4 border-t border-stone-700 pt-4">
            <p id="org-succession-mode" class="org-app-note">
              При уходе главы: {succession_label(@succession.on_leader_exit)}
            </p>
            <p :if={@succession.on_leader_exit == "vacant"} class="org-app-note mt-2">
              Вакантный пост не создаёт преемника автоматически: заполнить его можно только доступным правилом устава.
            </p>
            <.form
              :if={@can_manage_roles?}
              for={@succession_form}
              id="org-succession-form"
              phx-submit="configure_succession"
              class="org-app-actions mt-3"
            >
              <.input
                field={@succession_form[:on_leader_exit]}
                type="select"
                label="Правило ухода главы"
                options={succession_options()}
              />
              <button id="org-save-succession" type="submit" class="org-btn org-btn--ghost">
                Сохранить правило ухода
              </button>
            </.form>
          </div>

          <div class="mt-4 border-t border-stone-700 pt-4">
            <p id="org-treasury-decision-mode" class="org-app-note">
              Расходы казны: {treasury_decision_label(@treasury_policy.decision)}
            </p>
            <.form
              :if={@treasury_policy.can_configure?}
              for={@treasury_policy_form}
              id="org-treasury-policy-form"
              phx-submit="configure_treasury_decision"
              class="org-app-actions mt-3"
            >
              <.input
                field={@treasury_policy_form[:decision]}
                type="select"
                label="Правило расходов казны"
                options={treasury_decision_options()}
              />
              <button id="org-save-treasury-policy" type="submit" class="org-btn org-btn--ghost">
                Сохранить правило казны
              </button>
            </.form>

            <p id="org-treasury-actor-limit" class="org-app-note mt-3">
              Ваш предел прямой выплаты: {treasury_direct_payout_limit_label(
                @treasury_policy.actor_direct_payout_limit
              )}.
            </p>
            <ul id="org-treasury-role-limits" class="org-card-list mt-3">
              <li
                :for={role <- @treasury_policy.role_limits}
                id={"org-treasury-role-limit-#{role.id}"}
                class="org-charter-clause"
              >
                <span>{role.title}</span>
                <span class="org-app-note">
                  {treasury_direct_payout_limit_label(role.direct_payout_limit)}
                </span>
              </li>
            </ul>
            <.form
              :if={@treasury_policy.can_configure?}
              for={@treasury_role_limit_form}
              id="org-treasury-role-limit-form"
              phx-submit="configure_treasury_role_limit"
              class="org-app-actions mt-3"
            >
              <.input
                field={@treasury_role_limit_form[:role_id]}
                type="select"
                label="Роль"
                options={treasury_role_limit_options(@treasury_policy.role_limits)}
              />
              <.input
                field={@treasury_role_limit_form[:limit]}
                type="number"
                label="Предел прямой выплаты (◈; пусто = без предела)"
                min="0"
              />
              <button id="org-save-treasury-role-limit" type="submit" class="org-btn org-btn--ghost">
                Сохранить предел роли
              </button>
            </.form>
          </div>

          <%= if @leadership.open_election do %>
            <div id="org-open-election" class="mt-4 border-t border-stone-700 pt-4">
              <p id="org-election-candidate" class="org-app-note">
                Кандидат: {member_name(@leadership.open_election.candidate)}
              </p>
              <p id="org-election-tally" class="org-app-note">
                <%= if @leadership.open_election.weighted? do %>
                  Вес голосов: поддержка {@leadership.open_election.approve_weight}/ {@leadership.open_election.total_vote_weight}; отклонение {@leadership.open_election.reject_weight}/{@leadership.open_election.total_vote_weight};
                  для решения нужно {@leadership.open_election.required_vote_weight}.
                <% else %>
                  Голоса: {@leadership.open_election.votes_cast}/{@leadership.open_election.voter_count};
                  для решения нужно {@leadership.open_election.votes_needed}.
                <% end %>
              </p>
              <p :if={@leadership.open_election.weighted?} class="org-app-note">
                Ваш текущий вес: {@leadership.open_election.actor_vote_weight} б.п.
              </p>
              <div :if={@leadership.open_election.can_vote?} class="org-app-actions mt-3">
                <button
                  id="org-election-approve"
                  type="button"
                  class="org-btn"
                  phx-click="cast_leadership_vote"
                  phx-value-proposal_id={@leadership.open_election.id}
                  phx-value-vote="approve"
                >
                  Поддержать
                </button>
                <button
                  id="org-election-reject"
                  type="button"
                  class="org-btn org-btn--ghost"
                  phx-click="cast_leadership_vote"
                  phx-value-proposal_id={@leadership.open_election.id}
                  phx-value-vote="reject"
                >
                  Отклонить
                </button>
              </div>
              <p
                :if={not @leadership.open_election.can_vote?}
                id="org-election-vote-recorded"
                class="org-app-note mt-3"
              >
                Ваш голос уже учтён или вы не входили в состав участников на момент открытия выборов.
              </p>
            </div>
          <% else %>
            <div
              :if={@leadership.can_appoint?}
              id="org-founder-appointments"
              class="mt-4"
            >
              <p class="org-app-note">
                Устав оставляет назначение за основателем. Назначенный глава получает роль и полномочия сразу.
              </p>
              <div class="org-app-actions mt-3">
                <button
                  :for={member <- @leadership.candidate_memberships}
                  id={"org-appoint-#{member.character_id}"}
                  type="button"
                  class="org-btn"
                  phx-click="appoint_leader"
                  phx-value-candidate_id={member.character_id}
                >
                  Назначить: {member_name(member)}
                </button>
              </div>
            </div>
            <div :if={@leadership.can_nominate?} id="org-election-nominations" class="mt-4">
              <p class="org-app-note">Любой участник может вынести кандидатуру главы.</p>
              <div class="org-app-actions mt-3">
                <button
                  :for={member <- @leadership.candidate_memberships}
                  id={"org-nominate-#{member.character_id}"}
                  type="button"
                  class="org-btn org-btn--ghost"
                  phx-click="nominate_leader"
                  phx-value-candidate_id={member.character_id}
                >
                  Выдвинуть: {member_name(member)}
                </button>
              </div>
            </div>
          <% end %>
        </section>

        <section id="org-diplomacy" class="org-card">
          <h2 class="org-card-top">Дипломатия</h2>
          <p :if={@diplomacy.relationships == []} class="org-app-note">
            У организации пока нет закреплённых союзов или соперничеств.
          </p>
          <ul
            :if={@diplomacy.relationships != []}
            id="org-diplomacy-relationships"
            class="org-card-list"
          >
            <li :for={relationship <- @diplomacy.relationships} class="org-charter-clause">
              <span>{relationship.organization_name}</span>
              <span class="org-app-note">{diplomacy_kind_label(relationship.kind)}</span>
            </li>
          </ul>

          <.form
            :if={@can_manage_roles? and @diplomacy.available_targets != []}
            for={@diplomacy_form}
            id="org-diplomacy-form"
            phx-submit="propose_diplomacy"
            class="org-app-actions mt-4"
          >
            <.input
              field={@diplomacy_form[:target_organization_id]}
              type="select"
              label="Организация мира"
              options={diplomacy_target_options(@diplomacy.available_targets)}
            />
            <.input
              field={@diplomacy_form[:kind]}
              type="select"
              label="Отношение"
              options={diplomacy_kind_options()}
            />
            <button id="org-diplomacy-send" type="submit" class="org-btn org-btn--ghost">
              Отправить запрос
            </button>
          </.form>

          <div
            :for={request <- @diplomacy.incoming_requests}
            id={"org-diplomacy-request-#{request.id}"}
            class="mt-4 border-t border-stone-700 pt-4"
          >
            <p class="org-app-note">
              {request.source_organization_name} предлагает: {diplomacy_kind_label(
                request.relationship_kind
              )}.
            </p>
            <div :if={@can_manage_roles?} class="org-app-actions mt-3">
              <button
                id={"org-diplomacy-accept-#{request.id}"}
                type="button"
                class="org-btn"
                phx-click="respond_diplomacy"
                phx-value-proposal_id={request.id}
                phx-value-decision="accept"
              >
                Принять
              </button>
              <button
                id={"org-diplomacy-reject-#{request.id}"}
                type="button"
                class="org-btn org-btn--ghost"
                phx-click="respond_diplomacy"
                phx-value-proposal_id={request.id}
                phx-value-decision="reject"
              >
                Отклонить
              </button>
            </div>
          </div>
        </section>

        <section id="org-membership-actions" class="org-card">
          <h2 class="org-card-top">Ваше членство</h2>
          <button id="org-leave" type="button" class="org-btn org-btn--ghost" phx-click="leave">
            Покинуть организацию
          </button>
        </section>

        <section id="org-treasury" class="org-card">
          <p class="org-card-top">Казна организации</p>
          <p id="org-treasury-balance" class="mt-2 font-serif text-3xl text-amber-100">
            {@treasury_balance} ◈
          </p>
          <p class="org-app-note">
            Средства хранятся в общем реестре мира; каждое движение оставляет проводку.
          </p>
          <p :if={@treasury_recent_entry} id="org-treasury-last-entry" class="org-app-note">
            {treasury_entry_label(@treasury_recent_entry)}
          </p>

          <section id="org-treasury-ownership" class="mt-4 border-t border-stone-700 pt-4">
            <p class="org-app-note">
              Резерв организации: {format_share_bps(@treasury_ownership.organization_share_bps)}.
              Доли участников определяют экономический вес в долевом голосовании.
            </p>
            <ul id="org-treasury-shares" class="org-card-list mt-3">
              <li
                :for={member <- @treasury_ownership.members}
                id={"org-treasury-share-#{member.character_id}"}
                class="org-charter-clause"
              >
                <span>{member_name(member)}</span>
                <span class="org-app-note">{format_share_bps(member.share_bps)}</span>
              </li>
            </ul>

            <.form
              :if={@can_manage_treasury?}
              for={@treasury_share_form}
              id="org-treasury-share-form"
              phx-submit="assign_treasury_share"
              class="org-app-actions mt-4"
            >
              <.input
                field={@treasury_share_form[:character_id]}
                type="select"
                label="Участник"
                options={treasury_share_member_options(@treasury_ownership.members)}
              />
              <.input
                field={@treasury_share_form[:percent]}
                type="number"
                label="Доля участника (%)"
                min="0"
                max="100"
                required
              />
              <button id="org-treasury-share-save" type="submit" class="org-btn org-btn--ghost">
                Записать долю
              </button>
            </.form>

            <.form
              :if={@can_manage_treasury?}
              for={@treasury_dividend_form}
              id="org-treasury-dividend-form"
              phx-submit="distribute_treasury_dividend"
              class="org-app-actions mt-4 border-t border-stone-700 pt-4"
            >
              <.input
                field={@treasury_dividend_form[:amount]}
                type="number"
                label="Валовой доход для распределения"
                min="1"
                required
              />
              <button id="org-treasury-dividend" type="submit" class="org-btn">
                Распределить по долям
              </button>
            </.form>
          </section>

          <.form
            for={@treasury_deposit_form}
            id="org-treasury-deposit-form"
            phx-submit="deposit_treasury"
            class="org-app-actions mt-4"
          >
            <.input
              field={@treasury_deposit_form[:amount]}
              type="number"
              label="Вклад"
              min="1"
              required
            />
            <button id="org-treasury-deposit" type="submit" class="org-btn">
              Внести в казну
            </button>
          </.form>

          <.form
            :if={@can_manage_treasury?}
            for={@treasury_withdrawal_form}
            id="org-treasury-withdrawal-form"
            phx-submit="withdraw_treasury"
            class="org-app-actions mt-4 border-t border-stone-700 pt-4"
          >
            <.input
              field={@treasury_withdrawal_form[:handle]}
              type="text"
              label="Позывной получателя"
              autocomplete="off"
              required
            />
            <.input
              field={@treasury_withdrawal_form[:amount]}
              type="number"
              label="Сумма выплаты"
              min="1"
              required
            />
            <button id="org-treasury-withdraw" type="submit" class="org-btn">
              {treasury_withdrawal_button_label(@treasury_policy)}
            </button>
          </.form>

          <section
            :if={@treasury_policy.open_referendum}
            id="org-treasury-referendum"
            class="mt-4 border-t border-stone-700 pt-4"
          >
            <p id="org-treasury-referendum-summary" class="org-app-note">
              На голосовании: {@treasury_policy.open_referendum.amount} ◈ для {@treasury_policy.open_referendum.recipient_name}.
            </p>
            <p id="org-treasury-referendum-tally" class="org-app-note">
              Голоса: {@treasury_policy.open_referendum.votes_cast}/{@treasury_policy.open_referendum.voter_count}; поддержка {@treasury_policy.open_referendum.approve_votes}, отклонение {@treasury_policy.open_referendum.reject_votes}; для решения нужно {@treasury_policy.open_referendum.votes_needed}.
            </p>
            <div :if={@treasury_policy.open_referendum.can_vote?} class="org-app-actions mt-3">
              <button
                id="org-treasury-referendum-approve"
                type="button"
                class="org-btn"
                phx-click="cast_treasury_vote"
                phx-value-proposal_id={@treasury_policy.open_referendum.id}
                phx-value-vote="approve"
              >
                Поддержать выплату
              </button>
              <button
                id="org-treasury-referendum-reject"
                type="button"
                class="org-btn org-btn--ghost"
                phx-click="cast_treasury_vote"
                phx-value-proposal_id={@treasury_policy.open_referendum.id}
                phx-value-vote="reject"
              >
                Отклонить выплату
              </button>
            </div>
            <p
              :if={not @treasury_policy.open_referendum.can_vote?}
              id="org-treasury-referendum-vote-recorded"
              class="org-app-note mt-3"
            >
              Ваш голос уже учтён или вы не входили в состав участников на момент открытия.
            </p>
          </section>
        </section>

        <section :if={@fast_travel_destinations != []} id="org-fast-travel" class="org-card">
          <h2 class="org-card-top">Быстрый путь</h2>
          <p class="org-app-note">Маршруты доступны только из связанной точки организации.</p>
          <div class="org-app-actions">
            <button
              :for={destination <- @fast_travel_destinations}
              id={"org-fast-travel-#{destination.id}"}
              type="button"
              class="org-btn"
              phx-click="fast_travel"
              phx-value-destination-id={destination.id}
            >
              {fast_travel_destination_label(destination)}
            </button>
          </div>
        </section>

        <section
          :if={@fast_travel_tolls.can_configure? and length(@fast_travel_tolls.locations) > 1}
          id="org-fast-travel-toll-config"
          class="org-card"
        >
          <h2 class="org-card-top">Тарифы быстрых путей</h2>
          <p class="org-app-note">
            Тариф списывается до перехода: {format_tax_rate(@fast_travel_tolls.tax_rate_bps)} автоматически уходит в казну мира.
          </p>
          <.form
            for={@fast_travel_toll_form}
            id="org-fast-travel-toll-form"
            phx-submit="configure_fast_travel_toll"
            class="org-app-actions mt-4"
          >
            <.input
              field={@fast_travel_toll_form[:origin_location_id]}
              type="select"
              label="Откуда"
              options={fast_travel_location_options(@fast_travel_tolls.locations)}
            />
            <.input
              field={@fast_travel_toll_form[:destination_location_id]}
              type="select"
              label="Куда"
              options={fast_travel_location_options(@fast_travel_tolls.locations)}
            />
            <.input
              field={@fast_travel_toll_form[:amount]}
              type="number"
              label="Цена, ◈"
              min="0"
            />
            <button id="org-save-fast-travel-toll" type="submit" class="org-btn org-btn--ghost">
              Сохранить тариф
            </button>
          </.form>
          <ul :if={@fast_travel_tolls.configured_routes != []} class="org-card-list mt-4">
            <li
              :for={route <- @fast_travel_tolls.configured_routes}
              id={"org-fast-travel-toll-#{route.origin_location_id}-#{route.destination_location_id}"}
            >
              {route.origin_name} → {route.destination_name}: {route.fee} ◈
              <span class="text-stone-400">(налог {route.tax_amount} ◈)</span>
            </li>
          </ul>
        </section>

        <section :if={@can_invite?} id="org-invite-form" class="org-card">
          <h2 class="org-card-top">Пригласить участника</h2>
          <.form
            for={@invite_form}
            id="org-invite-form-body"
            phx-submit="invite"
            class="org-app-actions"
          >
            <.input
              field={@invite_form[:handle]}
              type="text"
              label="Позывной"
              autocomplete="off"
            />
            <.input
              field={@invite_form[:role_id]}
              type="select"
              label="Роль"
              options={Enum.map(@organization.roles, &{&1.title, &1.id})}
            />
            <button type="submit" class="org-btn">Отправить приглашение</button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="org-wrap">
        <.link navigate={~p"/map"} class="org-exit">&larr; к карте</.link>

        <h1 class="org-card-name">Организации</h1>
        <p class="org-card-creed">Гильдии, компании, советы и культы твоего мира</p>

        <%= if @error do %>
          <p class="org-app-note" role="alert">{@error}</p>
        <% end %>

        <section id="org-invitations" class="org-card">
          <h2 class="org-card-top">Приглашения</h2>
          <%= if @invitations == [] do %>
            <p class="org-app-note">Новых приглашений нет.</p>
          <% else %>
            <ul class="org-apps">
              <li :for={inv <- @invitations} class="org-app-main">
                <span class="org-app-name">{inv.organization.name}</span>
                <span class="org-app-note">{kind_label(inv.organization.kind)}</span>
                <button
                  type="button"
                  class="org-btn org-btn--sm"
                  phx-click="accept_invitation"
                  phx-value-invitation_id={inv.id}
                >
                  Принять
                </button>
                <button
                  type="button"
                  class="org-btn org-btn--sm org-btn--ghost"
                  phx-click="reject_invitation"
                  phx-value-invitation_id={inv.id}
                >
                  Отклонить
                </button>
              </li>
            </ul>
          <% end %>
        </section>

        <section id="org-list" class="org-card">
          <h2 class="org-card-top">Мои организации</h2>
          <%= if @organizations == [] do %>
            <p class="org-app-note">Ты пока не состоишь ни в одной организации.</p>
          <% else %>
            <ul class="org-card-list">
              <li :for={org <- @organizations} class="org-card-body">
                <.link navigate={~p"/orgs/#{org.id}"} class="org-card-name">{org.name}</.link>
                <span class="org-card-creed">{kind_label(org.kind)}</span>
              </li>
            </ul>
          <% end %>
        </section>

        <section id="org-public-list" class="org-card">
          <h2 class="org-card-top">Организации мира</h2>
          <%= if @public_organizations == [] do %>
            <p class="org-app-note">В этом мире ещё не основано ни одной организации.</p>
          <% else %>
            <ul class="org-card-list">
              <li
                :for={org <- @public_organizations}
                id={"org-public-#{org.id}"}
                class="org-card-body"
              >
                <span class="org-card-name">{org.name}</span>
                <span class="org-card-creed">{kind_label(org.kind)}</span>
                <button
                  :if={org.id in @open_organization_ids and org.id not in @member_organization_ids}
                  id={"org-join-#{org.id}"}
                  type="button"
                  class="org-btn org-btn--sm"
                  phx-click="join_open_organization"
                  phx-value-organization_id={org.id}
                >
                  Вступить
                </button>
              </li>
            </ul>
          <% end %>
        </section>

        <section id="org-create-form" class="org-card">
          <h2 class="org-card-top">Основать организацию</h2>
          <.form
            for={@organization_form}
            id="org-create-form-body"
            phx-submit="found"
            class="org-app-actions"
          >
            <.input
              field={@organization_form[:name]}
              type="text"
              label="Название"
              autocomplete="off"
              required
            />
            <.input
              field={@organization_form[:kind]}
              type="select"
              label="Вид"
              options={Enum.map(@kinds, &{kind_label(&1), to_string(&1)})}
            />
            <button type="submit" class="org-btn org-btn--seal">Основать</button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # ------------------------------------------------------------------
  # State loading
  # ------------------------------------------------------------------

  defp load_index(socket) do
    case Play.organizations_index(socket.assigns.character) do
      {:ok, state} ->
        socket
        |> assign(:organizations, state.organizations)
        |> assign(:invitations, state.invitations)
        |> assign(:public_organizations, state.public_organizations)
        |> assign(:member_organization_ids, state.member_organization_ids)
        |> assign(:open_organization_ids, state.open_organization_ids)
        |> assign(:kinds, @kinds)
        |> assign(
          :organization_form,
          to_form(%{"name" => "", "kind" => "guild"}, as: :organization)
        )

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/play")
    end
  end

  defp load_show(socket, organization_id) do
    case Play.organization_detail(socket.assigns.character, organization_id) do
      {:ok, state} ->
        socket
        |> assign(:organization, state.organization)
        |> assign(:membership, state.membership)
        |> assign(:can_invite?, state.can_invite?)
        |> assign(:can_manage_roles?, state.can_manage_roles?)
        |> assign(:can_manage_treasury?, state.can_manage_treasury?)
        |> assign(:treasury_balance, state.treasury_balance)
        |> assign(:treasury_recent_entry, state.treasury_recent_entry)
        |> assign(:treasury_ownership, state.treasury_ownership)
        |> assign(:treasury_policy, state.treasury_policy)
        |> assign(:leadership, state.leadership)
        |> assign(:membership_policy, state.membership_policy)
        |> assign(:diplomacy, state.diplomacy)
        |> assign(:fast_travel_destinations, state.fast_travel_destinations)
        |> assign(:fast_travel_tolls, state.fast_travel_tolls)
        |> assign(:invite_form, invite_form(state.organization))
        |> assign(:role_form, role_form())
        |> assign(:treasury_deposit_form, treasury_deposit_form())
        |> assign(:treasury_withdrawal_form, treasury_withdrawal_form())
        |> assign(:treasury_share_form, treasury_share_form(state.treasury_ownership.members))
        |> assign(:treasury_dividend_form, treasury_dividend_form())
        |> assign(:treasury_policy_form, treasury_policy_form(state.treasury_policy.decision))
        |> assign(
          :fast_travel_toll_form,
          fast_travel_toll_form(state.fast_travel_tolls.locations)
        )
        |> assign(
          :treasury_role_limit_form,
          treasury_role_limit_form(state.treasury_policy.role_limits)
        )
        |> assign(:leadership_form, leadership_form(state.leadership.selection))
        |> assign(:membership_form, membership_form(state.membership_policy.admission))
        |> assign(:succession, state.succession)
        |> assign(:succession_form, succession_form(state.succession.on_leader_exit))
        |> assign(:diplomacy_form, diplomacy_form(state.diplomacy.available_targets))

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/orgs")
    end
  end

  # ------------------------------------------------------------------
  # Presentation helpers
  # ------------------------------------------------------------------

  defp member_name(%{character: %{name: name}}), do: name
  defp member_name(_membership), do: "—"

  defp role_title(%{role: %{title: title}}), do: title
  defp role_title(_membership), do: "—"

  defp role_permissions_label([]), do: "без полномочий"

  defp role_permissions_label(permissions) when is_list(permissions) do
    permissions
    |> Enum.map(&role_permission_label/1)
    |> Enum.join(", ")
  end

  defp role_permissions_label(_permissions), do: "без полномочий"

  defp role_permission_options do
    [
      {"Приглашать участников", "invite_members"},
      {"Управлять ролями", "manage_roles"},
      {"Управлять казной", "manage_treasury"},
      {"Открывать быстрый путь", "grant_fast_travel"}
    ]
  end

  defp role_permission_label("invite_members"), do: "приглашения"
  defp role_permission_label("manage_roles"), do: "роли"
  defp role_permission_label("manage_treasury"), do: "казна"
  defp role_permission_label("grant_fast_travel"), do: "быстрый путь"
  defp role_permission_label(_permission), do: "иное полномочие"

  defp kind_label("guild"), do: "Гильдия"
  defp kind_label("company"), do: "Компания"
  defp kind_label("council"), do: "Совет"
  defp kind_label("cult"), do: "Культ"
  defp kind_label(kind) when is_atom(kind), do: kind |> Atom.to_string() |> kind_label()
  defp kind_label(_kind), do: "Организация"

  defp invite_form(organization) do
    role_id =
      case organization.roles do
        [role | _rest] -> role.id
        [] -> ""
      end

    to_form(%{"handle" => "", "role_id" => role_id}, as: :invite)
  end

  defp role_form do
    to_form(%{"title" => "", "rank" => "10", "permissions" => []}, as: :role)
  end

  defp treasury_deposit_form do
    to_form(%{"amount" => ""}, as: :treasury_deposit)
  end

  defp treasury_withdrawal_form do
    to_form(%{"handle" => "", "amount" => ""}, as: :treasury_withdrawal)
  end

  defp treasury_share_form(members) do
    character_id =
      case members do
        [%{character_id: character_id} | _rest] -> character_id
        _other -> ""
      end

    to_form(%{"character_id" => character_id, "percent" => "0"}, as: :treasury_share)
  end

  defp treasury_dividend_form do
    to_form(%{"amount" => ""}, as: :treasury_dividend)
  end

  defp treasury_policy_form(decision) do
    to_form(%{"decision" => decision}, as: :treasury_policy)
  end

  defp fast_travel_toll_form(locations) do
    location_ids = Enum.map(locations, & &1.id)
    origin_location_id = List.first(location_ids) || ""
    destination_location_id = Enum.at(location_ids, 1) || origin_location_id

    to_form(
      %{
        "origin_location_id" => origin_location_id,
        "destination_location_id" => destination_location_id,
        "amount" => "0"
      },
      as: :fast_travel_toll
    )
  end

  defp treasury_role_limit_form(role_limits) do
    role_id =
      case role_limits do
        [%{id: role_id} | _rest] -> role_id
        _other -> ""
      end

    to_form(%{"role_id" => role_id, "limit" => ""}, as: :treasury_role_limit)
  end

  defp leadership_form(selection) do
    to_form(%{"selection" => selection}, as: :leadership)
  end

  defp membership_form(admission) do
    to_form(%{"admission" => admission}, as: :membership)
  end

  defp succession_form(on_leader_exit) do
    to_form(%{"on_leader_exit" => on_leader_exit}, as: :succession)
  end

  defp diplomacy_form(targets) do
    target_organization_id =
      case targets do
        [%{id: organization_id} | _rest] -> organization_id
        _other -> ""
      end

    to_form(%{"target_organization_id" => target_organization_id, "kind" => "alliance"},
      as: :diplomacy
    )
  end

  defp parse_positive_amount(amount) when is_binary(amount) do
    case Integer.parse(String.trim(amount)) do
      {parsed_amount, ""} when parsed_amount > 0 -> {:ok, parsed_amount}
      _other -> {:error, :invalid_treasury_amount}
    end
  end

  defp parse_positive_amount(_amount), do: {:error, :invalid_treasury_amount}

  defp parse_nonnegative_amount(amount) when is_binary(amount) do
    case Integer.parse(String.trim(amount)) do
      {parsed_amount, ""} when parsed_amount >= 0 -> {:ok, parsed_amount}
      _other -> {:error, :invalid_fast_travel_toll}
    end
  end

  defp parse_nonnegative_amount(_amount), do: {:error, :invalid_fast_travel_toll}

  defp fast_travel_location_options(locations) do
    Enum.map(locations, &{&1.name, &1.id})
  end

  defp fast_travel_destination_label(%{fee: fee, name: name, tax_amount: tax_amount})
       when is_integer(fee) and fee > 0 do
    "#{name} · #{fee} ◈ (налог #{tax_amount} ◈)"
  end

  defp fast_travel_destination_label(%{name: name}), do: "#{name} · бесплатно"

  defp format_tax_rate(tax_rate_bps) when is_integer(tax_rate_bps) and tax_rate_bps >= 0 do
    whole_percent = div(tax_rate_bps, 100)
    fraction = rem(tax_rate_bps, 100)

    if fraction == 0 do
      "#{whole_percent}%"
    else
      "#{whole_percent}.#{String.pad_leading(Integer.to_string(fraction), 2, "0")}%"
    end
  end

  defp format_tax_rate(_tax_rate_bps), do: "0%"

  defp parse_optional_nonnegative_amount(amount) when is_binary(amount) do
    case String.trim(amount) do
      "" ->
        {:ok, nil}

      value ->
        case Integer.parse(value) do
          {parsed_amount, ""} when parsed_amount >= 0 -> {:ok, parsed_amount}
          _other -> {:error, :invalid_treasury_role_limit}
        end
    end
  end

  defp parse_optional_nonnegative_amount(_amount), do: {:error, :invalid_treasury_role_limit}

  defp parse_share_percent(percent) when is_binary(percent) do
    case Integer.parse(String.trim(percent)) do
      {whole_percent, ""} when whole_percent in 0..100 -> {:ok, whole_percent * 100}
      _other -> {:error, :invalid_treasury_share}
    end
  end

  defp parse_share_percent(_percent), do: {:error, :invalid_treasury_share}

  defp treasury_entry_label(%{amount: amount, metadata: %{"source" => source}}) do
    "Последняя проводка: #{treasury_source_label(source)} · #{amount} ◈"
  end

  defp treasury_entry_label(%{amount: amount}), do: "Последняя проводка: #{amount} ◈"
  defp treasury_entry_label(_entry), do: "Последняя проводка зафиксирована."

  defp treasury_source_label("organization_treasury_deposit"), do: "вклад"
  defp treasury_source_label("organization_treasury_withdrawal"), do: "выплата"
  defp treasury_source_label("organization_treasury_referendum"), do: "выплата по референдуму"
  defp treasury_source_label(_source), do: "движение средств"

  defp treasury_share_member_options(members) do
    Enum.map(members, fn member -> {member_name(member), member.character_id} end)
  end

  defp format_share_bps(share_bps) when is_integer(share_bps) do
    whole_percent = div(share_bps, 100)
    fraction = rem(share_bps, 100)

    if fraction == 0 do
      "#{whole_percent}%"
    else
      "#{whole_percent}.#{String.pad_leading(Integer.to_string(fraction), 2, "0")}%"
    end
  end

  defp format_share_bps(_share_bps), do: "0%"

  defp leadership_selection_options do
    [
      {"Назначение основателем", "founder_appointment"},
      {"Выборы участников", "member_election"},
      {"Выборы по долям казны", "share_weighted_election"}
    ]
  end

  defp leadership_selection_label("member_election"), do: "выборы участников"
  defp leadership_selection_label("share_weighted_election"), do: "выборы по долям казны"
  defp leadership_selection_label("founder_appointment"), do: "назначение основателем"
  defp leadership_selection_label(_selection), do: "назначение основателем"

  defp membership_admission_options do
    [
      {"Только по приглашению", "invitation_only"},
      {"Открытое вступление", "open"}
    ]
  end

  defp membership_admission_label("open"), do: "открытое вступление"
  defp membership_admission_label("invitation_only"), do: "только по приглашению"
  defp membership_admission_label(_admission), do: "только по приглашению"

  defp succession_options do
    [
      {"Передать старшему по рангу", "highest_rank_member"},
      {"Оставить пост вакантным", "vacant"}
    ]
  end

  defp succession_label("vacant"), do: "пост остаётся вакантным"
  defp succession_label("highest_rank_member"), do: "передать старшему по рангу"
  defp succession_label(_on_leader_exit), do: "передать старшему по рангу"

  defp treasury_decision_options do
    [
      {"По полномочию роли", "role_permission"},
      {"Референдум участников", "member_referendum"}
    ]
  end

  defp treasury_decision_label("member_referendum"), do: "референдум участников"
  defp treasury_decision_label("role_permission"), do: "по полномочию роли"
  defp treasury_decision_label(_decision), do: "по полномочию роли"

  defp treasury_role_limit_options(role_limits) do
    Enum.map(role_limits, fn role -> {"#{role.title} · ранг #{role.rank}", role.id} end)
  end

  defp treasury_direct_payout_limit_label(nil), do: "без предела"
  defp treasury_direct_payout_limit_label(0), do: "только через референдум"

  defp treasury_direct_payout_limit_label(limit) when is_integer(limit) and limit > 0,
    do: "до #{limit} ◈ напрямую"

  defp treasury_direct_payout_limit_label(_limit), do: "без предела"

  defp treasury_withdrawal_button_label(%{decision: "member_referendum"}),
    do: "Вынести выплату на голосование"

  defp treasury_withdrawal_button_label(%{actor_direct_payout_limit: limit})
       when is_integer(limit),
       do: "Исполнить по пределу роли"

  defp treasury_withdrawal_button_label(_policy), do: "Выплатить из казны"

  defp treasury_referendum_required?(%{decision: "member_referendum"}, _amount), do: true

  defp treasury_referendum_required?(%{actor_direct_payout_limit: limit}, amount)
       when is_integer(limit) and is_integer(amount) and amount > 0,
       do: amount > limit

  defp treasury_referendum_required?(_policy, _amount), do: false

  defp submit_treasury_withdrawal(character, organization_id, handle, amount, true) do
    Play.propose_organization_treasury_withdrawal(character, organization_id, handle, amount)
  end

  defp submit_treasury_withdrawal(character, organization_id, handle, amount, false) do
    Play.spend_organization_treasury(character, organization_id, handle, amount)
  end

  defp diplomacy_target_options(targets) do
    Enum.map(targets, &{&1.name, &1.id})
  end

  defp diplomacy_kind_options do
    [{"Союз", "alliance"}, {"Соперничество", "rivalry"}, {"Война", "war"}]
  end

  defp diplomacy_kind_label("alliance"), do: "союз"
  defp diplomacy_kind_label("rivalry"), do: "соперничество"
  defp diplomacy_kind_label("war"), do: "война"
  defp diplomacy_kind_label(_kind), do: "отношение"
end
