defmodule MMGO.Bases.Ownership do
  @moduledoc """
  Durable ownership-share data and custody checks for bases.

  A base retains its founding character as the legal owner, while its metadata
  can grant a closed share of the base to one or more organizations. An
  organization share is intentionally not a decorative map label: an active
  member with treasury authority receives custody access to that base's real
  storage and base-gated work surfaces. Removing the share or the authority
  immediately removes that access.

  This is kept here rather than in `MMGO.Organizations` because a base is the
  asset that owns the durable record. The organization tables are queried only
  to validate live custodianship.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Bases.Base
  alias MMGO.Organizations.{Membership, Organization, Role}
  alias MMGO.Repo

  @basis_points 10_000
  @ownership_key "ownership"
  @shares_key "shares_bps"
  @organization_prefix "organization:"
  @custody_permission "manage_treasury"

  @doc "Returns the closed ownership-share state for a base."
  def ownership_state(%Base{} = base) do
    organization_shares = organization_shares(base)

    %{
      owner_character_id: base.owner_character_id,
      owner_share_bps: @basis_points - Enum.sum(Map.values(organization_shares)),
      organization_share_bps: organization_shares
    }
  end

  def ownership_state(_base),
    do: %{owner_character_id: nil, owner_share_bps: @basis_points, organization_share_bps: %{}}

  @doc "Returns only valid, closed organization ownership shares for a base."
  def organization_shares(%Base{metadata: metadata}) when is_map(metadata) do
    raw_shares =
      case Map.get(metadata, @ownership_key, %{}) do
        ownership when is_map(ownership) -> Map.get(ownership, @shares_key, %{})
        _other -> %{}
      end

    shares =
      if is_map(raw_shares) do
        Enum.reduce(raw_shares, %{}, fn
          {<<@organization_prefix, organization_id::binary>>, share_bps}, acc
          when byte_size(organization_id) > 0 and is_integer(share_bps) and
                 share_bps in 1..@basis_points ->
            Map.put(acc, organization_id, share_bps)

          _entry, acc ->
            acc
        end)
      else
        %{}
      end

    if Enum.sum(Map.values(shares)) < @basis_points, do: shares, else: %{}
  end

  def organization_shares(_base), do: %{}

  @doc "Writes one organization share into base metadata while preserving the 10,000 bps cap."
  def put_organization_share(%Base{} = base, organization_id, share_bps)
      when is_binary(organization_id) and byte_size(organization_id) > 0 and
             is_integer(share_bps) and share_bps >= 0 and share_bps < @basis_points do
    organization_shares = organization_shares(base)

    updated_shares =
      case share_bps do
        0 -> Map.delete(organization_shares, organization_id)
        _positive_share -> Map.put(organization_shares, organization_id, share_bps)
      end

    if Enum.sum(Map.values(updated_shares)) < @basis_points do
      ownership =
        case Map.get(base.metadata || %{}, @ownership_key, %{}) do
          existing when is_map(existing) -> existing
          _other -> %{}
        end

      {:ok,
       Map.put(
         base.metadata || %{},
         @ownership_key,
         Map.put(
           ownership,
           @shares_key,
           Map.new(updated_shares, fn {id, bps} -> {@organization_prefix <> id, bps} end)
         )
       )}
    else
      {:error, :ownership_shares_exceed_cap}
    end
  end

  def put_organization_share(_base, _organization_id, _share_bps),
    do: {:error, :invalid_ownership_share}

  @doc "True when the character is the base owner or a live organization custodian."
  def accessible?(%Base{} = base, %Character{} = character) do
    base.owner_character_id == character.id or organization_custodian?(base, character, false)
  end

  def accessible?(_base, _character), do: false

  @doc false
  def accessible_for_update?(%Base{} = base, %Character{} = character) do
    base.owner_character_id == character.id or organization_custodian?(base, character, true)
  end

  def accessible_for_update?(_base, _character), do: false

  defp organization_custodian?(%Base{} = base, %Character{} = character, lock?) do
    organization_ids = Map.keys(organization_shares(base))

    if base.realm_id == character.realm_id and organization_ids != [] do
      query =
        from membership in Membership,
          join: role in Role,
          on: role.id == membership.role_id,
          join: organization in Organization,
          on: organization.id == membership.organization_id,
          where:
            membership.character_id == ^character.id and membership.status == :active and
              membership.organization_id in ^organization_ids and
              role.organization_id == membership.organization_id and
              organization.status == :active and
              ^@custody_permission in role.permissions,
          select: membership.id,
          limit: 1

      query = if lock?, do: lock(query, "FOR UPDATE"), else: query
      not is_nil(Repo.one(query))
    else
      false
    end
  end
end
