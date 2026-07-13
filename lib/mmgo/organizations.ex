defmodule MMGO.Organizations do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Notifications
  alias MMGO.Organizations.{Invitation, Membership, Organization, Role}
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds.{Location, Realm}

  @kinds [:cult, :company, :council, :guild]
  @treasury_permission "manage_treasury"
  @role_permissions ["invite_members", "manage_roles", @treasury_permission, "grant_fast_travel"]
  @leadership_selection_modes [
    "founder_appointment",
    "member_election",
    "share_weighted_election"
  ]
  @leader_exit_modes ["highest_rank_member", "vacant"]
  @membership_admission_modes ["invitation_only", "open"]
  @treasury_decision_modes ["role_permission", "member_referendum"]
  @role_treasury_payout_limit_key "treasury_direct_payout_limit"
  @governance_proposals_key "governance_proposals"
  @governance_proposal_history_limit 30
  @ownership_key "ownership"
  @treasury_shares_key "treasury_shares_bps"
  @organization_share_key "organization"
  @share_basis_points 10_000
  @diplomacy_relationship_kinds ["alliance", "rivalry", "war"]
  @diplomacy_relationships_key "diplomacy_relationships"
  @diplomacy_relationship_history_limit 30
  @fast_travel_tolls_key "fast_travel_tolls"
  @fast_travel_toll_tax_rate_bps 500

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

  def list_active_organizations_for_realm(realm_id) when is_binary(realm_id) do
    Organization
    |> where(
      [organization],
      organization.realm_id == ^realm_id and organization.status == :active
    )
    |> order_by([organization], asc: organization.inserted_at)
    |> Repo.all()
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
          hierarchy_rules: hierarchy_rules_for(attrs),
          fast_travel_enabled: attrs["fast_travel_enabled"] || false,
          linked_location_ids: attrs["linked_location_ids"] || [],
          metadata: organization_metadata_for(attrs, founder)
        })
        |> Repo.insert!()

      leader_role =
        %Role{}
        |> Role.changeset(%{
          organization_id: organization.id,
          code: default_role_code(kind),
          title: default_role_title(kind),
          rank: 100,
          permissions: [
            "invite_members",
            "manage_roles",
            @treasury_permission,
            "grant_fast_travel"
          ]
        })
        |> Repo.insert!()

      member_role =
        %Role{}
        |> Role.changeset(%{
          organization_id: organization.id,
          code: "open-member",
          title: "Member",
          rank: 0,
          permissions: []
        })
        |> Repo.insert!()

      treasury_account =
        case Economy.ensure_organization_account(organization) do
          {:ok, account} -> account
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end

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
        role: leader_role,
        member_role: member_role,
        treasury_account: treasury_account
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

      if not custom_roles_allowed?(organization) do
        Repo.rollback(
          organization_changeset("organization constitution does not permit custom roles")
        )
      end

      rank = attrs["rank"] || 10
      permissions = attrs["permissions"] || []

      if not valid_custom_role_rank?(rank) do
        Repo.rollback(organization_changeset("custom role rank must be between 0 and 99"))
      end

      if rank >= membership.role.rank do
        Repo.rollback(
          organization_changeset("custom role rank must remain below the creator role")
        )
      end

      if not valid_role_permissions?(permissions) do
        Repo.rollback(organization_changeset("custom role permissions are invalid"))
      end

      if not Enum.all?(permissions, &(&1 in membership.role.permissions)) do
        Repo.rollback(
          organization_changeset("custom role cannot grant permissions the creator does not hold")
        )
      end

      %Role{}
      |> Role.changeset(%{
        organization_id: organization.id,
        code: attrs["code"],
        title: attrs["title"],
        rank: rank,
        permissions: permissions
      })
      |> Repo.insert!()
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns the durable admission block for an organization constitution."
  def membership_state(%Organization{} = organization) do
    %{
      admission: membership_admission(organization),
      open?: membership_admission(organization) == "open"
    }
  end

  def membership_state(_organization), do: %{admission: "invitation_only", open?: false}

  @doc "Returns the durable leader-exit succession block for an organization constitution."
  def succession_state(%Organization{} = organization) do
    %{on_leader_exit: leader_exit_mode(organization)}
  end

  def succession_state(_organization), do: %{on_leader_exit: "highest_rank_member"}

  @doc "Configures whether a departing leader is replaced by rank or leaves the office vacant."
  def configure_leader_exit_succession(
        %Organization{} = organization,
        %Character{} = actor,
        on_leader_exit
      )
      when on_leader_exit in @leader_exit_modes do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      succession_block =
        case Map.get(organization.hierarchy_rules || %{}, "succession") do
          block when is_map(block) -> block
          _other -> %{}
        end

      organization
      |> Organization.changeset(%{
        hierarchy_rules:
          Map.put(
            organization.hierarchy_rules || %{},
            "succession",
            Map.put(succession_block, "on_leader_exit", on_leader_exit)
          )
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_leader_exit_succession(_organization, _actor, _on_leader_exit),
    do: {:error, organization_changeset("leader exit succession is invalid")}

  @doc "Configures whether an organization accepts only invitations or safe open enrollment."
  def configure_membership_admission(
        %Organization{} = organization,
        %Character{} = actor,
        admission
      )
      when admission in @membership_admission_modes do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      membership_block =
        case Map.get(organization.hierarchy_rules || %{}, "membership") do
          block when is_map(block) -> block
          _other -> %{}
        end

      organization
      |> Organization.changeset(%{
        hierarchy_rules:
          Map.put(
            organization.hierarchy_rules || %{},
            "membership",
            Map.put(membership_block, "admission", admission)
          )
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_membership_admission(_organization, _actor, _admission),
    do: {:error, organization_changeset("organization membership admission is invalid")}

  @doc "Joins an organization only when its durable admission block permits open enrollment."
  def join_open_organization(%Organization{} = organization, %Character{} = character) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      character = lock_character!(character.id)

      cond do
        membership_admission(organization) != "open" ->
          Repo.rollback(organization_changeset("organization is invitation-only"))

        character.realm_id != organization.realm_id ->
          Repo.rollback(organization_changeset("organization belongs to another realm"))

        Repo.exists?(
          from membership in Membership,
            where:
              membership.organization_id == ^organization.id and
                membership.character_id == ^character.id and membership.status == :active
        ) ->
          Repo.rollback(
            organization_changeset("character is already an active organization member")
          )

        true ->
          role = open_membership_role!(organization)

          %Membership{}
          |> Membership.changeset(%{
            organization_id: organization.id,
            character_id: character.id,
            role_id: role.id,
            status: :active,
            joined_at: DateTime.utc_now(),
            metadata: %{"admission" => "open"}
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns active relationships and inbound requests addressed to one organization."
  def diplomacy_state(%Organization{} = organization) do
    %{
      relationships: diplomacy_relationships(organization.metadata || %{}),
      incoming_requests:
        organization.metadata
        |> governance_proposals()
        |> Enum.filter(fn proposal ->
          Map.get(proposal, "kind") == "diplomacy_request" and
            Map.get(proposal, "status") == "open" and
            Map.get(proposal, "target_organization_id") == organization.id
        end)
    }
  end

  def diplomacy_state(_organization), do: %{relationships: [], incoming_requests: []}

  @doc "Sends one same-realm alliance or rivalry request that the other organization must accept."
  def propose_diplomacy(
        source_organization,
        actor,
        target_organization,
        relationship_kind,
        opts \\ []
      )

  def propose_diplomacy(
        %Organization{} = source_organization,
        %Character{} = actor,
        %Organization{} = target_organization,
        relationship_kind,
        opts
      )
      when relationship_kind in @diplomacy_relationship_kinds do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      organizations = lock_organization_pair!(source_organization.id, target_organization.id)
      source_organization = Map.fetch!(organizations, source_organization.id)
      target_organization = Map.fetch!(organizations, target_organization.id)
      membership = active_membership!(source_organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      cond do
        source_organization.id == target_organization.id ->
          Repo.rollback(organization_changeset("organization cannot send diplomacy to itself"))

        source_organization.realm_id != target_organization.realm_id ->
          Repo.rollback(organization_changeset("diplomacy target must belong to the same realm"))

        relationship_exists?(source_organization, target_organization.id) ->
          Repo.rollback(
            organization_changeset("organizations already have a diplomatic relationship")
          )

        diplomacy_request_open?(target_organization, source_organization.id) ->
          Repo.rollback(
            organization_changeset("a diplomacy request is already awaiting a response")
          )

        true ->
          proposal =
            new_diplomacy_request(
              source_organization,
              target_organization,
              actor.id,
              relationship_kind,
              now
            )

          target_organization
          |> Organization.changeset(%{
            metadata: append_governance_proposal(target_organization.metadata || %{}, proposal)
          })
          |> Repo.update!()
          |> then(
            &%{
              source_organization: source_organization,
              target_organization: &1,
              proposal: proposal
            }
          )
      end
    end)
    |> normalize_transaction_result()
  end

  def propose_diplomacy(
        _source_organization,
        _actor,
        _target_organization,
        _relationship_kind,
        _opts
      ),
      do: {:error, organization_changeset("diplomacy request is invalid")}

  @doc "Accepts or rejects a durable diplomacy request using the target organization's real role authority."
  def respond_to_diplomacy_request(target_organization, actor, proposal_id, decision, opts \\ [])

  def respond_to_diplomacy_request(
        %Organization{} = target_organization,
        %Character{} = actor,
        proposal_id,
        decision,
        opts
      )
      when is_binary(proposal_id) and decision in [:accept, :reject] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with source_organization_id when is_binary(source_organization_id) <-
           pending_diplomacy_source_id(target_organization.id, proposal_id) do
      Repo.transaction(fn ->
        organizations = lock_organization_pair!(target_organization.id, source_organization_id)
        target_organization = Map.fetch!(organizations, target_organization.id)
        source_organization = Map.fetch!(organizations, source_organization_id)
        membership = active_membership!(target_organization.id, actor.id)
        validate_permission!(membership, "manage_roles")

        proposal =
          target_organization.metadata
          |> governance_proposals()
          |> Enum.find(fn proposal ->
            Map.get(proposal, "id") == proposal_id and
              Map.get(proposal, "kind") == "diplomacy_request" and
              Map.get(proposal, "status") == "open" and
              Map.get(proposal, "source_organization_id") == source_organization.id
          end)

        if is_nil(proposal) do
          Repo.rollback(organization_changeset("diplomacy request is no longer open"))
        end

        case decision do
          :reject ->
            proposal = resolve_diplomacy_request(proposal, :rejected, now)

            target_organization
            |> replace_governance_proposal!(proposal)
            |> then(
              &%{
                target_organization: &1,
                source_organization: source_organization,
                resolution: :rejected
              }
            )

          :accept ->
            relationship_kind = Map.get(proposal, "relationship_kind")

            if relationship_kind not in @diplomacy_relationship_kinds do
              Repo.rollback(organization_changeset("diplomacy relationship kind is invalid"))
            end

            if relationship_exists?(source_organization, target_organization.id) do
              Repo.rollback(
                organization_changeset("organizations already have a diplomatic relationship")
              )
            end

            proposal = resolve_diplomacy_request(proposal, :accepted, now)

            target_relationship =
              new_diplomacy_relationship(source_organization.id, relationship_kind, now)

            source_relationship =
              new_diplomacy_relationship(target_organization.id, relationship_kind, now)

            target_organization =
              target_organization
              |> Organization.changeset(%{
                metadata:
                  target_organization.metadata
                  |> replace_governance_proposal_metadata(proposal)
                  |> append_diplomacy_relationship(target_relationship)
              })
              |> Repo.update!()

            source_organization =
              source_organization
              |> Organization.changeset(%{
                metadata:
                  source_organization.metadata
                  |> append_diplomacy_relationship(source_relationship)
              })
              |> Repo.update!()

            %{
              target_organization: target_organization,
              source_organization: source_organization,
              resolution: :accepted,
              relationship: target_relationship
            }
        end
      end)
      |> normalize_transaction_result()
    else
      _other -> {:error, organization_changeset("diplomacy request is unavailable")}
    end
  end

  def respond_to_diplomacy_request(_target_organization, _actor, _proposal_id, _decision, _opts),
    do: {:error, organization_changeset("diplomacy response is invalid")}

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

      if role.organization_id != organization.id do
        Repo.rollback(organization_changeset("invitation role must belong to this organization"))
      end

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

      role =
        Role
        |> where(
          [role],
          role.id == ^invitation.role_id and role.organization_id == ^invitation.organization_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(role) do
        Repo.rollback(
          organization_changeset("invitation role does not belong to this organization")
        )
      end

      membership =
        %Membership{}
        |> Membership.changeset(%{
          organization_id: invitation.organization_id,
          character_id: invitee.id,
          role_id: role.id,
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
      now = DateTime.utc_now()
      organization = lock_organization!(organization.id)
      memberships = lock_active_memberships!(organization.id)

      membership = Enum.find(memberships, &(&1.character_id == character.id))

      if is_nil(membership) do
        Repo.rollback(organization_changeset("character is not an active organization member"))
      end

      organization = cancel_governance_votes_for_departure!(organization, character.id, now)

      successor =
        if character.id == leader_character_id(organization) do
          successor = leader_exit_successor(organization, memberships, character.id)

          if successor do
            transfer_leadership!(organization, memberships, successor.character_id)
          end

          successor
        end

      membership =
        membership
        |> Membership.changeset(%{status: :left, left_at: now})
        |> Repo.update!()

      if character.id == leader_character_id(organization) do
        organization
        |> Organization.changeset(%{
          metadata:
            Map.put(
              organization.metadata || %{},
              "leader_character_id",
              successor && successor.character_id
            )
        })
        |> Repo.update!()
      end

      membership
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns the real economy account that holds an organization's treasury."
  def treasury_account(%Organization{} = organization) do
    Economy.organization_account_for_organization(organization)
  end

  def treasury_account(_organization), do: nil

  @doc "Returns the durable ownership-share ledger for an organization's treasury asset."
  def treasury_ownership_state(%Organization{} = organization) do
    shares = treasury_shares(organization.metadata || %{})

    %{
      shares: shares,
      organization_share_bps: Map.get(shares, @organization_share_key, @share_basis_points),
      member_share_bps:
        shares
        |> Map.delete(@organization_share_key)
        |> Map.new(fn {participant, share_bps} ->
          {share_character_id(participant), share_bps}
        end)
    }
  end

  def treasury_ownership_state(_organization),
    do: %{
      shares: %{@organization_share_key => @share_basis_points},
      organization_share_bps: @share_basis_points,
      member_share_bps: %{}
    }

  @doc "Assigns a member's durable treasury-share percentage while preserving a closed 10,000 bps cap."
  def assign_treasury_share(
        %Organization{} = organization,
        %Character{} = actor,
        %Character{} = member,
        share_bps
      )
      when is_integer(share_bps) and share_bps in 0..@share_basis_points do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      actor_membership = active_membership!(organization.id, actor.id)
      memberships = lock_active_memberships!(organization.id)
      validate_permission!(actor_membership, @treasury_permission)

      if is_nil(Enum.find(memberships, &(&1.character_id == member.id))) do
        Repo.rollback(
          organization_changeset("share holder must be an active organization member")
        )
      end

      shares = treasury_shares(organization.metadata || %{})
      participant = character_share_key(member.id)

      other_share_total =
        shares
        |> Map.delete(@organization_share_key)
        |> Map.delete(participant)
        |> Map.values()
        |> Enum.sum()

      if other_share_total + share_bps > @share_basis_points do
        Repo.rollback(organization_changeset("treasury shares cannot exceed 100 percent"))
      end

      shares =
        shares
        |> Map.put(@organization_share_key, @share_basis_points - other_share_total - share_bps)
        |> put_or_delete_share(participant, share_bps)

      organization
      |> Organization.changeset(%{
        metadata: put_treasury_shares(organization.metadata || %{}, shares)
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def assign_treasury_share(_organization, _actor, _member, _share_bps),
    do: {:error, organization_changeset("treasury share assignment is invalid")}

  @doc "Returns the organization constitution's treasury decision block and its open referendum."
  def treasury_policy_state(%Organization{} = organization) do
    %{
      decision: treasury_decision(organization),
      open_referendum: treasury_open_referendum(organization)
    }
  end

  def treasury_policy_state(_organization),
    do: %{decision: "role_permission", open_referendum: nil}

  @doc "Returns a role's direct-payout ceiling, or nil when it has no ceiling."
  def treasury_role_payout_limit(%Role{} = role) do
    case Map.get(role.metadata || %{}, @role_treasury_payout_limit_key) do
      limit when is_integer(limit) and limit >= 0 -> limit
      _other -> nil
    end
  end

  def treasury_role_payout_limit(_role), do: nil

  @doc "Sets a role's direct treasury-payout ceiling; larger payouts require a referendum."
  def configure_treasury_role_payout_limit(
        %Organization{} = organization,
        %Character{} = actor,
        %Role{} = role,
        limit
      )
      when is_nil(limit) or (is_integer(limit) and limit >= 0) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      if treasury_open_referendum(organization) do
        Repo.rollback(
          organization_changeset(
            "resolve the current treasury referendum before changing role payout limits"
          )
        )
      end

      role = lock_organization_role!(organization.id, role.id)

      metadata =
        case limit do
          nil ->
            Map.delete(role.metadata || %{}, @role_treasury_payout_limit_key)

          direct_payout_limit ->
            Map.put(role.metadata || %{}, @role_treasury_payout_limit_key, direct_payout_limit)
        end

      role
      |> Role.changeset(%{metadata: metadata})
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_treasury_role_payout_limit(_organization, _actor, _role, _limit),
    do: {:error, organization_changeset("treasury role payout limit is invalid")}

  @doc "Changes whether routine treasury payouts are role-authorized or require a member referendum."
  def configure_treasury_decision(%Organization{} = organization, %Character{} = actor, decision)
      when decision in @treasury_decision_modes do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      if decision != treasury_decision(organization) and treasury_open_referendum(organization) do
        Repo.rollback(
          organization_changeset(
            "resolve the current treasury referendum before changing this rule"
          )
        )
      end

      treasury_block =
        case Map.get(organization.hierarchy_rules || %{}, "treasury") do
          block when is_map(block) -> block
          _other -> %{}
        end

      organization
      |> Organization.changeset(%{
        hierarchy_rules:
          Map.put(
            organization.hierarchy_rules || %{},
            "treasury",
            Map.put(treasury_block, "decision", decision)
          )
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_treasury_decision(_organization, _actor, _decision),
    do: {:error, organization_changeset("treasury decision rule is invalid")}

  @doc "Pays the member-owned portion of a declared treasury profit in one atomic ledger split."
  def distribute_treasury_dividend(
        %Organization{} = organization,
        %Character{} = actor,
        gross_amount
      )
      when is_integer(gross_amount) and gross_amount > 0 do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, @treasury_permission)

      allocations = treasury_dividend_allocations(organization, gross_amount)

      if allocations == [] do
        Repo.rollback(organization_changeset("treasury profit has no member share holders"))
      end

      characters =
        allocations
        |> Enum.map(& &1.character_id)
        |> lock_characters!()

      recipient_accounts =
        Enum.map(allocations, fn allocation ->
          character = Map.fetch!(characters, allocation.character_id)

          if character.realm_id != organization.realm_id do
            Repo.rollback(
              organization_changeset("treasury share holder belongs to another realm")
            )
          end

          case Economy.ensure_character_account(character) do
            {:ok, account} -> Map.put(allocation, :account, account)
            {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          end
        end)

      with {:ok, organization_account} <- Economy.ensure_organization_account(organization),
           {:ok, transfer} <-
             Economy.transfer_many(
               organization_account,
               Enum.map(recipient_accounts, fn recipient ->
                 %{
                   credit_account: recipient.account,
                   amount: recipient.amount,
                   metadata: %{
                     "recipient_character_id" => recipient.character_id,
                     "share_bps" => recipient.share_bps
                   }
                 }
               end),
               %{
                 entry_type: "transfer",
                 source: "organization_treasury_dividend",
                 organization_id: organization.id,
                 actor_character_id: actor.id,
                 gross_amount: gross_amount,
                 organization_retained_amount:
                   gross_amount -
                     Enum.reduce(recipient_accounts, 0, &(&1.amount + &2))
               }
             ) do
        %{
          transfer: transfer,
          allocations: recipient_accounts,
          treasury_account: transfer.debit_account
        }
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def distribute_treasury_dividend(_organization, _actor, _gross_amount),
    do: {:error, organization_changeset("treasury dividend is unavailable")}

  @doc "Moves a member's own funds into the organization treasury."
  def deposit_to_treasury(%Organization{} = organization, %Character{} = member, amount)
      when is_integer(amount) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      _membership = active_membership!(organization.id, member.id)
      member = lock_character!(member.id)

      with {:ok, member_account} <- Economy.ensure_character_account(member),
           {:ok, organization_account} <- Economy.ensure_organization_account(organization),
           {:ok, transfer} <-
             Economy.transfer(member_account, organization_account, amount, %{
               entry_type: "transfer",
               source: "organization_treasury_deposit",
               organization_id: organization.id,
               actor_character_id: member.id
             }) do
        %{transfer: transfer, treasury_account: transfer.credit_account}
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def deposit_to_treasury(_organization, _member, _amount),
    do: {:error, organization_changeset("treasury deposit is unavailable")}

  @doc "Pays organization treasury funds to a same-realm recipient under a real role permission."
  def withdraw_from_treasury(
        %Organization{} = organization,
        %Character{} = actor,
        %Character{} = recipient,
        amount
      )
      when is_integer(amount) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, @treasury_permission)
      recipient = lock_character!(recipient.id)

      if treasury_referendum_required?(organization, membership.role, amount) do
        Repo.rollback(organization_changeset("treasury spending requires a member referendum"))
      end

      if recipient.realm_id != organization.realm_id do
        Repo.rollback(organization_changeset("treasury recipient must belong to the same realm"))
      end

      with {:ok, organization_account} <- Economy.ensure_organization_account(organization),
           {:ok, recipient_account} <- Economy.ensure_character_account(recipient),
           {:ok, transfer} <-
             Economy.transfer(organization_account, recipient_account, amount, %{
               entry_type: "transfer",
               source: "organization_treasury_withdrawal",
               organization_id: organization.id,
               actor_character_id: actor.id,
               recipient_character_id: recipient.id
             }) do
        %{transfer: transfer, treasury_account: transfer.debit_account}
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def withdraw_from_treasury(_organization, _actor, _recipient, _amount),
    do: {:error, organization_changeset("treasury withdrawal is unavailable")}

  @doc "Opens a member referendum for one real, same-realm treasury payout."
  def propose_treasury_withdrawal(organization, proposer, recipient, amount, opts \\ [])

  def propose_treasury_withdrawal(
        %Organization{} = organization,
        %Character{} = proposer,
        %Character{} = recipient,
        amount,
        opts
      )
      when is_integer(amount) and amount > 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      memberships = lock_active_memberships!(organization.id)
      proposer_membership = Enum.find(memberships, &(&1.character_id == proposer.id))
      recipient = lock_character!(recipient.id)

      if is_nil(proposer_membership) do
        Repo.rollback(organization_changeset("treasury proposer is not an active member"))
      end

      validate_permission!(proposer_membership, @treasury_permission)

      cond do
        not treasury_referendum_required?(organization, proposer_membership.role, amount) ->
          Repo.rollback(
            organization_changeset("treasury payout does not require a member referendum")
          )

        recipient.realm_id != organization.realm_id ->
          Repo.rollback(
            organization_changeset("treasury recipient must belong to the same realm")
          )

        treasury_open_referendum(organization) ->
          Repo.rollback(organization_changeset("a treasury referendum is already open"))

        true ->
          proposal = new_treasury_referendum(proposer.id, recipient.id, amount, memberships, now)

          organization
          |> Organization.changeset(%{
            metadata: append_governance_proposal(organization.metadata || %{}, proposal)
          })
          |> Repo.update!()
          |> then(&%{organization: &1, proposal: proposal})
      end
    end)
    |> normalize_transaction_result()
  end

  def propose_treasury_withdrawal(_organization, _proposer, _recipient, _amount, _opts),
    do: {:error, organization_changeset("treasury referendum is unavailable")}

  @doc "Records an immutable member vote and settles an accepted treasury referendum once."
  def cast_treasury_vote(organization, voter, proposal_id, vote, opts \\ [])

  def cast_treasury_vote(
        %Organization{} = organization,
        %Character{} = voter,
        proposal_id,
        vote,
        opts
      )
      when is_binary(proposal_id) and vote in [:approve, :reject] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      memberships = lock_active_memberships!(organization.id)

      proposal =
        organization.metadata
        |> governance_proposals()
        |> Enum.find(fn proposal ->
          Map.get(proposal, "id") == proposal_id and
            Map.get(proposal, "kind") == "treasury_withdrawal" and
            Map.get(proposal, "status") == "open"
        end)

      cond do
        is_nil(proposal) ->
          Repo.rollback(organization_changeset("treasury referendum is not open"))

        is_nil(Enum.find(memberships, &(&1.character_id == voter.id))) ->
          Repo.rollback(organization_changeset("voter is not an active member"))

        voter.id not in proposal_voter_ids(proposal) ->
          Repo.rollback(organization_changeset("voter is not part of this treasury referendum"))

        Map.has_key?(proposal_votes(proposal), voter.id) ->
          Repo.rollback(
            organization_changeset("member has already voted in this treasury referendum")
          )

        true ->
          proposal = put_leadership_vote(proposal, voter.id, vote, now)

          case member_election_resolution(proposal) do
            :pending ->
              updated_organization = replace_governance_proposal!(organization, proposal)
              %{organization: updated_organization, proposal: proposal, resolution: :pending}

            :rejected ->
              proposal = resolve_leadership_proposal(proposal, :rejected, now)
              updated_organization = replace_governance_proposal!(organization, proposal)
              %{organization: updated_organization, proposal: proposal, resolution: :rejected}

            :accepted ->
              recipient_character_id = Map.get(proposal, "recipient_character_id")
              amount = Map.get(proposal, "amount")

              if not is_binary(recipient_character_id) or not is_integer(amount) or amount <= 0 do
                Repo.rollback(organization_changeset("treasury referendum payload is invalid"))
              end

              recipient = lock_character!(recipient_character_id)

              if recipient.realm_id != organization.realm_id do
                Repo.rollback(organization_changeset("treasury referendum payload is invalid"))
              end

              with {:ok, organization_account} <-
                     Economy.ensure_organization_account(organization),
                   {:ok, recipient_account} <- Economy.ensure_character_account(recipient),
                   {:ok, transfer} <-
                     Economy.transfer(organization_account, recipient_account, amount, %{
                       entry_type: "transfer",
                       source: "organization_treasury_referendum",
                       organization_id: organization.id,
                       proposal_id: proposal_id,
                       proposer_character_id: Map.get(proposal, "proposer_character_id"),
                       approved_by_character_id: voter.id,
                       recipient_character_id: recipient.id
                     }) do
                proposal =
                  proposal
                  |> resolve_leadership_proposal(:accepted, now)
                  |> Map.put("settled_at", DateTime.to_iso8601(now))
                  |> Map.put("ledger_entry_ids", Enum.map(transfer.ledger_entries, & &1.id))

                updated_organization = replace_governance_proposal!(organization, proposal)

                %{
                  organization: updated_organization,
                  proposal: proposal,
                  transfer: transfer,
                  treasury_account: transfer.debit_account,
                  resolution: :accepted
                }
              else
                {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
              end
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def cast_treasury_vote(_organization, _voter, _proposal_id, _vote, _opts),
    do: {:error, organization_changeset("treasury referendum vote is unavailable")}

  @doc "Returns the active leadership block and its current election, if any."
  def leadership_state(%Organization{} = organization) do
    proposals = governance_proposals(organization.metadata || %{})

    %{
      selection: leadership_selection(organization),
      leader_character_id: leader_character_id(organization),
      open_election:
        Enum.find(proposals, fn proposal ->
          Map.get(proposal, "kind") == "leadership_election" and
            Map.get(proposal, "status") == "open"
        end)
    }
  end

  def leadership_state(_organization),
    do: %{selection: "founder_appointment", leader_character_id: nil, open_election: nil}

  @doc "Configures the composable leadership-selection block in an organization constitution."
  def configure_leadership_selection(
        %Organization{} = organization,
        %Character{} = actor,
        selection
      )
      when selection in @leadership_selection_modes do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, "manage_roles")

      if selection != leadership_selection(organization) and
           leadership_state(organization).open_election do
        Repo.rollback(
          organization_changeset(
            "resolve the current leadership election before changing this rule"
          )
        )
      end

      leadership_block =
        case Map.get(organization.hierarchy_rules || %{}, "leadership") do
          block when is_map(block) -> block
          _other -> %{}
        end

      organization
      |> Organization.changeset(%{
        hierarchy_rules:
          Map.put(
            organization.hierarchy_rules || %{},
            "leadership",
            Map.put(leadership_block, "selection", selection)
          )
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_leadership_selection(_organization, _actor, _selection),
    do: {:error, organization_changeset("leadership selection is invalid")}

  @doc "Appoints an active member as leader when the constitution reserves that power to the founder."
  def appoint_leader(
        %Organization{} = organization,
        %Character{} = founder,
        %Character{} = candidate
      ) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      memberships = lock_active_memberships!(organization.id)

      cond do
        leadership_selection(organization) != "founder_appointment" ->
          Repo.rollback(
            organization_changeset("founder appointment is not enabled by this constitution")
          )

        organization.founder_character_id != founder.id ->
          Repo.rollback(
            organization_changeset("only the organization founder can appoint a leader")
          )

        is_nil(Enum.find(memberships, &(&1.character_id == founder.id))) ->
          Repo.rollback(organization_changeset("organization founder is not an active member"))

        is_nil(Enum.find(memberships, &(&1.character_id == candidate.id))) ->
          Repo.rollback(organization_changeset("leadership candidate is not an active member"))

        candidate.id == leader_character_id(organization) ->
          Repo.rollback(organization_changeset("leadership candidate already holds this role"))

        not is_nil(leadership_state(organization).open_election) ->
          Repo.rollback(
            organization_changeset(
              "resolve the current leadership election before appointing a leader"
            )
          )

        true ->
          transfer_leadership!(organization, memberships, candidate.id)

          organization
          |> Organization.changeset(%{
            metadata: Map.put(organization.metadata || %{}, "leader_character_id", candidate.id)
          })
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  def appoint_leader(_organization, _founder, _candidate),
    do: {:error, organization_changeset("founder appointment is unavailable")}

  @doc "Opens one durable member-election proposal for an active organization member."
  def open_leadership_election(organization, proposer, candidate, opts \\ [])

  def open_leadership_election(
        %Organization{} = organization,
        %Character{} = proposer,
        %Character{} = candidate,
        opts
      ) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      candidate = lock_character!(candidate.id)
      memberships = lock_active_memberships!(organization.id)

      cond do
        leadership_selection(organization) not in ["member_election", "share_weighted_election"] ->
          Repo.rollback(
            organization_changeset(
              "member or share elections are not enabled by this constitution"
            )
          )

        candidate.realm_id != organization.realm_id ->
          Repo.rollback(
            organization_changeset("leadership candidate must belong to the same realm")
          )

        is_nil(Enum.find(memberships, &(&1.character_id == proposer.id))) ->
          Repo.rollback(organization_changeset("election proposer is not an active member"))

        is_nil(Enum.find(memberships, &(&1.character_id == candidate.id))) ->
          Repo.rollback(organization_changeset("leadership candidate is not an active member"))

        candidate.id == leader_character_id(organization) ->
          Repo.rollback(organization_changeset("leadership candidate already holds this role"))

        not is_nil(leadership_state(organization).open_election) ->
          Repo.rollback(organization_changeset("a leadership election is already open"))

        true ->
          case new_leadership_election(
                 candidate.id,
                 memberships,
                 leadership_selection(organization),
                 treasury_shares(organization.metadata || %{}),
                 now
               ) do
            {:ok, proposal} ->
              organization
              |> Organization.changeset(%{
                metadata: append_governance_proposal(organization.metadata || %{}, proposal)
              })
              |> Repo.update!()
              |> then(&%{organization: &1, proposal: proposal})

            {:error, :no_share_voters} ->
              Repo.rollback(
                organization_changeset(
                  "share-weighted election requires at least one member share holder"
                )
              )
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def open_leadership_election(_organization, _proposer, _candidate, _opts),
    do: {:error, organization_changeset("leadership election is unavailable")}

  @doc "Registers one active member's immutable vote and resolves a decisive majority."
  def cast_leadership_vote(organization, voter, proposal_id, vote, opts \\ [])

  def cast_leadership_vote(
        %Organization{} = organization,
        %Character{} = voter,
        proposal_id,
        vote,
        opts
      )
      when is_binary(proposal_id) and vote in [:approve, :reject] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      memberships = lock_active_memberships!(organization.id)

      proposal =
        organization.metadata
        |> governance_proposals()
        |> Enum.find(fn proposal ->
          Map.get(proposal, "id") == proposal_id and
            Map.get(proposal, "kind") == "leadership_election" and
            Map.get(proposal, "status") == "open"
        end)

      cond do
        is_nil(proposal) ->
          Repo.rollback(organization_changeset("leadership election is not open"))

        is_nil(Enum.find(memberships, &(&1.character_id == voter.id))) ->
          Repo.rollback(organization_changeset("voter is not an active member"))

        voter.id not in proposal_voter_ids(proposal) ->
          Repo.rollback(organization_changeset("voter is not part of this election"))

        Map.has_key?(proposal_votes(proposal), voter.id) ->
          Repo.rollback(organization_changeset("member has already voted in this election"))

        true ->
          proposal = put_leadership_vote(proposal, voter.id, vote, now)

          case leadership_election_resolution(proposal) do
            :pending ->
              updated_organization = replace_governance_proposal!(organization, proposal)
              %{organization: updated_organization, proposal: proposal, resolution: :pending}

            :accepted ->
              candidate_id = Map.get(proposal, "candidate_character_id")
              transfer_leadership!(organization, memberships, candidate_id)
              proposal = resolve_leadership_proposal(proposal, :accepted, now)

              updated_organization =
                organization
                |> Organization.changeset(%{
                  metadata:
                    organization.metadata
                    |> replace_governance_proposal_metadata(proposal)
                    |> Map.put("leader_character_id", candidate_id)
                })
                |> Repo.update!()

              %{organization: updated_organization, proposal: proposal, resolution: :accepted}

            :rejected ->
              proposal = resolve_leadership_proposal(proposal, :rejected, now)
              updated_organization = replace_governance_proposal!(organization, proposal)
              %{organization: updated_organization, proposal: proposal, resolution: :rejected}
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def cast_leadership_vote(_organization, _voter, _proposal_id, _vote, _opts),
    do: {:error, organization_changeset("leadership vote is unavailable")}

  def pending_invitations_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from invitation in Invitation,
        where: invitation.invitee_character_id == ^character_id and invitation.status == :pending,
        order_by: [asc: invitation.inserted_at],
        preload: [:organization, :inviter_character, :role]
    )
  end

  @doc "Returns the configured directional tolls and their realm tax policy."
  def fast_travel_toll_state(%Organization{} = organization) do
    %{
      tax_rate_bps: @fast_travel_toll_tax_rate_bps,
      route_fees: fast_travel_tolls(organization.metadata || %{})
    }
  end

  def fast_travel_toll_state(_organization),
    do: %{tax_rate_bps: @fast_travel_toll_tax_rate_bps, route_fees: %{}}

  @doc "Quotes the gross toll, organization credit, and realm tax for one linked route."
  def fast_travel_toll_quote(
        %Organization{} = organization,
        %Location{} = origin_location,
        %Location{} = destination_location
      ) do
    with {:ok, {origin_location, destination_location}} <-
           linked_fast_travel_route(organization, origin_location.id, destination_location.id) do
      {:ok,
       build_fast_travel_toll_quote(organization, origin_location.id, destination_location.id)}
    end
  end

  def fast_travel_toll_quote(_organization, _origin_location, _destination_location),
    do: {:error, organization_changeset("fast travel toll route is unavailable")}

  @doc "Sets a non-negative, directional fee for one organization-linked fast-travel route."
  def configure_fast_travel_toll(
        %Organization{} = organization,
        %Character{} = actor,
        %Location{} = origin_location,
        %Location{} = destination_location,
        amount
      )
      when is_integer(amount) and amount >= 0 do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)
      membership = active_membership!(organization.id, actor.id)
      validate_permission!(membership, @treasury_permission)

      {origin_location, destination_location} =
        linked_fast_travel_route!(organization, origin_location.id, destination_location.id)

      organization
      |> Organization.changeset(%{
        metadata:
          put_fast_travel_toll(
            organization.metadata || %{},
            origin_location.id,
            destination_location.id,
            amount
          )
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def configure_fast_travel_toll(
        _organization,
        _actor,
        _origin_location,
        _destination_location,
        _amount
      ),
      do:
        {:error, organization_changeset("fast travel toll amount must be a non-negative integer")}

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
      organization = lock_organization!(organization.id)
      character = lock_character!(character.id)
      destination_location = existing_location!(destination_location.id)
      membership = active_membership!(organization.id, character.id)
      validate_permission!(membership, "grant_fast_travel")

      cond do
        not is_nil(Travel.active_journey(character.id)) ->
          Repo.rollback(
            organization_changeset("character cannot use fast travel while travelling")
          )

        organization.status != :active or not organization.fast_travel_enabled ->
          Repo.rollback(organization_changeset("organization fast travel is not active"))

        organization.realm_id != character.realm_id or
            destination_location.realm_id != character.realm_id ->
          Repo.rollback(
            organization_changeset("fast travel must remain inside the organization realm")
          )

        character.current_location_id not in organization.linked_location_ids ->
          Repo.rollback(
            organization_changeset("character is not at an organization-linked location")
          )

        destination_location.id not in organization.linked_location_ids ->
          Repo.rollback(organization_changeset("destination is not linked to this organization"))

        true ->
          settle_fast_travel_toll!(organization, character, destination_location)

          character
          |> Character.travel_changeset(%{current_location_id: destination_location.id})
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  defp settle_fast_travel_toll!(organization, character, destination_location) do
    quote =
      build_fast_travel_toll_quote(
        organization,
        character.current_location_id,
        destination_location.id
      )

    if quote.fee > 0 do
      with {:ok, traveler_account} <- Economy.ensure_character_account(character),
           {:ok, organization_account} <- Economy.ensure_organization_account(organization),
           {:ok, _realm_treasury_account} <-
             ensure_fast_travel_realm_treasury(organization.realm_id),
           {:ok, _transfer} <-
             Economy.taxed_transfer(
               traveler_account,
               organization_account,
               quote.fee,
               quote.tax_rate_bps,
               %{
                 entry_type: "transfer",
                 source: "organization_fast_travel_toll",
                 organization_id: organization.id,
                 traveler_character_id: character.id,
                 origin_location_id: character.current_location_id,
                 destination_location_id: destination_location.id,
                 fast_travel_fee: quote.fee
               }
             ) do
        :ok
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    else
      :ok
    end
  end

  defp ensure_fast_travel_realm_treasury(realm_id) do
    case Repo.get(Realm, realm_id) do
      %Realm{} = realm -> Economy.ensure_treasury_account(realm, 0)
      nil -> {:error, organization_changeset("organization realm could not be found")}
    end
  end

  defp existing_location!(location_id) do
    case safe_get_location(location_id) do
      %Location{} = location -> location
      nil -> Repo.rollback(organization_changeset("fast travel destination could not be found"))
    end
  end

  defp linked_fast_travel_route!(organization, origin_location_id, destination_location_id) do
    case linked_fast_travel_route(organization, origin_location_id, destination_location_id) do
      {:ok, route} -> route
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
    end
  end

  defp linked_fast_travel_route(
         %Organization{} = organization,
         origin_location_id,
         destination_location_id
       )
       when is_binary(origin_location_id) and is_binary(destination_location_id) do
    with %Location{} = origin_location <- safe_get_location(origin_location_id),
         %Location{} = destination_location <- safe_get_location(destination_location_id) do
      linked_location_ids = organization.linked_location_ids || []

      cond do
        origin_location.id == destination_location.id ->
          {:error, organization_changeset("fast travel toll route requires distinct locations")}

        origin_location.realm_id != organization.realm_id or
            destination_location.realm_id != organization.realm_id ->
          {:error,
           organization_changeset(
             "fast travel toll route must remain inside the organization realm"
           )}

        origin_location.id not in linked_location_ids or
            destination_location.id not in linked_location_ids ->
          {:error,
           organization_changeset(
             "fast travel toll locations must be linked to this organization"
           )}

        true ->
          {:ok, {origin_location, destination_location}}
      end
    else
      _other -> {:error, organization_changeset("fast travel toll location could not be found")}
    end
  end

  defp linked_fast_travel_route(_organization, _origin_location_id, _destination_location_id),
    do: {:error, organization_changeset("fast travel toll route is unavailable")}

  defp build_fast_travel_toll_quote(organization, origin_location_id, destination_location_id) do
    fee = fast_travel_toll_fee(organization, origin_location_id, destination_location_id)
    tax_amount = div(fee * @fast_travel_toll_tax_rate_bps, 10_000)

    %{
      origin_location_id: origin_location_id,
      destination_location_id: destination_location_id,
      fee: fee,
      organization_amount: fee - tax_amount,
      tax_amount: tax_amount,
      tax_rate_bps: @fast_travel_toll_tax_rate_bps,
      charged?: fee > 0
    }
  end

  defp fast_travel_toll_fee(
         %Organization{} = organization,
         origin_location_id,
         destination_location_id
       ) do
    organization.metadata
    |> fast_travel_tolls()
    |> Map.get(origin_location_id, %{})
    |> Map.get(destination_location_id, 0)
  end

  defp fast_travel_toll_fee(_organization, _origin_location_id, _destination_location_id), do: 0

  defp fast_travel_tolls(metadata) when is_map(metadata) do
    case Map.get(metadata, @fast_travel_tolls_key, %{}) do
      raw_tolls when is_map(raw_tolls) ->
        Enum.reduce(raw_tolls, %{}, fn
          {origin_location_id, raw_destinations}, tolls
          when is_binary(origin_location_id) and is_map(raw_destinations) ->
            destinations =
              Enum.reduce(raw_destinations, %{}, fn
                {destination_location_id, amount}, routes
                when is_binary(destination_location_id) and is_integer(amount) and amount > 0 ->
                  Map.put(routes, destination_location_id, amount)

                _route, routes ->
                  routes
              end)

            if map_size(destinations) > 0 do
              Map.put(tolls, origin_location_id, destinations)
            else
              tolls
            end

          _route, tolls ->
            tolls
        end)

      _other ->
        %{}
    end
  end

  defp fast_travel_tolls(_metadata), do: %{}

  defp put_fast_travel_toll(metadata, origin_location_id, destination_location_id, amount) do
    tolls = fast_travel_tolls(metadata)
    destination_tolls = Map.get(tolls, origin_location_id, %{})

    destination_tolls =
      if amount == 0 do
        Map.delete(destination_tolls, destination_location_id)
      else
        Map.put(destination_tolls, destination_location_id, amount)
      end

    tolls =
      if map_size(destination_tolls) == 0 do
        Map.delete(tolls, origin_location_id)
      else
        Map.put(tolls, origin_location_id, destination_tolls)
      end

    if map_size(tolls) == 0 do
      Map.delete(metadata, @fast_travel_tolls_key)
    else
      Map.put(metadata, @fast_travel_tolls_key, tolls)
    end
  end

  defp safe_get_location(location_id) when is_binary(location_id) do
    Repo.get(Location, location_id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp safe_get_location(_location_id), do: nil

  defp fast_travel_memberships(location_id, character_id) do
    Membership
    |> join(:inner, [membership], organization in assoc(membership, :organization))
    |> join(:inner, [membership, organization], role in assoc(membership, :role))
    |> where(
      [membership, organization, role],
      membership.character_id == ^character_id and membership.status == :active and
        role.organization_id == organization.id and organization.status == :active and
        organization.fast_travel_enabled == true and
        ^location_id in organization.linked_location_ids and
        ^"grant_fast_travel" in role.permissions
    )
    |> preload([membership, organization, role], organization: organization, role: role)
    |> Repo.all()
  end

  defp active_membership_query do
    from membership in Membership,
      join: role in assoc(membership, :role),
      where: membership.status == :active and role.organization_id == membership.organization_id,
      order_by: [asc: membership.joined_at],
      preload: [:character, role: role]
  end

  defp active_membership!(organization_id, character_id) do
    Membership
    |> join(:inner, [membership], role in assoc(membership, :role))
    |> where(
      [membership, role],
      membership.organization_id == ^organization_id and membership.character_id == ^character_id and
        membership.status == :active and role.organization_id == membership.organization_id
    )
    |> lock("FOR UPDATE")
    |> preload([_membership, role], role: role)
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(organization_changeset("character is not an active organization member"))

      membership ->
        membership
    end
  end

  defp lock_active_memberships!(organization_id) do
    Membership
    |> join(:inner, [membership], role in assoc(membership, :role))
    |> where(
      [membership, role],
      membership.organization_id == ^organization_id and membership.status == :active and
        role.organization_id == membership.organization_id
    )
    |> order_by([membership], asc: membership.id)
    |> lock("FOR UPDATE")
    |> preload([_membership, role], role: role)
    |> Repo.all()
  end

  defp lock_organization_role!(organization_id, role_id) do
    Role
    |> where([role], role.organization_id == ^organization_id and role.id == ^role_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> Repo.rollback(organization_changeset("organization role was not found"))
      role -> role
    end
  end

  defp validate_permission!(membership, permission) do
    if permission in membership.role.permissions do
      :ok
    else
      Repo.rollback(organization_changeset("role lacks required permission #{permission}"))
    end
  end

  defp custom_roles_allowed?(%Organization{hierarchy_rules: rules}) when is_map(rules) do
    Map.get(rules, "custom_roles_allowed", true) in [true, "true"]
  end

  defp custom_roles_allowed?(_organization), do: true

  defp valid_custom_role_rank?(rank) when is_integer(rank), do: rank in 0..99
  defp valid_custom_role_rank?(_rank), do: false

  defp valid_role_permissions?(permissions) when is_list(permissions),
    do: Enum.all?(permissions, &(&1 in @role_permissions))

  defp valid_role_permissions?(_permissions), do: false

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

  defp hierarchy_rules_for(attrs) when is_map(attrs) do
    rules = Map.get(attrs, "hierarchy_rules", %{})
    rules = if(is_map(rules), do: rules, else: %{})

    %{
      "custom_roles_allowed" => Map.get(rules, "custom_roles_allowed", true),
      "leadership" => %{
        "selection" =>
          rules
          |> Map.get("leadership", %{})
          |> leadership_selection_from_block()
      },
      "membership" => %{
        "admission" =>
          rules
          |> Map.get("membership", %{})
          |> membership_admission_from_block()
      },
      "succession" => %{"on_leader_exit" => "highest_rank_member"},
      "treasury" => %{"decision" => "role_permission", "permission" => @treasury_permission}
    }
    |> Map.merge(rules)
  end

  defp hierarchy_rules_for(_attrs), do: hierarchy_rules_for(%{})

  defp organization_metadata_for(attrs, %Character{} = founder) when is_map(attrs) do
    metadata = Map.get(attrs, "metadata", %{})
    metadata = if(is_map(metadata), do: metadata, else: %{})

    metadata
    |> Map.put("leader_character_id", founder.id)
    |> put_treasury_shares(treasury_shares(metadata))
  end

  defp organization_metadata_for(_attrs, %Character{} = founder),
    do:
      %{"leader_character_id" => founder.id}
      |> put_treasury_shares(%{@organization_share_key => @share_basis_points})

  defp leadership_selection(%Organization{hierarchy_rules: rules}) when is_map(rules) do
    rules
    |> Map.get("leadership", %{})
    |> leadership_selection_from_block()
  end

  defp leadership_selection(_organization), do: "founder_appointment"

  defp leadership_selection_from_block(block) when is_map(block) do
    case Map.get(block, "selection") do
      selection when selection in @leadership_selection_modes -> selection
      _other -> "founder_appointment"
    end
  end

  defp leadership_selection_from_block(_block), do: "founder_appointment"

  defp membership_admission(%Organization{hierarchy_rules: rules}) when is_map(rules) do
    rules
    |> Map.get("membership", %{})
    |> membership_admission_from_block()
  end

  defp membership_admission(_organization), do: "invitation_only"

  defp membership_admission_from_block(block) when is_map(block) do
    case Map.get(block, "admission") do
      admission when admission in @membership_admission_modes -> admission
      _other -> "invitation_only"
    end
  end

  defp membership_admission_from_block(_block), do: "invitation_only"

  defp treasury_decision(%Organization{hierarchy_rules: rules}) when is_map(rules) do
    rules
    |> Map.get("treasury", %{})
    |> treasury_decision_from_block()
  end

  defp treasury_decision(_organization), do: "role_permission"

  defp treasury_decision_from_block(block) when is_map(block) do
    case Map.get(block, "decision") do
      decision when decision in @treasury_decision_modes -> decision
      _other -> "role_permission"
    end
  end

  defp treasury_decision_from_block(_block), do: "role_permission"

  defp treasury_referendum_required?(organization, role, amount)
       when is_integer(amount) and amount > 0 do
    treasury_decision(organization) == "member_referendum" or
      case treasury_role_payout_limit(role) do
        limit when is_integer(limit) -> amount > limit
        _other -> false
      end
  end

  defp treasury_referendum_required?(_organization, _role, _amount), do: false

  defp open_membership_role!(%Organization{} = organization) do
    case Enum.find(organization.roles, &(&1.code == "open-member")) do
      %Role{permissions: []} = role ->
        role

      %Role{} ->
        Repo.rollback(
          organization_changeset("organization open-member role must not grant permissions")
        )

      nil ->
        Repo.rollback(organization_changeset("organization has no safe open-member role"))
    end
  end

  defp treasury_shares(metadata) when is_map(metadata) do
    raw_shares =
      case Map.get(metadata, @ownership_key, %{}) do
        ownership when is_map(ownership) -> Map.get(ownership, @treasury_shares_key, %{})
        _other -> %{}
      end

    normalized_character_shares =
      if is_map(raw_shares) do
        raw_shares
        |> Enum.reduce(%{}, fn
          {participant, share_bps}, shares
          when is_binary(participant) and is_integer(share_bps) and
                 share_bps in 1..@share_basis_points ->
            if is_character_share_key(participant) do
              Map.put(shares, participant, share_bps)
            else
              shares
            end

          _entry, shares ->
            shares
        end)
      else
        %{}
      end

    character_share_total = normalized_character_shares |> Map.values() |> Enum.sum()

    if character_share_total <= @share_basis_points do
      Map.put(
        normalized_character_shares,
        @organization_share_key,
        @share_basis_points - character_share_total
      )
    else
      %{@organization_share_key => @share_basis_points}
    end
  end

  defp treasury_shares(_metadata), do: %{@organization_share_key => @share_basis_points}

  defp put_treasury_shares(metadata, shares) do
    ownership =
      case Map.get(metadata, @ownership_key, %{}) do
        existing when is_map(existing) -> existing
        _other -> %{}
      end

    Map.put(metadata, @ownership_key, Map.put(ownership, @treasury_shares_key, shares))
  end

  defp put_or_delete_share(shares, participant, 0), do: Map.delete(shares, participant)

  defp put_or_delete_share(shares, participant, share_bps),
    do: Map.put(shares, participant, share_bps)

  defp character_share_key(character_id), do: "character:" <> character_id

  defp is_character_share_key("character:" <> character_id), do: byte_size(character_id) > 0
  defp is_character_share_key(_participant), do: false

  defp share_character_id("character:" <> character_id), do: character_id

  defp treasury_dividend_allocations(%Organization{} = organization, gross_amount) do
    organization.metadata
    |> treasury_shares()
    |> Enum.flat_map(fn
      {"character:" <> character_id, share_bps} ->
        amount = div(gross_amount * share_bps, @share_basis_points)

        if amount > 0 do
          [%{character_id: character_id, share_bps: share_bps, amount: amount}]
        else
          []
        end

      _share ->
        []
    end)
    |> Enum.sort_by(& &1.character_id)
  end

  defp leader_character_id(%Organization{} = organization) do
    case Map.fetch(organization.metadata || %{}, "leader_character_id") do
      {:ok, character_id} when is_binary(character_id) -> character_id
      {:ok, _other} -> nil
      :error -> organization.founder_character_id
    end
  end

  defp governance_proposals(metadata) when is_map(metadata) do
    case Map.get(metadata, @governance_proposals_key, []) do
      proposals when is_list(proposals) -> Enum.filter(proposals, &is_map/1)
      _other -> []
    end
  end

  defp governance_proposals(_metadata), do: []

  defp append_governance_proposal(metadata, proposal) do
    proposals =
      [proposal | governance_proposals(metadata)]
      |> Enum.take(@governance_proposal_history_limit)

    Map.put(metadata, @governance_proposals_key, proposals)
  end

  defp replace_governance_proposal!(%Organization{} = organization, proposal) do
    organization
    |> Organization.changeset(%{
      metadata: replace_governance_proposal_metadata(organization.metadata || %{}, proposal)
    })
    |> Repo.update!()
  end

  defp replace_governance_proposal_metadata(metadata, proposal) do
    proposal_id = Map.get(proposal, "id")

    metadata
    |> governance_proposals()
    |> Enum.map(fn existing ->
      if Map.get(existing, "id") == proposal_id, do: proposal, else: existing
    end)
    |> then(&Map.put(metadata, @governance_proposals_key, &1))
  end

  defp diplomacy_relationships(metadata) when is_map(metadata) do
    case Map.get(metadata, @diplomacy_relationships_key, []) do
      relationships when is_list(relationships) ->
        Enum.filter(relationships, fn relationship ->
          is_map(relationship) and is_binary(Map.get(relationship, "organization_id")) and
            Map.get(relationship, "kind") in @diplomacy_relationship_kinds
        end)

      _other ->
        []
    end
  end

  defp diplomacy_relationships(_metadata), do: []

  defp relationship_exists?(%Organization{} = organization, other_organization_id) do
    Enum.any?(diplomacy_relationships(organization.metadata || %{}), fn relationship ->
      Map.get(relationship, "organization_id") == other_organization_id
    end)
  end

  defp treasury_open_referendum(%Organization{} = organization) do
    organization.metadata
    |> governance_proposals()
    |> Enum.find(fn proposal ->
      Map.get(proposal, "kind") == "treasury_withdrawal" and
        Map.get(proposal, "status") == "open"
    end)
  end

  defp new_treasury_referendum(
         proposer_character_id,
         recipient_character_id,
         amount,
         memberships,
         %DateTime{} = now
       ) do
    %{
      "id" => Ecto.UUID.generate(),
      "kind" => "treasury_withdrawal",
      "status" => "open",
      "proposer_character_id" => proposer_character_id,
      "recipient_character_id" => recipient_character_id,
      "amount" => amount,
      "voter_character_ids" => Enum.map(memberships, & &1.character_id),
      "votes" => %{},
      "opened_at" => DateTime.to_iso8601(now)
    }
  end

  defp diplomacy_request_open?(%Organization{} = organization, source_organization_id) do
    organization.metadata
    |> governance_proposals()
    |> Enum.any?(fn proposal ->
      Map.get(proposal, "kind") == "diplomacy_request" and
        Map.get(proposal, "status") == "open" and
        Map.get(proposal, "source_organization_id") == source_organization_id
    end)
  end

  defp new_diplomacy_request(
         source,
         target,
         requester_character_id,
         relationship_kind,
         %DateTime{} = now
       ) do
    %{
      "id" => Ecto.UUID.generate(),
      "kind" => "diplomacy_request",
      "status" => "open",
      "relationship_kind" => relationship_kind,
      "source_organization_id" => source.id,
      "target_organization_id" => target.id,
      "requester_character_id" => requester_character_id,
      "opened_at" => DateTime.to_iso8601(now)
    }
  end

  defp resolve_diplomacy_request(proposal, outcome, %DateTime{} = now) do
    proposal
    |> Map.put("status", Atom.to_string(outcome))
    |> Map.put("resolved_at", DateTime.to_iso8601(now))
  end

  defp new_diplomacy_relationship(other_organization_id, relationship_kind, %DateTime{} = now) do
    %{
      "organization_id" => other_organization_id,
      "kind" => relationship_kind,
      "established_at" => DateTime.to_iso8601(now)
    }
  end

  defp append_diplomacy_relationship(metadata, relationship) do
    relationships =
      metadata
      |> diplomacy_relationships()
      |> Enum.reject(&(&1["organization_id"] == relationship["organization_id"]))
      |> then(&[relationship | &1])
      |> Enum.take(@diplomacy_relationship_history_limit)

    Map.put(metadata, @diplomacy_relationships_key, relationships)
  end

  defp pending_diplomacy_source_id(target_organization_id, proposal_id) do
    case Repo.get(Organization, target_organization_id) do
      %Organization{} = target_organization ->
        target_organization.metadata
        |> governance_proposals()
        |> Enum.find_value(fn proposal ->
          if Map.get(proposal, "id") == proposal_id and
               Map.get(proposal, "kind") == "diplomacy_request" and
               Map.get(proposal, "status") == "open" do
            Map.get(proposal, "source_organization_id")
          end
        end)

      nil ->
        nil
    end
  end

  defp new_leadership_election(
         candidate_character_id,
         memberships,
         "member_election",
         _shares,
         %DateTime{} = now
       ) do
    {:ok,
     %{
       "id" => Ecto.UUID.generate(),
       "kind" => "leadership_election",
       "status" => "open",
       "voting_method" => "member_majority",
       "candidate_character_id" => candidate_character_id,
       "voter_character_ids" => Enum.map(memberships, & &1.character_id),
       "votes" => %{},
       "opened_at" => DateTime.to_iso8601(now)
     }}
  end

  defp new_leadership_election(
         candidate_character_id,
         memberships,
         "share_weighted_election",
         shares,
         %DateTime{} = now
       ) do
    voter_weights =
      memberships
      |> Enum.reduce(%{}, fn membership, weights ->
        share_bps = Map.get(shares, character_share_key(membership.character_id), 0)

        if is_integer(share_bps) and share_bps > 0 do
          Map.put(weights, membership.character_id, share_bps)
        else
          weights
        end
      end)

    if map_size(voter_weights) == 0 do
      {:error, :no_share_voters}
    else
      {:ok,
       %{
         "id" => Ecto.UUID.generate(),
         "kind" => "leadership_election",
         "status" => "open",
         "voting_method" => "share_weighted",
         "candidate_character_id" => candidate_character_id,
         "voter_character_ids" => voter_weights |> Map.keys() |> Enum.sort(),
         "voter_weights_bps" => voter_weights,
         "votes" => %{},
         "opened_at" => DateTime.to_iso8601(now)
       }}
    end
  end

  defp proposal_voter_ids(%{"voter_character_ids" => voter_ids}) when is_list(voter_ids),
    do: Enum.filter(voter_ids, &is_binary/1)

  defp proposal_voter_ids(_proposal), do: []

  defp proposal_votes(%{"votes" => votes}) when is_map(votes), do: votes
  defp proposal_votes(_proposal), do: %{}

  defp proposal_voter_weights(%{"voter_weights_bps" => weights}) when is_map(weights) do
    weights
    |> Enum.reduce(%{}, fn
      {character_id, weight}, normalized
      when is_binary(character_id) and is_integer(weight) and weight > 0 ->
        Map.put(normalized, character_id, weight)

      _entry, normalized ->
        normalized
    end)
  end

  defp proposal_voter_weights(_proposal), do: %{}

  defp put_leadership_vote(proposal, voter_character_id, vote, %DateTime{} = now) do
    Map.put(
      proposal,
      "votes",
      Map.put(proposal_votes(proposal), voter_character_id, %{
        "choice" => to_string(vote),
        "voted_at" => DateTime.to_iso8601(now)
      })
    )
  end

  defp leadership_election_resolution(proposal) do
    case proposal_voter_weights(proposal) do
      weights when map_size(weights) > 0 -> weighted_election_resolution(proposal, weights)
      _weights -> member_election_resolution(proposal)
    end
  end

  defp member_election_resolution(proposal) do
    voter_count = length(proposal_voter_ids(proposal))
    required_votes = div(voter_count, 2) + 1

    vote_counts =
      proposal
      |> proposal_votes()
      |> Map.values()
      |> Enum.frequencies_by(&Map.get(&1, "choice"))

    cond do
      voter_count == 0 -> :rejected
      Map.get(vote_counts, "approve", 0) >= required_votes -> :accepted
      Map.get(vote_counts, "reject", 0) >= required_votes -> :rejected
      true -> :pending
    end
  end

  defp weighted_election_resolution(proposal, weights) do
    total_weight = weights |> Map.values() |> Enum.sum()
    required_weight = div(total_weight, 2) + 1

    vote_weights =
      proposal
      |> proposal_votes()
      |> Enum.reduce(%{"approve" => 0, "reject" => 0}, fn {character_id, vote}, totals ->
        choice = Map.get(vote, "choice")
        weight = Map.get(weights, character_id, 0)

        if choice in ["approve", "reject"] do
          Map.update!(totals, choice, &(&1 + weight))
        else
          totals
        end
      end)

    cond do
      total_weight == 0 -> :rejected
      vote_weights["approve"] >= required_weight -> :accepted
      vote_weights["reject"] >= required_weight -> :rejected
      true -> :pending
    end
  end

  defp resolve_leadership_proposal(proposal, outcome, %DateTime{} = now) do
    proposal
    |> Map.put("status", Atom.to_string(outcome))
    |> Map.put("resolved_at", DateTime.to_iso8601(now))
  end

  defp cancel_governance_votes_for_departure!(
         %Organization{} = organization,
         character_id,
         %DateTime{} = now
       ) do
    {proposals, changed?} =
      organization.metadata
      |> governance_proposals()
      |> Enum.map_reduce(false, fn proposal, changed? ->
        if Map.get(proposal, "status") == "open" and character_id in proposal_voter_ids(proposal) do
          cancelled_proposal =
            proposal
            |> resolve_leadership_proposal(:cancelled, now)
            |> Map.put("cancellation_reason", "member_departed")

          {cancelled_proposal, true}
        else
          {proposal, changed?}
        end
      end)

    if changed? do
      organization
      |> Organization.changeset(%{
        metadata: Map.put(organization.metadata || %{}, @governance_proposals_key, proposals)
      })
      |> Repo.update!()
    else
      organization
    end
  end

  defp leader_exit_successor(%Organization{} = organization, memberships, departing_character_id) do
    remaining_memberships =
      Enum.reject(memberships, &(&1.character_id == departing_character_id))

    case leader_exit_mode(organization) do
      "highest_rank_member" ->
        Enum.max_by(remaining_memberships, & &1.role.rank, fn -> nil end)

      _other ->
        nil
    end
  end

  defp leader_exit_mode(%Organization{hierarchy_rules: rules}) when is_map(rules) do
    case Map.get(rules, "succession") do
      %{"on_leader_exit" => "highest_rank_member"} -> "highest_rank_member"
      %{"on_leader_exit" => "vacant"} -> "vacant"
      _other -> "highest_rank_member"
    end
  end

  defp leader_exit_mode(_organization), do: "highest_rank_member"

  defp transfer_leadership!(%Organization{} = organization, memberships, candidate_character_id) do
    candidate_membership = Enum.find(memberships, &(&1.character_id == candidate_character_id))

    current_leader_membership =
      Enum.find(memberships, &(&1.character_id == leader_character_id(organization)))

    leader_role =
      case current_leader_membership do
        %{role: %Role{} = role} -> role
        _other -> Enum.max_by(organization.roles, & &1.rank, fn -> nil end)
      end

    cond do
      is_nil(candidate_membership) ->
        Repo.rollback(
          organization_changeset("leadership candidate is no longer an active member")
        )

      is_nil(leader_role) ->
        Repo.rollback(organization_changeset("organization has no leadership role to transfer"))

      candidate_membership.role_id == leader_role.id ->
        :ok

      true ->
        candidate_role_id = candidate_membership.role_id

        candidate_membership
        |> Membership.changeset(%{role_id: leader_role.id})
        |> Repo.update!()

        if current_leader_membership do
          current_leader_membership
          |> Membership.changeset(%{role_id: candidate_role_id})
          |> Repo.update!()
        end
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

  defp lock_characters!(character_ids) do
    character_ids = Enum.uniq(character_ids)

    characters =
      Character
      |> where([character], character.id in ^character_ids)
      |> order_by([character], asc: character.id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    if length(characters) != length(character_ids) do
      Repo.rollback(organization_changeset("treasury share holder could not be found"))
    end

    Map.new(characters, &{&1.id, &1})
  end

  defp lock_organization!(organization_id) do
    Organization
    |> where([organization], organization.id == ^organization_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(memberships: active_membership_query(), roles: [])
  end

  defp lock_organization_pair!(first_organization_id, second_organization_id) do
    organization_ids = Enum.uniq([first_organization_id, second_organization_id])

    organizations =
      Organization
      |> where([organization], organization.id in ^organization_ids)
      |> order_by([organization], asc: organization.id)
      |> lock("FOR UPDATE")
      |> Repo.all()
      |> Repo.preload(memberships: active_membership_query(), roles: [])

    if length(organizations) != length(organization_ids) do
      Repo.rollback(organization_changeset("diplomacy organization could not be found"))
    end

    Map.new(organizations, &{&1.id, &1})
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
