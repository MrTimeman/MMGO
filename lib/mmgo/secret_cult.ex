defmodule MMGO.SecretCult do
  @moduledoc """
  The durable discovery and passage contract for the seeded Secret Cult.

  Discovery is personal state on the character, but passage is not a client
  flag: completing the two location-bound steps grants a real active
  organization membership whose role has the existing `grant_fast_travel`
  permission. From that point the normal organization travel code remains the
  only way to move the character.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.{Character, CharacterProfiles}
  alias MMGO.Organizations.{Membership, Organization, Role}
  alias MMGO.Repo
  alias MMGO.Worlds.Location

  @discovery_key "secret_cult_discovery"
  @stage_key "stage"
  @rumor_heard "rumor_heard"
  @passage_unlocked "passage_unlocked"
  @passage_role_code "passage-bearer"
  @passage_permission "grant_fast_travel"

  @doc "Repairs the maximum ordinary passage access granted to the sealed alpha profile."
  def ensure_maximum_passage_access(%Character{} = character) do
    case secret_cult_for_realm(character.realm_id) do
      nil ->
        {:error, :secret_cult_unavailable}

      %Organization{} ->
        Repo.transaction(fn ->
          character = lock_character!(character.id)

          unless CharacterProfiles.sealed_spirit?(character) and
                   CharacterProfiles.legendary_progression?(character) do
            Repo.rollback(:secret_cult_access_not_eligible)
          end

          organization = lock_secret_cult!(character.realm_id)
          passage_role = ensure_passage_role!(organization)
          membership = grant_maximum_passage_membership!(organization, character, passage_role)
          now = DateTime.utc_now()

          discovery =
            character
            |> discovery_metadata()
            |> Map.merge(%{
              @stage_key => @passage_unlocked,
              "passage_unlocked_at" => DateTime.to_iso8601(now),
              "progression_source" => "closed_alpha_maximum"
            })

          updated_character =
            character
            |> Character.changeset(%{
              metadata: Map.put(character.metadata || %{}, @discovery_key, discovery)
            })
            |> Repo.update!()

          %{
            character: updated_character,
            organization: organization,
            membership: membership,
            stage: :passage_unlocked
          }
        end)
    end
  end

  def ensure_maximum_passage_access(_character),
    do: {:error, :secret_cult_access_not_eligible}

  @doc "Returns only the current character's safe, presentation-ready discovery state."
  def discovery_state(%Character{} = character) do
    case secret_cult_for_realm(character.realm_id) do
      nil ->
        unavailable_state()

      %Organization{} = organization ->
        discovery = discovery_metadata(character)
        stage = discovery_stage(discovery)
        discovery_city_id = Map.get(organization.metadata || %{}, "discovery_city_id")
        discovery_watchtower_id = Map.get(organization.metadata || %{}, "discovery_watchtower_id")
        passage_available? = passage_membership?(organization.id, character.id)

        %{
          available?: is_binary(discovery_city_id) and is_binary(discovery_watchtower_id),
          organization_id: organization.id,
          organization_name: organization.name,
          stage: stage,
          passage_available?: passage_available?,
          passage_destinations:
            if(passage_available?,
              do: passage_destinations(organization, character.current_location_id),
              else: []
            ),
          can_hear_rumor?:
            stage == :unknown and character.current_location_id == discovery_city_id,
          can_reveal_passage?:
            stage == :rumor_heard and character.current_location_id == discovery_watchtower_id
        }
    end
  end

  def discovery_state(_character), do: unavailable_state()

  @doc "Filters secret organizations from a character's public directory and map until discovery."
  def visible_organizations(organizations, %Character{} = character)
      when is_list(organizations) do
    Enum.filter(organizations, fn
      %Organization{} = organization -> visible_to_character?(organization, character)
      _other -> false
    end)
  end

  def visible_organizations(organizations, _character) when is_list(organizations),
    do: organizations

  @doc "Secret Cult membership or a durable discovery stage is required before it becomes visible."
  def visible_to_character?(%Organization{} = organization, %Character{} = character) do
    not secret_cult?(organization) or
      discovery_stage(discovery_metadata(character)) != :unknown or
      passage_membership?(organization.id, character.id)
  end

  def visible_to_character?(_organization, _character), do: false

  @doc "Uses only the existing organization travel command after rechecking the real cult pass."
  def use_pass(%Character{} = character, destination_location_id)
      when is_binary(destination_location_id) do
    with %Character{} = character <-
           Repo.get(Character, character.id) |> Repo.preload(:current_location),
         %Organization{} = organization <- secret_cult_for_realm(character.realm_id),
         :passage_unlocked <- discovery_stage(discovery_metadata(character)),
         true <- passage_membership?(organization.id, character.id),
         %Location{} = destination <- Repo.get(Location, destination_location_id),
         true <- destination.realm_id == character.realm_id,
         true <- destination.id in organization.linked_location_ids do
      MMGO.Organizations.use_secret_passage(character, organization, destination)
    else
      nil -> {:error, :secret_cult_destination_not_found}
      false -> {:error, :secret_cult_destination_not_found}
      _other -> {:error, :secret_cult_passage_unavailable}
    end
  end

  def use_pass(_character, _destination_location_id),
    do: {:error, :secret_cult_passage_unavailable}

  @doc "Records the capital-city rumor only at the cult's configured discovery location."
  def hear_rumor(%Character{} = character) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      organization = lock_secret_cult!(character.realm_id)
      validate_discovery_location!(character, organization, "discovery_city_id")

      case discovery_stage(discovery_metadata(character)) do
        :unknown ->
          updated_character =
            character
            |> Character.changeset(%{
              metadata:
                Map.put(character.metadata || %{}, @discovery_key, %{
                  @stage_key => @rumor_heard,
                  "rumor_heard_at" => DateTime.to_iso8601(DateTime.utc_now())
                })
            })
            |> Repo.update!()

          %{character: updated_character, organization: organization, stage: :rumor_heard}

        :rumor_heard ->
          %{character: character, organization: organization, stage: :rumor_heard}

        :passage_unlocked ->
          Repo.rollback(:secret_cult_already_unlocked)
      end
    end)
  end

  @doc "Completes the watchtower step and grants the existing fast-travel permission through a real role."
  def reveal_passage(%Character{} = character) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      organization = lock_secret_cult!(character.realm_id)
      validate_discovery_location!(character, organization, "discovery_watchtower_id")

      if discovery_stage(discovery_metadata(character)) != :rumor_heard do
        Repo.rollback(:secret_cult_rumor_required)
      end

      passage_role = ensure_passage_role!(organization)
      membership = grant_passage_membership!(organization, character, passage_role)

      updated_character =
        character
        |> Character.changeset(%{
          metadata:
            Map.put(character.metadata || %{}, @discovery_key, %{
              @stage_key => @passage_unlocked,
              "passage_unlocked_at" => DateTime.to_iso8601(DateTime.utc_now())
            })
        })
        |> Repo.update!()

      %{
        character: updated_character,
        organization: organization,
        membership: membership,
        stage: :passage_unlocked
      }
    end)
  end

  defp unavailable_state do
    %{
      available?: false,
      organization_id: nil,
      organization_name: nil,
      stage: :unavailable,
      passage_available?: false,
      passage_destinations: [],
      can_hear_rumor?: false,
      can_reveal_passage?: false
    }
  end

  defp secret_cult_for_realm(realm_id) when is_binary(realm_id) do
    Organization
    |> where(
      [organization],
      organization.realm_id == ^realm_id and organization.status == :active
    )
    |> order_by([organization], asc: organization.inserted_at)
    |> Repo.all()
    |> Enum.find(fn organization ->
      organization.kind == :cult and Map.get(organization.metadata || %{}, "secret_cult") == true
    end)
  end

  defp secret_cult_for_realm(_realm_id), do: nil

  defp lock_secret_cult!(realm_id) do
    case secret_cult_for_realm(realm_id) do
      nil ->
        Repo.rollback(:secret_cult_unavailable)

      %Organization{} = organization ->
        locked_organization =
          Organization
          |> where([organization], organization.id == ^organization.id)
          |> lock("FOR UPDATE")
          |> Repo.one!()

        if secret_cult?(locked_organization) do
          locked_organization
        else
          Repo.rollback(:secret_cult_unavailable)
        end
    end
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp validate_discovery_location!(
         %Character{} = character,
         %Organization{} = organization,
         metadata_key
       ) do
    case Map.get(organization.metadata || %{}, metadata_key) do
      location_id when is_binary(location_id) and character.current_location_id == location_id ->
        :ok

      _other ->
        Repo.rollback(:secret_cult_wrong_location)
    end
  end

  defp ensure_passage_role!(%Organization{} = organization) do
    Role
    |> where(
      [role],
      role.organization_id == ^organization.id and role.code == ^@passage_role_code
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Role{} = role ->
        permissions = Enum.uniq((role.permissions || []) ++ [@passage_permission])

        if permissions == role.permissions do
          role
        else
          role
          |> Role.changeset(%{permissions: permissions})
          |> Repo.update!()
        end

      nil ->
        %Role{}
        |> Role.changeset(%{
          organization_id: organization.id,
          code: @passage_role_code,
          title: "Носитель прохода",
          rank: 1,
          permissions: [@passage_permission]
        })
        |> Repo.insert!()
    end
  end

  defp grant_passage_membership!(
         %Organization{} = organization,
         %Character{} = character,
         %Role{} = role
       ) do
    membership =
      Membership
      |> where(
        [membership],
        membership.organization_id == ^organization.id and
          membership.character_id == ^character.id and
          membership.status == :active
      )
      |> lock("FOR UPDATE")
      |> preload(:role)
      |> Repo.one()

    cond do
      is_nil(membership) ->
        %Membership{}
        |> Membership.changeset(%{
          organization_id: organization.id,
          character_id: character.id,
          role_id: role.id,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{"source" => "secret_cult_discovery"}
        })
        |> Repo.insert!()

      @passage_permission in membership.role.permissions ->
        membership

      true ->
        # A pre-existing cult member may hold a role with other authority.
        # Discovery must never silently demote that role just to grant a pass.
        # Their passage remains a deliberate organization-governance decision.
        Repo.rollback(:secret_cult_existing_membership_requires_passage_role)
    end
  end

  defp grant_maximum_passage_membership!(organization, character, role) do
    membership =
      Membership
      |> where(
        [membership],
        membership.organization_id == ^organization.id and
          membership.character_id == ^character.id and membership.status == :active
      )
      |> lock("FOR UPDATE")
      |> preload(:role)
      |> Repo.one()

    cond do
      is_nil(membership) ->
        %Membership{}
        |> Membership.changeset(%{
          organization_id: organization.id,
          character_id: character.id,
          role_id: role.id,
          status: :active,
          joined_at: DateTime.utc_now(),
          metadata: %{"source" => "closed_alpha_maximum"}
        })
        |> Repo.insert!()

      @passage_permission in membership.role.permissions ->
        membership

      true ->
        augmented_role =
          ensure_augmented_passage_role!(organization, character, membership.role)

        membership
        |> Membership.changeset(%{
          role_id: augmented_role.id,
          metadata:
            Map.merge(membership.metadata || %{}, %{
              "source" => "closed_alpha_maximum",
              "previous_role_id" => membership.role_id
            })
        })
        |> Repo.update!()
    end
  end

  defp ensure_augmented_passage_role!(organization, character, existing_role) do
    code = "sealed-passage-#{character.id}"

    role =
      Role
      |> where([role], role.organization_id == ^organization.id and role.code == ^code)
      |> lock("FOR UPDATE")
      |> Repo.one()

    attrs = %{
      organization_id: organization.id,
      code: code,
      title: existing_role.title,
      rank: existing_role.rank,
      permissions: Enum.uniq((existing_role.permissions || []) ++ [@passage_permission]),
      metadata:
        Map.merge(existing_role.metadata || %{}, %{
          "source" => "closed_alpha_maximum",
          "base_role_id" => existing_role.id
        })
    }

    (role || %Role{})
    |> Role.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  defp discovery_metadata(%Character{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, @discovery_key, %{}) do
      discovery when is_map(discovery) -> discovery
      _other -> %{}
    end
  end

  defp discovery_metadata(_character), do: %{}

  defp discovery_stage(discovery) when is_map(discovery) do
    case Map.get(discovery, @stage_key) do
      @rumor_heard -> :rumor_heard
      @passage_unlocked -> :passage_unlocked
      _other -> :unknown
    end
  end

  defp passage_membership?(organization_id, character_id) do
    Repo.exists?(
      from membership in Membership,
        join: role in Role,
        on: role.id == membership.role_id,
        where:
          membership.organization_id == ^organization_id and
            membership.character_id == ^character_id and
            membership.status == :active and ^@passage_permission in role.permissions
    )
  end

  defp passage_destinations(%Organization{} = organization, current_location_id) do
    organization.linked_location_ids
    |> Enum.reject(&(&1 == current_location_id))
    |> then(fn location_ids ->
      Location
      |> where([location], location.id in ^location_ids)
      |> order_by([location], asc: location.name)
      |> Repo.all()
      |> Enum.map(&%{id: &1.id, name: &1.name})
    end)
  end

  defp secret_cult?(%Organization{} = organization) do
    organization.status == :active and organization.kind == :cult and
      Map.get(organization.metadata || %{}, "secret_cult") == true
  end
end
