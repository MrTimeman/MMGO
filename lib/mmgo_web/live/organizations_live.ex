defmodule MMGOWeb.OrganizationsLive do
  @moduledoc """
  Player organizations (GDD §17), wired to the real `MMGO.Organizations`
  context through `MMGO.Play`.

  Map-first (GDD §5): organization business happens in a city, so mount gates on
  the session character's location. Three live actions share this module:

    * `:index` `/orgs`            — the registry: your organizations + invitations
    * `:new`   `/orgs/new`        — founding (shares the index's create form)
    * `:show`  `/orgs/:id[/:tab]` — one organization's members, roles, invites

  All authority derives from the session character; org/role/invitee ids from the
  client are validated against real ownership in `MMGO.Play`.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @kinds ~w(guild company council cult)

  @impl true
  def mount(_params, session, socket) do
    case session_character(session) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/play/continue")}

      character ->
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
  def handle_event("leave", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/orgs")}
  end

  # ------------------------------------------------------------------
  # Render
  # ------------------------------------------------------------------

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="org-app">
      <.link navigate={~p"/map"} class="org-btn org-btn--ghost">&larr; к карте</.link>
      <.link navigate={~p"/orgs"} class="org-btn org-btn--ghost">Все организации</.link>

      <h1 class="org-card-name">{@organization.name}</h1>
      <p class="org-card-creed">Organizations · {kind_label(@organization.kind)}</p>

      <%= if @error do %>
        <p class="org-app-note" role="alert">{@error}</p>
      <% end %>

      <section id="org-roles" class="org-card">
        <h2 class="org-card-top">Роли (Roles)</h2>
        <ul class="org-card-list">
          <li :for={role <- @organization.roles} class="org-charter-clause">
            {role.title}
          </li>
        </ul>
      </section>

      <section id="org-members" class="org-card">
        <h2 class="org-card-top">Участники (Members)</h2>
        <ul class="org-card-members">
          <li :for={m <- @organization.memberships}>
            {member_name(m)} — {role_title(m)}
          </li>
        </ul>
      </section>

      <section id="org-invite-form" class="org-card">
        <h2 class="org-card-top">Пригласить (Invite)</h2>
        <form phx-submit="invite" class="org-app-actions">
          <label>
            Позывной <input type="text" name="invite[handle]" autocomplete="off" />
          </label>
          <label>
            Роль
            <select name="invite[role_id]">
              <option :for={role <- @organization.roles} value={role.id}>{role.title}</option>
            </select>
          </label>
          <button type="submit" class="org-btn">Отправить приглашение</button>
        </form>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="org-app">
      <.link navigate={~p"/map"} class="org-btn org-btn--ghost">&larr; к карте</.link>

      <h1 class="org-card-name">Organizations</h1>
      <p class="org-card-creed">Гильдии, компании, советы и культы твоего мира</p>

      <%= if @error do %>
        <p class="org-app-note" role="alert">{@error}</p>
      <% end %>

      <section id="org-invitations" class="org-card">
        <h2 class="org-card-top">Приглашения (Invitations)</h2>
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
              <span class="org-card-creed">{to_string(org.kind)}</span>
            </li>
          </ul>
        <% end %>
      </section>

      <section id="org-create-form" class="org-card">
        <h2 class="org-card-top">Основать организацию</h2>
        <form phx-submit="found" class="org-app-actions">
          <label>
            Название <input type="text" name="organization[name]" autocomplete="off" required />
          </label>
          <label>
            Вид
            <select name="organization[kind]">
              <option :for={kind <- @kinds} value={kind}>{kind_label(kind)}</option>
            </select>
          </label>
          <button type="submit" class="org-btn org-btn--seal">Основать</button>
        </form>
      </section>
    </div>
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
        |> assign(:kinds, @kinds)

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/play/continue")
    end
  end

  defp load_show(socket, organization_id) do
    case Play.organization_detail(socket.assigns.character, organization_id) do
      {:ok, state} ->
        socket
        |> assign(:organization, state.organization)
        |> assign(:membership, state.membership)

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/orgs")
    end
  end

  # ------------------------------------------------------------------
  # Session + presentation helpers
  # ------------------------------------------------------------------

  defp session_character(session) do
    with id when is_binary(id) <- session["demo_character_id"],
         {:ok, %{character: character}} <- Play.load_demo_state(id) do
      character
    else
      _other -> nil
    end
  end

  defp member_name(%{character: %{name: name}}), do: name
  defp member_name(_membership), do: "—"

  defp role_title(%{role: %{title: title}}), do: title
  defp role_title(_membership), do: "—"

  defp kind_label("guild"), do: "Гильдия"
  defp kind_label("company"), do: "Компания"
  defp kind_label("council"), do: "Совет"
  defp kind_label("cult"), do: "Культ"
  defp kind_label(kind) when is_atom(kind), do: kind |> Atom.to_string() |> kind_label()
  defp kind_label(kind), do: to_string(kind)
end
