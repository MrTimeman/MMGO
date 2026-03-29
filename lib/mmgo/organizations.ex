defmodule MMGO.Organizations do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Notifications
  alias MMGO.Organizations.{Invitation, Membership, Organization, Role}
  alias MMGO.Repo
  alias MMGO.Worlds.Location

  @kinds [:cult, :company, :council, :guild]

  def list_organizations_for_character(character_id) when is_binary(character_id) do
    Organization
    |> join(:inner, [organization], membership in assoc(organization, :memberships))
    |> where(
      [_organization, membership],
      membership.character_id == ^character_id and membership.status == :active
    )
    |> order_by([organization, _membership], asc: organization.inserted_at)
    |> Repo.all()
    |> Repo.preload(memberships: active_membership_query())
  end

  def get_organization!(id) do
    Organization
    |> Repo.get!(id)
    |> Repo.preload(roles: [], memberships: active_membership_query())
  end

  def create_organization(%Character{} = founder, kind, name, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    kind = normalize_kind(kind)

    Repo.transaction(fn ->
      founder = lock_character!(founder.id)

      if is_nil(kind) do
        Repo.rollback(organization_changeset("organization kind is invalid"))
      end

      organization =
        %Organization{}
        |> Organization.changeset(%{
          realm_id: founder.realm_id,
          founder_character_id: founder.id,
          name: name,
          kind: kind,
          hierarchy_rules: attrs["hierarchy_rules"] || %{"custom_roles_allowed" => true},
          fast_travel_enabled: attrs["fast_travel_enabled"] || false,
          linked_location_ids: attrs["linked_location_ids"] || [],
          metadata: attrs["metadata"] || %{}
        })
        |> Repo.insert!()

      leader_role =
        %Role{}
        |> Role.changeset(%{
          organization_id: organization.id,
          code: default_role_code(kind),
          title: default_role_title(kind),
          rank: 100,
          permissions: ["invite_members", "manage_roles", "grant_fast_travel"]
        })
        |> Repo.insert!()

      membership =
        %Membership{}
        |> Membership.changeset(%{
          organization_id: organization.id,
          character_id: founder.id,
          role_id: leader_role.id,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      %{
        organization: get_organization!(organization.id),
        membership: membership,
        role: leader_role
      }
    end)
    |> normalize_transaction_result()
  end

  def add_role(%Organization{} = organization, %Character{} = actor, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      %Role{}
      |> Role.changeset(%{
        organization_id: organization.id,
        code: attrs["code"],
        title: attrs["title"],
        rank: attrs["rank"] || 10,
        permissions: attrs["permissions"] || []
      })
      |> Repo.insert!()
    end)
    |> normalize_transaction_result()
  end

  def invite_member(
        %Organization{} = organization,
        %Character{} = inviter,
        %Character{} = invitee,
        %Role{} = role
      ) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      inviter_membership = active_membership!(organization.id, inviter.id)
      invitee = lock_character!(invitee.id)
      role = Repo.get!(Role, role.id)

      validate_permission!(inviter_membership, "invite_members")

      if invitee.realm_id != organization.realm_id do
        Repo.rollback(organization_changeset("invitee must belong to the same realm"))
      end

      if Repo.exists?(
           from membership in Membership,
             where:
               membership.organization_id == ^organization.id and
                 membership.character_id == ^invitee.id and membership.status == :active
         ) do
        Repo.rollback(organization_changeset("invitee is already a member"))
      end

      invitation =
        %Invitation{}
        |> Invitation.changeset(%{
          organization_id: organization.id,
          inviter_character_id: inviter.id,
          invitee_character_id: invitee.id,
          role_id: role.id,
          status: :pending,
          sent_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      _ = Notifications.notify_org_invitation(invitee, invitation, organization)

      Repo.preload(invitation, [:organization, :inviter_character, :role])
    end)
    |> normalize_transaction_result()
  end

  def accept_invitation(%Invitation{} = invitation, %Character{} = invitee) do
    Repo.transaction(fn ->
      invitation = lock_invitation!(invitation.id)
      invitee = lock_character!(invitee.id)

      validate_invitation_response!(invitation, invitee)

      membership =
        %Membership{}
        |> Membership.changeset(%{
          organization_id: invitation.organization_id,
          character_id: invitee.id,
          role_id: invitation.role_id,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

      invitation
      |> Invitation.changeset(%{status: :accepted, responded_at: DateTime.utc_now()})
      |> Repo.update!()

      membership
    end)
    |> normalize_transaction_result()
  end

  def reject_invitation(%Invitation{} = invitation, %Character{} = invitee) do
    Repo.transaction(fn ->
      invitation = lock_invitation!(invitation.id)
      invitee = lock_character!(invitee.id)
      validate_invitation_response!(invitation, invitee)

      invitation
      |> Invitation.changeset(%{status: :rejected, responded_at: DateTime.utc_now()})
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def leave_organization(%Organization{} = organization, %Character{} = character) do
    Repo.transaction(fn ->
      membership = active_membership!(organization.id, character.id)

      membership
      |> Membership.changeset(%{status: :left, left_at: DateTime.utc_now()})
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def pending_invitations_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from invitation in Invitation,
        where: invitation.invitee_character_id == ^character_id and invitation.status == :pending,
        order_by: [asc: invitation.inserted_at],
        preload: [:organization, :inviter_character, :role]
    )
  end

  def list_available_fast_travel_destinations(%Character{} = character) do
    character.current_location_id
    |> fast_travel_memberships(character.id)
    |> Enum.flat_map(fn membership ->
      membership.organization.linked_location_ids
      |> Enum.reject(&(&1 == character.current_location_id))
      |> Enum.map(&MMGO.Worlds.get_location!/1)
    end)
  end

  def use_fast_travel(
        %Character{} = character,
        %Organization{} = organization,
        %Location{} = destination_location
      ) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      membership = active_membership!(organization.id, character.id)
      validate_permission!(membership, "grant_fast_travel")

      cond do
        character.current_location_id not in organization.linked_location_ids ->
          Repo.rollback(
            organization_changeset("character is not at an organization-linked location")
          )

        destination_location.id not in organization.linked_location_ids ->
          Repo.rollback(organization_changeset("destination is not linked to this organization"))

        true ->
          character
          |> Character.travel_changeset(%{current_location_id: destination_location.id})
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  defp fast_travel_memberships(location_id, character_id) do
    Membership
    |> join(:inner, [membership], organization in assoc(membership, :organization))
    |> join(:inner, [membership, organization], role in assoc(membership, :role))
    |> where(
      [membership, organization, role],
      membership.character_id == ^character_id and membership.status == :active and
        organization.status == :active and organization.fast_travel_enabled == true and
        ^location_id in organization.linked_location_ids and
        ^"grant_fast_travel" in role.permissions
    )
    |> preload([membership, organization, role], organization: organization, role: role)
    |> Repo.all()
  end

  defp active_membership_query do
    from membership in Membership,
      where: membership.status == :active,
      order_by: [asc: membership.joined_at],
      preload: [:character, :role]
  end

  defp active_membership!(organization_id, character_id) do
    Membership
    |> where(
      [membership],
      membership.organization_id == ^organization_id and membership.character_id == ^character_id and
        membership.status == :active
    )
    |> lock("FOR UPDATE")
    |> preload(:role)
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(organization_changeset("character is not an active organization member"))

      membership ->
        membership
    end
  end

  defp validate_permission!(membership, permission) do
    if permission in membership.role.permissions do
      :ok
    else
      Repo.rollback(organization_changeset("role lacks required permission #{permission}"))
    end
  end

  defp validate_invitation_response!(invitation, invitee) do
    cond do
      invitation.status != :pending ->
        Repo.rollback(organization_changeset("invitation is not pending"))

      invitation.invitee_character_id != invitee.id ->
        Repo.rollback(organization_changeset("invitation does not belong to this character"))

      true ->
        :ok
    end
  end

  defp normalize_kind(value) when value in @kinds, do: value
  defp normalize_kind("cult"), do: :cult
  defp normalize_kind("company"), do: :company
  defp normalize_kind("council"), do: :council
  defp normalize_kind("guild"), do: :guild
  defp normalize_kind(_value), do: nil

  defp default_role_code(:cult), do: "archbishop"
  defp default_role_code(:company), do: "director"
  defp default_role_code(:council), do: "chair"
  defp default_role_code(:guild), do: "master"

  defp default_role_title(:cult), do: "Archbishop"
  defp default_role_title(:company), do: "Director"
  defp default_role_title(:council), do: "Chair"
  defp default_role_title(:guild), do: "Guildmaster"

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_organization!(organization_id) do
    Organization
    |> where([organization], organization.id == ^organization_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(memberships: active_membership_query(), roles: [])
  end

  defp lock_invitation!(invitation_id) do
    Invitation
    |> where([invitation], invitation.id == ^invitation_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload([:organization, :role])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp organization_changeset(message) do
    %Organization{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
