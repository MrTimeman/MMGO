defmodule MMGOWeb.OrganizationsLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts
  alias MMGO.Organizations
  alias MMGO.Organizations.Organization
  alias MMGOWeb.LocationGate

  @kinds [:cult, :company, :council, :guild]
  @known_permissions ["invite_members", "manage_roles", "grant_fast_travel"]

  @impl true
  def mount(_params, session, socket) do
    character = load_character(session)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :city) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          {:ok,
           socket
           |> assign(:page_title, "Organizations")
           |> assign(:character, character)
           |> assign(:organization, nil)
           |> assign(:kinds, @kinds)
           |> assign(:known_permissions, @known_permissions)
           |> assign(:invite_form_error, nil)
           |> assign(:role_form_error, nil)}
      end
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, %{assigns: %{character: character}} = socket)
      when not is_nil(character) do
    case load_owned_organization(id, character.id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not an active member of that organization.")
         |> push_navigate(to: ~p"/orgs")}

      organization ->
        {:noreply,
         socket
         |> assign(:organization, organization)
         |> assign(:invite_form_error, nil)
         |> assign(:role_form_error, nil)
         |> assign_fast_travel_destinations()}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:organization, nil)
     |> assign(:organizations, load_organizations(socket.assigns.character))
     |> assign(:pending_invitations, load_invitations(socket.assigns.character))}
  end

  @impl true
  def handle_event("create_organization", %{"organization" => params}, socket) do
    character = socket.assigns.character
    kind = params["kind"]
    name = params["name"] || ""

    case Organizations.create_organization(character, kind, name) do
      {:ok, %{organization: organization}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Founded #{organization.name}.")
         |> assign(:organizations, load_organizations(character))
         |> assign(:pending_invitations, load_invitations(character))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}
    end
  end

  @impl true
  def handle_event("accept_invitation", %{"invitation_id" => invitation_id}, socket) do
    character = socket.assigns.character
    invitation = find_invitation(socket, invitation_id)

    case invitation && Organizations.accept_invitation(invitation, character) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation accepted.")
         |> assign(:organizations, load_organizations(character))
         |> assign(:pending_invitations, load_invitations(character))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "Invitation not found.")}
    end
  end

  @impl true
  def handle_event("reject_invitation", %{"invitation_id" => invitation_id}, socket) do
    character = socket.assigns.character
    invitation = find_invitation(socket, invitation_id)

    case invitation && Organizations.reject_invitation(invitation, character) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation rejected.")
         |> assign(:pending_invitations, load_invitations(character))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "Invitation not found.")}
    end
  end

  @impl true
  def handle_event("add_role", %{"role" => params}, socket) do
    character = socket.assigns.character
    organization = socket.assigns.organization

    permissions =
      params
      |> Map.get("permissions", %{})
      |> Enum.filter(fn {_permission, checked} -> checked in ["true", "on"] end)
      |> Enum.map(fn {permission, _checked} -> permission end)

    attrs = %{
      "code" => params["code"],
      "title" => params["title"],
      "rank" => parse_integer(params["rank"], 10),
      "permissions" => permissions
    }

    case Organizations.add_role(organization, character, attrs) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role created.")
         |> assign(:role_form_error, nil)
         |> reload_organization()}

      {:error, changeset} ->
        {:noreply, assign(socket, :role_form_error, changeset_error(changeset))}
    end
  end

  @impl true
  def handle_event("invite_member", %{"invite" => params}, socket) do
    character = socket.assigns.character
    organization = socket.assigns.organization
    handle = String.trim(params["handle"] || "")
    role_id = params["role_id"]

    with invitee when not is_nil(invitee) <-
           Accounts.get_character_by_handle(character.realm_id, handle),
         role when not is_nil(role) <- Enum.find(organization.roles, &(&1.id == role_id)),
         {:ok, invitation} <-
           Organizations.invite_member(organization, character, invitee, role) do
      {:noreply,
       socket
       |> put_flash(:info, "Invitation sent to #{invitee.name}.")
       |> assign(:invite_form_error, nil)
       |> reload_organization()
       |> then(fn socket -> assign(socket, :last_invitation, invitation) end)}
    else
      nil ->
        {:noreply, assign(socket, :invite_form_error, "Character handle or role not found.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :invite_form_error, changeset_error(changeset))}
    end
  end

  @impl true
  def handle_event("fast_travel", %{"location_id" => location_id}, socket) do
    character = socket.assigns.character
    organization = socket.assigns.organization
    destination = Enum.find(socket.assigns.fast_travel_destinations, &(&1.id == location_id))

    case destination && Organizations.use_fast_travel(character, organization, destination) do
      {:ok, updated_character} ->
        {:noreply,
         socket
         |> assign(:character, updated_character)
         |> put_flash(:info, "Travelled to #{destination.name}.")
         |> assign_fast_travel_destinations()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}

      nil ->
        {:noreply, put_flash(socket, :error, "Destination is not available.")}
    end
  end

  @impl true
  def handle_event("leave_organization", _params, socket) do
    character = socket.assigns.character
    organization = socket.assigns.organization

    case Organizations.leave_organization(organization, character) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "You left #{organization.name}.")
         |> push_navigate(to: ~p"/orgs")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}
    end
  end

  @impl true
  def render(%{organization: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="game-root" style="overflow-y: auto; padding: 2rem; padding-bottom: 6rem;">
        <div style="max-width: 900px; margin: 0 auto;">
          <a href={~p"/map"} class="map-back-link">← World map</a>
          <header style="margin-bottom: 2rem;">
            <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 1.75rem;">
              Organizations
            </h1>
            <p style="color: var(--color-text-muted); font-size: 0.875rem;">
              {@character.name} · Realm {@character.realm_id}
            </p>
          </header>

          <section id="org-invitations" style="margin-bottom: 2.5rem;">
            <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
              Pending Invitations
            </h2>
            <%= if @pending_invitations == [] do %>
              <p style="color: var(--color-text-muted); font-size: 0.875rem;">
                No pending invitations.
              </p>
            <% else %>
              <div style="display: flex; flex-direction: column; gap: 0.75rem;">
                <%= for invitation <- @pending_invitations do %>
                  <div
                    id={"invitation-#{invitation.id}"}
                    style="background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--panel-radius); padding: 1rem; display: flex; justify-content: space-between; align-items: center;"
                  >
                    <div>
                      <strong>{invitation.organization.name}</strong>
                      <span style="color: var(--color-text-muted);">
                        ({invitation.organization.kind}) as {invitation.role.title}
                      </span>
                      <div style="color: var(--color-text-muted); font-size: 0.8rem;">
                        Invited by {invitation.inviter_character.name}
                      </div>
                    </div>
                    <div style="display: flex; gap: 0.5rem;">
                      <button
                        phx-click="accept_invitation"
                        phx-value-invitation_id={invitation.id}
                        style="padding: 0.4rem 1rem; background: var(--color-accent); color: #000; border: none; border-radius: 0.375rem; cursor: pointer; font-weight: bold;"
                      >
                        Accept
                      </button>
                      <button
                        phx-click="reject_invitation"
                        phx-value-invitation_id={invitation.id}
                        style="padding: 0.4rem 1rem; background: none; border: 1px solid var(--color-border); border-radius: 0.375rem; cursor: pointer;"
                      >
                        Reject
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>

          <section id="org-list" style="margin-bottom: 2.5rem;">
            <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
              My Organizations
            </h2>
            <%= if @organizations == [] do %>
              <p style="color: var(--color-text-muted); font-size: 0.875rem;">
                You have not joined any organizations yet.
              </p>
            <% else %>
              <div style="display: flex; flex-direction: column; gap: 0.75rem;">
                <%= for organization <- @organizations do %>
                  <.link
                    navigate={~p"/orgs/#{organization.id}"}
                    id={"org-row-#{organization.id}"}
                    style="display: block; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--panel-radius); padding: 1rem; text-decoration: none; color: inherit;"
                  >
                    <div style="display: flex; justify-content: space-between; align-items: center;">
                      <div>
                        <strong style="color: var(--color-text);">{organization.name}</strong>
                        <span style="
                          margin-left: 0.5rem;
                          font-size: 0.7rem;
                          padding: 0.15rem 0.5rem;
                          background: var(--color-surface-2);
                          border-radius: 9999px;
                          color: var(--color-text-muted);
                          text-transform: uppercase;
                          letter-spacing: 0.05em;
                        ">
                          {organization.kind}
                        </span>
                      </div>
                      <div style="color: var(--color-text-muted); font-size: 0.8rem;">
                        {length(organization.memberships)} member(s) · {my_role_title(
                          organization,
                          @character
                        )}
                      </div>
                    </div>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </section>

          <section id="org-create-form">
            <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
              Found an Organization
            </h2>
            <form
              phx-submit="create_organization"
              style="display: flex; gap: 0.75rem; align-items: flex-end; flex-wrap: wrap;"
            >
              <div>
                <label style="display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.25rem;">
                  Name
                </label>
                <input
                  type="text"
                  name="organization[name]"
                  required
                  style="padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                />
              </div>
              <div>
                <label style="display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.25rem;">
                  Kind
                </label>
                <select
                  name="organization[kind]"
                  style="padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                >
                  <%= for kind <- @kinds do %>
                    <option value={kind}>{kind}</option>
                  <% end %>
                </select>
              </div>
              <button
                type="submit"
                style="padding: 0.55rem 1.5rem; background: var(--color-accent); color: #000; font-family: var(--font-serif); font-weight: bold; border: none; border-radius: 0.375rem; cursor: pointer;"
              >
                Found
              </button>
            </form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def render(%{organization: %Organization{}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="game-root" style="overflow-y: auto; padding: 2rem; padding-bottom: 6rem;">
        <div style="max-width: 900px; margin: 0 auto;">
          <a href={~p"/map"} class="map-back-link">← World map</a>
          <header style="margin-bottom: 2rem;">
            <.link
              navigate={~p"/orgs"}
              style="color: var(--color-text-muted); font-size: 0.85rem; text-decoration: underline;"
            >
              ← All Organizations
            </.link>
            <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 1.75rem; margin-top: 0.5rem;">
              {@organization.name}
            </h1>
            <p style="color: var(--color-text-muted); font-size: 0.875rem;">
              {@organization.kind} · Founded {Calendar.strftime(@organization.inserted_at, "%Y-%m-%d")}
            </p>
          </header>

          <section id="org-members" style="margin-bottom: 2.5rem;">
            <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
              Members
            </h2>
            <table style="width: 100%; border-collapse: collapse; font-size: 0.875rem;">
              <thead>
                <tr style="text-align: left; color: var(--color-text-muted); border-bottom: 1px solid var(--color-border);">
                  <th style="padding: 0.5rem 0;">Character</th>
                  <th style="padding: 0.5rem 0;">Role</th>
                  <th style="padding: 0.5rem 0;">Rank</th>
                  <th style="padding: 0.5rem 0;">Joined</th>
                </tr>
              </thead>
              <tbody>
                <%= for membership <- @organization.memberships do %>
                  <tr
                    id={"member-#{membership.id}"}
                    style="border-bottom: 1px solid var(--color-border);"
                  >
                    <td style="padding: 0.5rem 0;">{membership.character.name}</td>
                    <td style="padding: 0.5rem 0;">{membership.role.title}</td>
                    <td style="padding: 0.5rem 0;">{membership.role.rank}</td>
                    <td style="padding: 0.5rem 0;">
                      {Calendar.strftime(membership.joined_at, "%Y-%m-%d")}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </section>

          <section id="org-roles" style="margin-bottom: 2.5rem;">
            <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
              Roles
            </h2>
            <div style="display: flex; flex-direction: column; gap: 0.5rem;">
              <%= for role <- @organization.roles do %>
                <div
                  id={"role-#{role.id}"}
                  style="background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--panel-radius); padding: 0.75rem 1rem;"
                >
                  <strong>{role.title}</strong>
                  <span style="color: var(--color-text-muted); font-size: 0.8rem;">
                    ({role.code}) · rank {role.rank}
                  </span>
                  <div style="margin-top: 0.4rem; display: flex; gap: 0.4rem; flex-wrap: wrap;">
                    <%= for permission <- role.permissions do %>
                      <span style="
                        font-size: 0.7rem;
                        padding: 0.15rem 0.5rem;
                        background: var(--color-surface-2);
                        border-radius: 9999px;
                        color: var(--color-text-muted);
                      ">
                        {permission}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </section>

          <%= if can?(@organization, @character, "manage_roles") do %>
            <section id="org-add-role-form" style="margin-bottom: 2.5rem;">
              <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
                Add Role
              </h2>
              <%= if @role_form_error do %>
                <p style="color: var(--color-danger); font-size: 0.85rem; margin-bottom: 0.5rem;">
                  {@role_form_error}
                </p>
              <% end %>
              <form
                phx-submit="add_role"
                style="display: flex; flex-direction: column; gap: 0.75rem; max-width: 420px;"
              >
                <div style="display: flex; gap: 0.75rem;">
                  <input
                    type="text"
                    name="role[code]"
                    placeholder="code"
                    required
                    style="flex: 1; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                  />
                  <input
                    type="text"
                    name="role[title]"
                    placeholder="title"
                    required
                    style="flex: 1; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                  />
                  <input
                    type="number"
                    name="role[rank]"
                    placeholder="rank"
                    min="0"
                    style="width: 90px; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                  />
                </div>
                <div style="display: flex; gap: 1rem; font-size: 0.85rem;">
                  <%= for permission <- @known_permissions do %>
                    <label style="display: flex; align-items: center; gap: 0.3rem;">
                      <input type="checkbox" name={"role[permissions][#{permission}]"} value="true" />
                      {permission}
                    </label>
                  <% end %>
                </div>
                <button
                  type="submit"
                  style="align-self: flex-start; padding: 0.5rem 1.25rem; background: var(--color-accent); color: #000; font-weight: bold; border: none; border-radius: 0.375rem; cursor: pointer;"
                >
                  Create Role
                </button>
              </form>
            </section>
          <% end %>

          <%= if can?(@organization, @character, "invite_members") do %>
            <section id="org-invite-form" style="margin-bottom: 2.5rem;">
              <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
                Invite Member
              </h2>
              <%= if @invite_form_error do %>
                <p style="color: var(--color-danger); font-size: 0.85rem; margin-bottom: 0.5rem;">
                  {@invite_form_error}
                </p>
              <% end %>
              <form
                phx-submit="invite_member"
                style="display: flex; gap: 0.75rem; align-items: flex-end; flex-wrap: wrap;"
              >
                <div>
                  <label style="display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.25rem;">
                    Character Handle
                  </label>
                  <input
                    type="text"
                    name="invite[handle]"
                    required
                    style="padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                  />
                </div>
                <div>
                  <label style="display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 0.25rem;">
                    Role
                  </label>
                  <select
                    name="invite[role_id]"
                    style="padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.375rem; background: var(--color-surface);"
                  >
                    <%= for role <- @organization.roles do %>
                      <option value={role.id}>{role.title}</option>
                    <% end %>
                  </select>
                </div>
                <button
                  type="submit"
                  style="padding: 0.55rem 1.5rem; background: var(--color-accent); color: #000; font-family: var(--font-serif); font-weight: bold; border: none; border-radius: 0.375rem; cursor: pointer;"
                >
                  Send Invite
                </button>
              </form>
            </section>
          <% end %>

          <%= if @organization.fast_travel_enabled && can?(@organization, @character, "grant_fast_travel") do %>
            <section id="org-fast-travel" style="margin-bottom: 2.5rem;">
              <h2 style="font-family: var(--font-serif); font-size: 1.25rem; margin-bottom: 1rem;">
                Fast Travel
              </h2>
              <%= if @fast_travel_destinations == [] do %>
                <p style="color: var(--color-text-muted); font-size: 0.875rem;">
                  No fast travel destinations available from your current location.
                </p>
              <% else %>
                <div style="display: flex; flex-direction: column; gap: 0.5rem;">
                  <%= for destination <- @fast_travel_destinations do %>
                    <div
                      id={"fast-travel-#{destination.id}"}
                      style="display: flex; justify-content: space-between; align-items: center; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--panel-radius); padding: 0.6rem 1rem;"
                    >
                      <span>{destination.name}</span>
                      <button
                        phx-click="fast_travel"
                        phx-value-location_id={destination.id}
                        style="padding: 0.4rem 1rem; background: var(--color-accent); color: #000; border: none; border-radius: 0.375rem; cursor: pointer; font-weight: bold;"
                      >
                        Travel
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>
          <% end %>

          <section id="org-leave">
            <button
              phx-click="leave_organization"
              data-confirm="Are you sure you want to leave this organization?"
              style="padding: 0.5rem 1.25rem; background: none; border: 1px solid var(--color-danger); color: var(--color-danger); border-radius: 0.375rem; cursor: pointer;"
            >
              Leave Organization
            </button>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_fast_travel_destinations(socket) do
    %{character: character, organization: organization} = socket.assigns

    destinations =
      character
      |> Organizations.list_available_fast_travel_destinations()
      |> Enum.filter(&(&1.id in organization.linked_location_ids))

    assign(socket, :fast_travel_destinations, destinations)
  end

  defp reload_organization(socket) do
    organization = Organizations.get_organization!(socket.assigns.organization.id)

    socket
    |> assign(:organization, organization)
    |> assign_fast_travel_destinations()
  end

  defp find_invitation(socket, invitation_id) do
    Enum.find(socket.assigns.pending_invitations, &(&1.id == invitation_id))
  end

  defp load_organizations(character) do
    Organizations.list_organizations_for_character(character.id)
  end

  defp load_invitations(character) do
    Organizations.pending_invitations_for_character(character.id)
  end

  defp load_owned_organization(id, character_id) do
    organization = Organizations.get_organization!(id)

    if Enum.any?(
         organization.memberships,
         &(&1.character_id == character_id and &1.status == :active)
       ) do
      organization
    else
      nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp my_role_title(organization, character) do
    organization.memberships
    |> Enum.find(&(&1.character_id == character.id))
    |> case do
      nil -> "—"
      membership -> membership.role.title
    end
  end

  defp can?(organization, character, permission) do
    organization.memberships
    |> Enum.find(&(&1.character_id == character.id))
    |> case do
      nil -> false
      membership -> permission in membership.role.permissions
    end
  end

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    Accounts.get_character!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> default
    end
  end

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end
end
