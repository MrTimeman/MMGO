defmodule MMGO.Parties do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Clubs
  alias MMGO.Notifications
  alias MMGO.Parties.{Expedition, ExpeditionMember, Membership, Party, Reward}
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Survival
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

  @doc "PubSub topic for committed changes visible to an active party."
  def party_topic(party_id) when is_binary(party_id), do: "party:#{party_id}"

  @doc "PubSub topic for a character's private party invitation and membership changes."
  def character_topic(character_id) when is_binary(character_id),
    do: "party-character:#{character_id}"

  @doc "Broadcasts a committed non-party state change to the character's active party."
  def notify_character_state_changed(character_id) when is_binary(character_id) do
    case active_party_for_character(character_id) do
      %Party{} = party -> broadcast_party_update(party.id)
      nil -> :ok
    end
  end

  def notify_character_state_changed(_character_id), do: :ok

  def create_party(%Character{} = leader, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    name = attrs["name"] || "Отряд: #{leader.name}"
    now = DateTime.utc_now()

    result =
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

    notify_party_result(result, [leader.id])
    result
  end

  @doc """
  Creates a durable, pending party invitation under the party row lock. Party
  metadata is an existing persisted extension point, used here because the
  migration generator is unavailable in this sandbox; it is never client-side
  state.
  """
  def invite_member(%Party{} = party, %Character{} = inviter, %Character{} = invitee) do
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        party = lock_party!(party.id)
        inviter = lock_character!(inviter.id)
        invitee = lock_character!(invitee.id)

        validate_party_invitation!(party, inviter, invitee)

        invitation = %{
          "id" => Ecto.UUID.generate(),
          "inviter_character_id" => inviter.id,
          "invitee_character_id" => invitee.id,
          "status" => "pending",
          "created_at" => DateTime.to_iso8601(now)
        }

        updated_party =
          party
          |> Party.changeset(%{
            metadata: put_party_invitations(party, [invitation | party_invitations(party)])
          })
          |> Repo.update!()

        %{party: preload_party(updated_party), invitation: invitation}
      end)
      |> normalize_transaction_result()

    case result do
      {:ok, %{party: updated_party, invitation: invitation}} ->
        _ = Notifications.notify_party_invitation(invitee, invitation, updated_party)

      _other ->
        :ok
    end

    notify_party_result(result, [invitee.id])
    result
  end

  @doc "Lists pending invitations that belong to one character."
  def pending_invitations_for_character(character_id) when is_binary(character_id) do
    Party
    |> where([party], party.status == :active)
    |> Repo.all()
    |> Enum.flat_map(fn party ->
      party
      |> party_invitations()
      |> Enum.filter(fn invitation ->
        invitation["status"] == "pending" and invitation["invitee_character_id"] == character_id
      end)
      |> Enum.map(fn invitation ->
        %{
          id: invitation["id"],
          party: preload_party(party),
          inviter_character: Repo.get(Character, invitation["inviter_character_id"]),
          created_at: invitation["created_at"]
        }
      end)
    end)
  end

  def accept_invitation(invitation_id, %Character{} = invitee) when is_binary(invitation_id) do
    with {%Party{} = party, _invitation} <- find_pending_invitation(invitation_id, invitee.id) do
      now = DateTime.utc_now()

      result =
        Repo.transaction(fn ->
          party = lock_party!(party.id)
          invitee = lock_character!(invitee.id)

          invitation = find_pending_invitation_in_party(party, invitation_id, invitee.id)

          if is_nil(invitation) do
            Repo.rollback(invitation_changeset("party invitation is not pending"))
          end

          validate_joinable!(party, invitee)

          membership =
            %Membership{}
            |> Membership.changeset(%{
              party_id: party.id,
              character_id: invitee.id,
              role: :member,
              status: :active,
              joined_at: now,
              metadata: %{"ready" => true}
            })
            |> Repo.insert!()

          updated_invitations =
            update_party_invitation_status(party, invitation_id, "accepted", now)

          updated_party =
            party
            |> Party.changeset(%{metadata: put_party_invitations(party, updated_invitations)})
            |> Repo.update!()

          %{party: preload_party(updated_party), membership: membership}
        end)
        |> normalize_transaction_result()

      notify_party_result(result, [invitee.id])
      result
    else
      nil -> {:error, invitation_changeset("party invitation could not be found")}
    end
  end

  def accept_invitation(_invitation_id, _invitee),
    do: {:error, invitation_changeset("party invitation could not be found")}

  def reject_invitation(invitation_id, %Character{} = invitee) when is_binary(invitation_id) do
    with {%Party{} = party, _invitation} <- find_pending_invitation(invitation_id, invitee.id) do
      now = DateTime.utc_now()

      result =
        Repo.transaction(fn ->
          party = lock_party!(party.id)
          invitee = lock_character!(invitee.id)

          if is_nil(find_pending_invitation_in_party(party, invitation_id, invitee.id)) do
            Repo.rollback(invitation_changeset("party invitation is not pending"))
          end

          updated_invitations =
            update_party_invitation_status(party, invitation_id, "rejected", now)

          party
          |> Party.changeset(%{metadata: put_party_invitations(party, updated_invitations)})
          |> Repo.update!()
        end)
        |> normalize_transaction_result()

      notify_party_result(result, [invitee.id])
      result
    else
      nil -> {:error, invitation_changeset("party invitation could not be found")}
    end
  end

  def reject_invitation(_invitation_id, _invitee),
    do: {:error, invitation_changeset("party invitation could not be found")}

  @doc "Sets the calling member's explicit expedition readiness flag."
  def set_member_ready(%Party{} = party, %Character{} = character, ready?)
      when is_boolean(ready?) do
    result =
      Repo.transaction(fn ->
        party = lock_party!(party.id)

        membership =
          Membership
          |> where(
            [membership],
            membership.party_id == ^party.id and membership.character_id == ^character.id and
              membership.status == :active
          )
          |> lock("FOR UPDATE")
          |> Repo.one()

        if is_nil(membership) do
          Repo.rollback(membership_changeset("character is not an active party member"))
        end

        membership
        |> Membership.changeset(%{metadata: Map.put(membership.metadata || %{}, "ready", ready?)})
        |> Repo.update!()
      end)
      |> normalize_transaction_result()

    notify_party_result(result, party.id, [character.id])
    result
  end

  def set_member_ready(_party, _character, _ready?),
    do: {:error, membership_changeset("ready state is invalid")}

  @doc "Lets the party leader set a bounded, persisted loot policy."
  def set_loot_policy(%Party{} = party, %Character{} = actor, policy) do
    with {:ok, policy} <- normalize_loot_policy(policy) do
      result =
        Repo.transaction(fn ->
          party = lock_party!(party.id)

          if party.leader_character_id != actor.id do
            Repo.rollback(party_changeset("only the party leader can set loot policy"))
          end

          metadata = Map.put(party.metadata || %{}, "loot_policy", policy)

          party
          |> Party.changeset(%{metadata: metadata})
          |> Repo.update!()
          |> preload_party()
        end)
        |> normalize_transaction_result()

      notify_party_result(result)
      result
    end
  end

  def add_member(%Party{} = party, %Character{} = character) do
    now = DateTime.utc_now()

    result =
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

    notify_party_result(result, [character.id])
    result
  end

  def remove_member(%Party{} = party, %Character{} = character) do
    now = DateTime.utc_now()

    result =
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

    notify_party_result(result, [character.id])
    result
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

    result =
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

        supply_summary = Survival.expedition_supply_summary(members)

        route_plan =
          case Clubs.consume_expedition_plan_for_members(
                 Enum.map(members, & &1.character_id),
                 party.realm_id,
                 now: started_at
               ) do
            {:ok, plan} -> plan
            {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          end

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
            started_at: started_at,
            metadata: expedition_metadata(route_plan, supply_summary)
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

    notify_party_result(result, party.id)
    result
  end

  def end_expedition(%Expedition{} = expedition, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    status = normalize_expedition_status(attrs["status"] || :completed)
    ended_at = attrs["ended_at"] || DateTime.utc_now()

    result =
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

    notify_party_result(result, expedition.party_id)
    result
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

      Enum.any?(members, &(not member_ready?(&1))) ->
        Repo.rollback(expedition_changeset("all party members must be ready"))

      true ->
        :ok
    end
  end

  @doc """
  Returns the durable survival ledger for an expedition.

  Food is intentionally taken from the supplies present when the expedition
  starts, rather than from the members' mutable inventories. Older expeditions
  that predate the ledger safely fall back to their persisted snapshots.
  """
  def expedition_survival_state(%Expedition{} = expedition) do
    initial_food = non_negative_integer(expedition.food_units_snapshot, 0)
    daily_food_demand = non_negative_integer(expedition.daily_food_demand, 0)
    carried_weight = non_negative_integer(expedition.carried_weight, 0)
    carry_capacity = non_negative_integer(expedition.carry_capacity, 0)
    metadata = expedition.metadata || %{}

    stored_state =
      case Map.get(metadata, "survival") do
        state when is_map(state) -> state
        _other -> %{}
      end

    food_units_remaining =
      stored_state
      |> Map.get("food_units_remaining", initial_food)
      |> non_negative_integer(initial_food)
      |> min(initial_food)

    %{
      food_units_initial: initial_food,
      food_units_remaining: food_units_remaining,
      food_units_consumed: initial_food - food_units_remaining,
      daily_food_demand: daily_food_demand,
      foodless_game_days:
        stored_state
        |> Map.get("foodless_game_days", 0)
        |> non_negative_integer(0),
      shared_hp_drain:
        stored_state
        |> Map.get("shared_hp_drain", 0)
        |> non_negative_integer(0),
      movement_penalty_days:
        stored_state
        |> Map.get("movement_penalty_days", 0)
        |> non_negative_integer(0),
      carried_weight: carried_weight,
      carry_capacity: carry_capacity,
      encumbered?: carried_weight > carry_capacity
    }
  end

  @doc """
  Advances an expedition's persisted survival ledger for a dungeon activity.

  The caller owns the database transaction and writes `metadata` to the
  already-locked expedition. Movement retains its foodless and encumbrance
  penalties; stationary activities such as scavenging consume their declared
  game-days and can cause starvation, but do not pretend to be extra movement.
  The drain is cumulative but is intentionally capped by the dungeon combat
  boundary so starvation alone cannot kill a party.
  """
  def advance_expedition_survival(expedition, game_days, opts \\ [])

  def advance_expedition_survival(%Expedition{} = expedition, game_days, opts)
      when is_integer(game_days) and game_days > 0 and is_list(opts) do
    activity = normalize_survival_activity(Keyword.get(opts, :activity, :movement))
    survival = expedition_survival_state(expedition)
    food_units_required = game_days * survival.daily_food_demand
    food_units_consumed = min(survival.food_units_remaining, food_units_required)
    food_shortage_units = food_units_required - food_units_consumed
    foodless_game_days = shortage_days(food_shortage_units, survival.daily_food_demand)

    previous_foodless_game_days = survival.foodless_game_days
    total_foodless_game_days = previous_foodless_game_days + foodless_game_days

    newly_starving_game_days =
      max(total_foodless_game_days - 1, 0) - max(previous_foodless_game_days - 1, 0)

    shared_hp_drain = newly_starving_game_days * survival.daily_food_demand

    encumbrance_penalty_days =
      if activity == :movement and survival.encumbered?, do: game_days, else: 0

    movement_penalty_days =
      if activity == :movement, do: foodless_game_days + encumbrance_penalty_days, else: 0

    activity_metadata = %{
      "activity" => Atom.to_string(activity),
      "game_days" => game_days,
      "food_units_required" => food_units_required,
      "food_units_consumed" => food_units_consumed,
      "food_shortage_units" => food_shortage_units,
      "foodless_game_days" => foodless_game_days,
      "shared_hp_drain" => shared_hp_drain,
      "encumbrance_penalty_days" => encumbrance_penalty_days,
      "movement_penalty_days" => movement_penalty_days
    }

    updated_survival =
      %{
        "food_units_initial" => survival.food_units_initial,
        "food_units_remaining" => survival.food_units_remaining - food_units_consumed,
        "food_units_consumed" => survival.food_units_consumed + food_units_consumed,
        "foodless_game_days" => total_foodless_game_days,
        "shared_hp_drain" => survival.shared_hp_drain + shared_hp_drain,
        "movement_penalty_days" => survival.movement_penalty_days + movement_penalty_days,
        "last_activity" => activity_metadata
      }
      |> maybe_put_last_movement(activity, game_days, activity_metadata)

    %{
      metadata: Map.put(expedition.metadata || %{}, "survival", updated_survival),
      survival:
        Map.merge(survival, %{
          food_units_remaining: updated_survival["food_units_remaining"],
          food_units_consumed: updated_survival["food_units_consumed"],
          foodless_game_days: updated_survival["foodless_game_days"],
          shared_hp_drain: updated_survival["shared_hp_drain"],
          movement_penalty_days: updated_survival["movement_penalty_days"]
        }),
      food_units_required: food_units_required,
      food_units_consumed: food_units_consumed,
      food_shortage_units: food_shortage_units,
      foodless_game_days: foodless_game_days,
      shared_hp_drain: shared_hp_drain,
      encumbrance_penalty_days: encumbrance_penalty_days,
      movement_penalty_days: movement_penalty_days,
      effective_travel_cost: game_days + movement_penalty_days,
      activity: activity,
      game_days: game_days
    }
  end

  defp expedition_metadata(route_plan, supply_summary) do
    metadata = if(route_plan, do: %{"club_route_plan" => route_plan}, else: %{})

    Map.put(metadata, "survival", %{
      "food_units_initial" => supply_summary.total_food_units,
      "food_units_remaining" => supply_summary.total_food_units,
      "food_units_consumed" => 0,
      "foodless_game_days" => 0,
      "shared_hp_drain" => 0,
      "movement_penalty_days" => 0,
      "encumbered" => supply_summary.encumbered?
    })
  end

  defp shortage_days(_food_shortage_units, 0), do: 0

  defp shortage_days(food_shortage_units, daily_food_demand) do
    div(food_shortage_units + daily_food_demand - 1, daily_food_demand)
  end

  defp maybe_put_last_movement(updated_survival, :movement, game_days, activity_metadata) do
    Map.put(
      updated_survival,
      "last_movement",
      Map.put(activity_metadata, "travel_cost", game_days)
    )
  end

  defp maybe_put_last_movement(updated_survival, _activity, _game_days, _activity_metadata),
    do: updated_survival

  defp normalize_survival_activity(:scavenging), do: :scavenging
  defp normalize_survival_activity(_activity), do: :movement

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp active_membership?(character_id) do
    Repo.exists?(
      from membership in Membership,
        where: membership.character_id == ^character_id and membership.status == :active
    )
  end

  defp notify_party_result(result), do: notify_party_result(result, [])

  defp notify_party_result({:ok, %{party: %Party{} = party}}, extra_character_ids)
       when is_list(extra_character_ids) do
    broadcast_party_update(party.id, extra_character_ids)
  end

  defp notify_party_result({:ok, %Party{} = party}, extra_character_ids)
       when is_list(extra_character_ids) do
    broadcast_party_update(party.id, extra_character_ids)
  end

  defp notify_party_result({:ok, _result}, party_id) when is_binary(party_id) do
    broadcast_party_update(party_id)
  end

  defp notify_party_result(_result, _extra_character_ids), do: :ok

  defp notify_party_result({:ok, _result}, party_id, extra_character_ids)
       when is_binary(party_id) and is_list(extra_character_ids) do
    broadcast_party_update(party_id, extra_character_ids)
  end

  defp notify_party_result(_result, _party_id, _extra_character_ids), do: :ok

  defp broadcast_party_update(party_id, extra_character_ids \\ []) do
    Phoenix.PubSub.broadcast(MMGO.PubSub, party_topic(party_id), {:party_updated, party_id})

    extra_character_ids
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.each(fn character_id ->
      Phoenix.PubSub.broadcast(
        MMGO.PubSub,
        character_topic(character_id),
        {:party_updated, party_id}
      )
    end)
  end

  defp member_ready?(%Membership{metadata: metadata}) do
    # Legacy parties predate readiness and remain ready until a player
    # explicitly marks themselves unready.
    Map.get(metadata || %{}, "ready", true) == true
  end

  defp validate_party_invitation!(
         %Party{} = party,
         %Character{} = inviter,
         %Character{} = invitee
       ) do
    inviter_membership =
      Membership
      |> where(
        [membership],
        membership.party_id == ^party.id and membership.character_id == ^inviter.id and
          membership.status == :active
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      party.status != :active ->
        Repo.rollback(party_changeset("party is not active"))

      is_nil(inviter_membership) or inviter_membership.role != :leader ->
        Repo.rollback(party_changeset("only the party leader can invite members"))

      inviter.realm_id != invitee.realm_id ->
        Repo.rollback(party_changeset("invitee must belong to the same realm"))

      active_membership?(invitee.id) ->
        Repo.rollback(active_party_changeset())

      Enum.any?(party_invitations(party), fn invitation ->
        invitation["status"] == "pending" and invitation["invitee_character_id"] == invitee.id
      end) ->
        Repo.rollback(invitation_changeset("invitee already has a pending party invitation"))

      true ->
        :ok
    end
  end

  defp party_invitations(%Party{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "invitations", []) do
      invitations when is_list(invitations) -> Enum.filter(invitations, &is_map/1)
      _other -> []
    end
  end

  defp party_invitations(_party), do: []

  defp put_party_invitations(%Party{metadata: metadata}, invitations) do
    Map.put(metadata || %{}, "invitations", invitations)
  end

  defp find_pending_invitation(invitation_id, invitee_character_id) do
    Party
    |> where([party], party.status == :active)
    |> Repo.all()
    |> Enum.find_value(fn party ->
      case find_pending_invitation_in_party(party, invitation_id, invitee_character_id) do
        nil -> nil
        invitation -> {party, invitation}
      end
    end)
  end

  defp find_pending_invitation_in_party(%Party{} = party, invitation_id, invitee_character_id) do
    Enum.find(party_invitations(party), fn invitation ->
      invitation["id"] == invitation_id and invitation["status"] == "pending" and
        invitation["invitee_character_id"] == invitee_character_id
    end)
  end

  defp update_party_invitation_status(%Party{} = party, invitation_id, status, now) do
    Enum.map(party_invitations(party), fn invitation ->
      if invitation["id"] == invitation_id do
        invitation
        |> Map.put("status", status)
        |> Map.put("resolved_at", DateTime.to_iso8601(now))
      else
        invitation
      end
    end)
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

    suffix =
      case attrs["reward_code_suffix"] do
        value when is_binary(value) and byte_size(value) > 0 -> ":#{String.slice(value, 0, 120)}"
        _other -> ""
      end

    "#{source_type}:#{source_id}:#{reward_kind}:#{character_id}#{suffix}"
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

  defp normalize_loot_policy(policy) when policy in [:round_robin, :leader, :free_for_all],
    do: {:ok, Atom.to_string(policy)}

  defp normalize_loot_policy(policy) when is_binary(policy) do
    case policy do
      "round_robin" -> {:ok, policy}
      "leader" -> {:ok, policy}
      "free_for_all" -> {:ok, policy}
      _other -> {:error, party_changeset("loot policy is invalid")}
    end
  end

  defp normalize_loot_policy(_policy), do: {:error, party_changeset("loot policy is invalid")}

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

  defp invitation_changeset(message) do
    %Party{}
    |> Changeset.change()
    |> Changeset.add_error(:metadata, message)
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
