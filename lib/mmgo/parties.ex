defmodule MMGO.Parties do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Parties.{Expedition, ExpeditionMember, Membership, Party, Reward}
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel.Journey

  def list_parties_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from party in Party,
        where: party.realm_id == ^realm_id,
        order_by: [asc: party.inserted_at]
    )
  end

  def get_party!(id) do
    Party
    |> Repo.get!(id)
    |> preload_party()
  end

  def active_party_for_character(character_id) when is_binary(character_id) do
    Party
    |> join(:inner, [party], membership in assoc(party, :memberships))
    |> where(
      [_party, membership],
      membership.character_id == ^character_id and membership.status == :active
    )
    |> where([party, _membership], party.status == :active)
    |> Repo.one()
    |> case do
      nil -> nil
      party -> preload_party(party)
    end
  end

  def list_active_members(%Party{} = party) do
    active_members_query()
    |> where([membership], membership.party_id == ^party.id)
    |> Repo.all()
  end

  def create_party(%Character{} = leader, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    name = attrs["name"] || "#{leader.name}'s Party"
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      leader = lock_character!(leader.id)

      if active_membership?(leader.id) do
        Repo.rollback(active_party_changeset())
      end

      party =
        %Party{}
        |> Party.changeset(%{
          realm_id: leader.realm_id,
          leader_character_id: leader.id,
          name: name,
          status: :active
        })
        |> Repo.insert!()

      membership =
        %Membership{}
        |> Membership.changeset(%{
          party_id: party.id,
          character_id: leader.id,
          role: :leader,
          status: :active,
          joined_at: now
        })
        |> Repo.insert!()

      %{party: preload_party(party), membership: membership}
    end)
    |> normalize_transaction_result()
  end

  def add_member(%Party{} = party, %Character{} = character) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      party = lock_party!(party.id)
      character = lock_character!(character.id)

      validate_joinable!(party, character)

      membership =
        %Membership{}
        |> Membership.changeset(%{
          party_id: party.id,
          character_id: character.id,
          role: :member,
          status: :active,
          joined_at: now
        })
        |> Repo.insert!()

      %{party: preload_party(party), membership: membership}
    end)
    |> normalize_transaction_result()
  end

  def remove_member(%Party{} = party, %Character{} = character) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      party = lock_party!(party.id)

      membership =
        Membership
        |> where(
          [membership],
          membership.party_id == ^party.id and membership.character_id == ^character.id
        )
        |> where([membership], membership.status == :active)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(membership) do
        Repo.rollback(membership_changeset("character is not an active party member"))
      end

      membership
      |> Membership.changeset(%{status: :left, left_at: now})
      |> Repo.update!()

      remaining_members =
        active_members_query()
        |> where([membership], membership.party_id == ^party.id)
        |> Repo.all()

      party =
        cond do
          remaining_members == [] ->
            party
            |> Party.changeset(%{status: :disbanded})
            |> Repo.update!()

          membership.role == :leader ->
            new_leader =
              Enum.min_by(remaining_members, &DateTime.to_unix(&1.joined_at, :microsecond))

            new_leader
            |> Membership.changeset(%{role: :leader})
            |> Repo.update!()

            party
            |> Party.changeset(%{leader_character_id: new_leader.character_id})
            |> Repo.update!()

          true ->
            party
        end

      %{party: preload_party(party)}
    end)
    |> normalize_transaction_result()
  end

  def active_expedition_for_party(party_id) when is_binary(party_id) do
    Repo.get_by(Expedition, party_id: party_id, status: :active)
  end

  def active_expedition_for_character(character_id) when is_binary(character_id) do
    Expedition
    |> join(:inner, [expedition], member in assoc(expedition, :members))
    |> where(
      [expedition, member],
      expedition.status == :active and member.character_id == ^character_id and
        member.status == :active
    )
    |> Repo.one()
  end

  def active_members_for_expedition(expedition_id) when is_binary(expedition_id) do
    ExpeditionMember
    |> where([member], member.expedition_id == ^expedition_id and member.status == :active)
    |> order_by([member], asc: member.joined_at)
    |> preload(:character)
    |> Repo.all()
  end

  def eligible_member_for_expedition?(expedition_id, character_id)
      when is_binary(expedition_id) and is_binary(character_id) do
    Repo.exists?(
      from member in ExpeditionMember,
        where:
          member.expedition_id == ^expedition_id and member.character_id == ^character_id and
            member.status in [:active, :completed]
    )
  end

  def list_rewards_for_expedition(expedition_id) when is_binary(expedition_id) do
    Reward
    |> where([reward], reward.expedition_id == ^expedition_id)
    |> order_by([reward], asc: reward.inserted_at)
    |> Repo.all()
  end

  def distribute_xp_shares(repo \\ Repo, %Expedition{} = expedition, total_xp, attrs \\ %{})
      when is_integer(total_xp) do
    attrs = stringify_keys(attrs)

    if total_xp <= 0 do
      []
    else
      members =
        ExpeditionMember
        |> where([member], member.expedition_id == ^expedition.id and member.status == :active)
        |> order_by([member], asc: member.joined_at)
        |> preload(:character)
        |> repo.all()

      if members == [] do
        []
      else
        characters = lock_characters(repo, Enum.map(members, & &1.character_id))
        count = length(members)
        base_share = div(total_xp, count)
        remainder = rem(total_xp, count)
        now = attrs["granted_at"] || DateTime.utc_now()
        source_type = normalize_source_type(attrs["source_type"])
        reward_kind = normalize_reward_kind(attrs["reward_kind"])

        Enum.with_index(members)
        |> Enum.reduce([], fn {member, index}, rewards ->
          share = base_share + if(index < remainder, do: 1, else: 0)

          if share <= 0 do
            rewards
          else
            character = Map.fetch!(characters, member.character_id)

            {:ok, %{character: updated_character}} =
              Progression.grant_xp(repo, character, share, %{
                "source" => attrs["source"] || "party_reward",
                "granted_at" => now,
                "run_id" => attrs["run_id"],
                "encounter_id" => attrs["encounter_id"]
              })

            reward =
              %Reward{}
              |> Reward.changeset(%{
                reward_kind: reward_kind,
                source_type: source_type,
                reward_code: reward_code(attrs, member.character_id, reward_kind),
                amount: share,
                granted_at: now,
                metadata: Map.put(attrs, "character_name", updated_character.name),
                expedition_id: expedition.id,
                run_id: attrs["run_id"],
                encounter_id: attrs["encounter_id"],
                character_id: member.character_id
              })
              |> repo.insert!()

            [reward | rewards]
          end
        end)
        |> Enum.reverse()
      end
    end
  end

  def start_expedition(%Party{} = party, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    started_at = attrs["started_at"] || DateTime.utc_now()
    expedition_type = attrs["expedition_type"] || "dungeon"

    Repo.transaction(fn ->
      party = lock_party!(party.id)

      members =
        active_members_query()
        |> where([membership], membership.party_id == ^party.id)
        |> Repo.all()

      validate_expedition_ready!(party, members)

      location_id =
        members
        |> Enum.map(& &1.character.current_location_id)
        |> Enum.uniq()
        |> List.first()

      supply_summary = %{
        total_food_units: 0,
        daily_food_demand: 0,
        total_carried_weight: 0,
        total_carry_capacity: 100
      }

      expedition =
        %Expedition{}
        |> Expedition.changeset(%{
          party_id: party.id,
          realm_id: party.realm_id,
          location_id: location_id,
          expedition_type: expedition_type,
          status: :active,
          food_units_snapshot: supply_summary.total_food_units,
          daily_food_demand: supply_summary.daily_food_demand,
          carried_weight: supply_summary.total_carried_weight,
          carry_capacity: supply_summary.total_carry_capacity,
          started_at: started_at
        })
        |> Repo.insert!()

      expedition_members =
        Enum.map(members, fn membership ->
          %ExpeditionMember{}
          |> ExpeditionMember.changeset(%{
            expedition_id: expedition.id,
            party_membership_id: membership.id,
            character_id: membership.character_id,
            status: :active,
            joined_at: started_at,
            metadata: %{"role" => Atom.to_string(membership.role)}
          })
          |> Repo.insert!()
        end)

      %{expedition: preload_expedition(expedition), members: expedition_members}
    end)
    |> normalize_transaction_result()
  end

  def end_expedition(%Expedition{} = expedition, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    status = normalize_expedition_status(attrs["status"] || :completed)
    ended_at = attrs["ended_at"] || DateTime.utc_now()

    Repo.transaction(fn ->
      expedition = lock_expedition!(expedition.id)

      if expedition.status != :active do
        Repo.rollback(expedition_changeset("expedition is not active"))
      end

      expedition_members =
        ExpeditionMember
        |> where([member], member.expedition_id == ^expedition.id and member.status == :active)
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.each(expedition_members, fn member ->
        member
        |> ExpeditionMember.changeset(%{status: :completed, left_at: ended_at})
        |> Repo.update!()
      end)

      updated_expedition =
        expedition
        |> Expedition.changeset(%{status: status, ended_at: ended_at})
        |> Repo.update!()

      %{expedition: preload_expedition(updated_expedition)}
    end)
    |> normalize_transaction_result()
  end

  defp validate_joinable!(%Party{} = party, %Character{} = character) do
    cond do
      party.status != :active ->
        Repo.rollback(party_changeset("party is not active"))

      party.realm_id != character.realm_id ->
        Repo.rollback(party_changeset("character must belong to the same realm"))

      active_membership?(character.id) ->
        Repo.rollback(active_party_changeset())

      true ->
        :ok
    end
  end

  defp validate_expedition_ready!(%Party{} = party, members) do
    cond do
      party.status != :active ->
        Repo.rollback(expedition_changeset("party is not active"))

      members == [] ->
        Repo.rollback(expedition_changeset("party must have active members"))

      active_expedition_for_party(party.id) ->
        Repo.rollback(expedition_changeset("party already has an active expedition"))

      Enum.any?(members, &is_nil(&1.character.current_location_id)) ->
        Repo.rollback(expedition_changeset("all members must have a current location"))

      members_same_location?(members) == false ->
        Repo.rollback(expedition_changeset("all members must be in the same location"))

      Enum.any?(members, &active_expedition_for_character(&1.character_id)) ->
        Repo.rollback(expedition_changeset("a member already has an active expedition"))

      Enum.any?(members, &active_journey?(&1.character_id)) ->
        Repo.rollback(expedition_changeset("a member is currently travelling"))

      true ->
        :ok
    end
  end

  defp active_membership?(character_id) do
    Repo.exists?(
      from membership in Membership,
        where: membership.character_id == ^character_id and membership.status == :active
    )
  end

  defp active_journey?(character_id) do
    Repo.exists?(
      from journey in Journey,
        where: journey.character_id == ^character_id and journey.status == :active
    )
  end

  defp members_same_location?(members) do
    members
    |> Enum.map(& &1.character.current_location_id)
    |> Enum.uniq()
    |> length() == 1
  end

  defp preload_party(%Party{} = party) do
    Repo.preload(party, memberships: {active_members_query(), [:character]})
  end

  defp preload_expedition(%Expedition{} = expedition) do
    Repo.preload(expedition, members: [:character])
  end

  defp active_members_query do
    from membership in Membership,
      where: membership.status == :active,
      order_by: [asc: membership.joined_at],
      preload: [:character]
  end

  defp lock_characters(repo, character_ids) do
    Character
    |> where([character], character.id in ^character_ids)
    |> order_by([character], asc: character.id)
    |> lock("FOR UPDATE")
    |> repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp reward_code(attrs, character_id, reward_kind) do
    source_type = attrs["source_type"] || "run"
    source_id = attrs["encounter_id"] || attrs["run_id"] || "unknown"
    "#{source_type}:#{source_id}:#{reward_kind}:#{character_id}"
  end

  defp normalize_source_type("encounter"), do: :encounter
  defp normalize_source_type(:encounter), do: :encounter
  defp normalize_source_type(_source_type), do: :run

  defp normalize_reward_kind("xp"), do: :xp
  defp normalize_reward_kind(:xp), do: :xp
  defp normalize_reward_kind(_reward_kind), do: :xp

  defp lock_party!(party_id) do
    Party
    |> where([party], party.id == ^party_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_expedition!(expedition_id) do
    Expedition
    |> where([expedition], expedition.id == ^expedition_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_expedition_status(status) when status in [:completed, :aborted, :failed],
    do: status

  defp normalize_expedition_status(status) when is_binary(status) do
    case status do
      "completed" -> :completed
      "aborted" -> :aborted
      "failed" -> :failed
      _other -> :completed
    end
  end

  defp normalize_expedition_status(_status), do: :completed

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp active_party_changeset do
    %Membership{}
    |> Changeset.change()
    |> Changeset.add_error(:status, "character already belongs to an active party")
  end

  defp membership_changeset(message) do
    %Membership{}
    |> Changeset.change()
    |> Changeset.add_error(:character_id, message)
  end

  defp party_changeset(message) do
    %Party{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp expedition_changeset(message) do
    %Expedition{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
