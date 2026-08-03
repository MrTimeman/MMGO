defmodule MMGO.Overworld do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Combat
  alias MMGO.Notifications
  alias MMGO.Overworld.{Encounter, Response}
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds
  alias MMGO.Worlds.Location
  alias MMGO.Worlds.Realm

  @actions [:greet, :trade, :attack, :avoid]
  @contact_decisions [:accept, :decline, :cancel]
  @contact_kind "traveler_contact"
  @sensitive_contact_metadata_keys ~w(
    username
    contact_username
    contact_handle
    telegram_username
    telegram_user_id
  )

  @doc "PubSub topic for committed traveler-contact changes visible to one character."
  def character_topic(character_id) when is_binary(character_id),
    do: "overworld-character:#{character_id}"

  @doc "Returns whether an encounter is the explicit mutual-consent contact flow."
  def contact_request?(%Encounter{} = encounter),
    do: Map.get(encounter.metadata || %{}, "kind") == @contact_kind

  def list_open_encounters_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from encounter in Encounter,
        where:
          (encounter.initiator_character_id == ^character_id or
             encounter.target_character_id == ^character_id) and
            encounter.status in [:pending, :active],
        order_by: [asc: encounter.inserted_at],
        preload: [:location, :initiator_character, :target_character, :combat]
    )
  end

  def get_encounter!(id) do
    Encounter
    |> Repo.get!(id)
    |> Repo.preload([
      :location,
      :initiator_character,
      :target_character,
      :combat,
      responses: :actor_character
    ])
  end

  @doc """
  Closes an escalated overworld encounter after its linked combat finishes.

  Combat owns mechanics; this adapter owns the road-encounter lifecycle. It is
  deliberately idempotent so an Oban retry cannot leave an escalation open or
  record a second outcome.
  """
  def settle_encounter_from_combat(%MMGO.Combat.Combat{} = combat) do
    Repo.transaction(fn ->
      if combat.kind != :overworld_encounter or combat.status != :finished do
        Repo.rollback(encounter_changeset("combat is not a finished overworld encounter"))
      end

      encounter_id = combat.metadata["encounter_id"] || combat.metadata[:encounter_id]
      encounter = lock_encounter!(encounter_id)

      case encounter.status do
        :resolved ->
          Repo.preload(encounter, [:location, :initiator_character, :target_character, :combat])

        :escalated ->
          metadata =
            encounter.metadata
            |> Kernel.||(%{})
            |> Map.merge(%{
              "winner_side" => combat.winner_side,
              "resolved_via" => "combat"
            })

          encounter
          |> Encounter.changeset(%{
            status: :resolved,
            resolved_at: DateTime.utc_now(),
            metadata: metadata
          })
          |> Repo.update!()
          |> Repo.preload([:location, :initiator_character, :target_character, :combat])

        _other ->
          Repo.rollback(encounter_changeset("encounter is not escalated"))
      end
    end)
    |> normalize_transaction_result()
  end

  def create_encounter(%Character{} = initiator, %Character{} = target, attrs \\ %{}) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      {initiator, target} = lock_characters!(initiator.id, target.id)
      validate_encounter_start!(initiator, target)

      location = Repo.get!(Location, initiator.current_location_id)

      %Encounter{}
      |> Encounter.changeset(%{
        realm_id: initiator.realm_id,
        location_id: location.id,
        initiator_character_id: initiator.id,
        target_character_id: target.id,
        encounter_kind: normalize_kind(attrs["encounter_kind"] || :player),
        status: :pending,
        started_at: DateTime.utc_now(),
        metadata: attrs["metadata"] || %{}
      })
      |> Repo.insert!()
      |> Repo.preload([:location, :initiator_character, :target_character])
    end)
    |> normalize_transaction_result()
  end

  @doc """
  Creates a durable request to exchange Telegram contact details.

  Creating the request is the initiator's consent. The contact details are not
  persisted on the encounter and are only delivered after the target accepts.
  """
  def request_contact(%Character{} = initiator, %Character{} = target, attrs \\ %{}) do
    attrs = stringify_keys(attrs)

    metadata =
      attrs
      |> Map.get("metadata", %{})
      |> sanitize_contact_metadata()
      |> Map.put("kind", @contact_kind)

    result = create_encounter(initiator, target, Map.put(attrs, "metadata", metadata))

    case result do
      {:ok, %Encounter{} = encounter} ->
        _ =
          Notifications.notify_overworld_contact_request(
            encounter.target_character,
            encounter,
            encounter.initiator_character
          )

        broadcast_contact_update(encounter)
        result

      {:error, _reason} ->
        result
    end
  end

  @doc """
  Resolves a pending traveler-contact request using a strict consent matrix.

  Only the target can accept or decline. Only the initiator can cancel. A
  contact decision is final and cannot be replaced by a legacy encounter
  action.
  """
  def respond_to_contact(%Encounter{} = encounter, %Character{} = actor, decision) do
    decision = normalize_contact_decision(decision)

    result =
      Repo.transaction(fn ->
        encounter = lock_encounter!(encounter.id)
        actor = lock_character!(actor.id)

        validate_contact_response!(encounter, actor, decision)

        response =
          %Response{}
          |> Response.changeset(%{
            encounter_id: encounter.id,
            actor_character_id: actor.id,
            action: contact_response_action(decision),
            chosen_at: DateTime.utc_now(),
            metadata: %{"contact_decision" => to_string(decision)}
          })
          |> Repo.insert!()

        updated_encounter = finalize_contact_request!(encounter, actor, decision)

        result = %{
          encounter: updated_encounter,
          response: response,
          decision: decision
        }

        notify_contact_result!(result)
        result
      end)
      |> normalize_transaction_result()

    broadcast_contact_result(result)
    result
  end

  def respond(%Encounter{} = encounter, %Character{} = actor, action, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    action = normalize_action(action)

    Repo.transaction(fn ->
      encounter = lock_encounter!(encounter.id)
      actor = lock_character!(actor.id)

      validate_response!(encounter, actor, action)

      response =
        %Response{}
        |> Response.changeset(%{
          encounter_id: encounter.id,
          actor_character_id: actor.id,
          action: action,
          chosen_at: DateTime.utc_now(),
          metadata: attrs["metadata"] || %{}
        })
        |> Repo.insert!()

      result =
        case action do
          :attack -> attack_response!(encounter, actor)
          :avoid -> finalize_encounter!(encounter, :avoided)
          :greet -> maybe_complete_social_encounter!(encounter, :greeted)
          :trade -> maybe_complete_social_encounter!(encounter, :trading)
        end

      Map.put(result, :response, response)
    end)
    |> normalize_transaction_result()
  end

  defp validate_encounter_start!(%Character{} = initiator, %Character{} = target) do
    cond do
      initiator.id == target.id ->
        Repo.rollback(encounter_changeset("character cannot encounter themselves"))

      initiator.realm_id != target.realm_id ->
        Repo.rollback(encounter_changeset("characters must belong to the same realm"))

      is_nil(initiator.current_location_id) or is_nil(target.current_location_id) ->
        Repo.rollback(encounter_changeset("both characters must be at a location"))

      initiator.current_location_id != target.current_location_id ->
        Repo.rollback(encounter_changeset("characters must be at the same location"))

      not is_nil(Travel.active_journey(initiator.id)) or
          not is_nil(Travel.active_journey(target.id)) ->
        Repo.rollback(
          encounter_changeset("travelling characters cannot start an overworld encounter")
        )

      not is_nil(Combat.active_combat_for_character(initiator.id)) or
          not is_nil(Combat.active_combat_for_character(target.id)) ->
        Repo.rollback(
          encounter_changeset("characters already in combat cannot start an overworld encounter")
        )

      active_encounter_exists?(initiator.id, target.id) ->
        Repo.rollback(
          encounter_changeset("an active encounter already exists between these characters")
        )

      true ->
        :ok
    end
  end

  defp validate_response!(%Encounter{} = encounter, %Character{} = actor, action) do
    cond do
      contact_request?(encounter) ->
        Repo.rollback(
          encounter_changeset("contact requests require an explicit consent decision")
        )

      encounter.status not in [:pending, :active] ->
        Repo.rollback(encounter_changeset("encounter is not active"))

      actor.id not in [encounter.initiator_character_id, encounter.target_character_id] ->
        Repo.rollback(encounter_changeset("character does not belong to this encounter"))

      action not in @actions ->
        Repo.rollback(encounter_changeset("action is invalid"))

      response_exists?(encounter.id, actor.id) ->
        Repo.rollback(encounter_changeset("character has already responded to this encounter"))

      true ->
        :ok
    end
  end

  defp validate_contact_response!(%Encounter{} = encounter, %Character{} = actor, decision) do
    cond do
      not contact_request?(encounter) ->
        Repo.rollback(encounter_changeset("encounter is not a traveler contact request"))

      encounter.status != :pending ->
        Repo.rollback(encounter_changeset("contact request is not pending"))

      actor.id not in [encounter.initiator_character_id, encounter.target_character_id] ->
        Repo.rollback(encounter_changeset("character does not belong to this contact request"))

      decision not in @contact_decisions ->
        Repo.rollback(encounter_changeset("contact decision is invalid"))

      decision in [:accept, :decline] and actor.id != encounter.target_character_id ->
        Repo.rollback(encounter_changeset("only the requested traveler may answer"))

      decision == :cancel and actor.id != encounter.initiator_character_id ->
        Repo.rollback(encounter_changeset("only the requesting traveler may cancel"))

      response_exists?(encounter.id, actor.id) ->
        Repo.rollback(encounter_changeset("character has already answered this contact request"))

      true ->
        :ok
    end
  end

  defp attack_response!(%Encounter{} = encounter, %Character{} = actor) do
    location = Repo.get!(Location, encounter.location_id)

    if location.safe_zone do
      Repo.rollback(encounter_changeset("attacks are not allowed in safe zones"))
    end

    realm = Repo.get!(Realm, encounter.realm_id)

    unless Worlds.realm_ruleset(realm)["overworld_pvp_enabled"] do
      Repo.rollback(encounter_changeset("overworld PvP is disabled for this realm"))
    end

    initiator_side =
      if actor.id == encounter.initiator_character_id, do: "attackers", else: "defenders"

    defender_side = if initiator_side == "attackers", do: "defenders", else: "attackers"

    {:ok, %{combat: combat}} =
      Combat.create_overworld_encounter(%Realm{id: encounter.realm_id}, %{
        participants: [
          %{
            character_id: encounter.initiator_character_id,
            side:
              if(actor.id == encounter.initiator_character_id, do: "attackers", else: "defenders"),
            position: 0
          },
          %{
            character_id: encounter.target_character_id,
            side:
              if(actor.id == encounter.target_character_id, do: "attackers", else: "defenders"),
            position: 0
          }
        ],
        metadata: %{
          encounter_id: encounter.id,
          location_id: location.id,
          location_kind: to_string(location.kind),
          initiator_side: initiator_side,
          defender_side: defender_side
        }
      })

    updated_encounter =
      encounter
      |> Encounter.changeset(%{status: :escalated, combat_id: combat.id})
      |> Repo.update!()

    %{
      encounter:
        Repo.preload(updated_encounter, [
          :location,
          :initiator_character,
          :target_character,
          :combat
        ]),
      combat: combat
    }
  end

  defp maybe_complete_social_encounter!(%Encounter{} = encounter, status) do
    responder_count =
      Response
      |> where([response], response.encounter_id == ^encounter.id)
      |> Repo.aggregate(:count, :id)

    if responder_count >= 2 do
      finalize_encounter!(encounter, status)
    else
      %{
        encounter:
          Repo.preload(encounter, [:location, :initiator_character, :target_character, :combat])
      }
    end
  end

  defp finalize_encounter!(%Encounter{} = encounter, status) do
    updated_encounter =
      encounter
      |> Encounter.changeset(%{status: status, resolved_at: DateTime.utc_now()})
      |> Repo.update!()

    %{
      encounter:
        Repo.preload(updated_encounter, [
          :location,
          :initiator_character,
          :target_character,
          :combat
        ])
    }
  end

  defp finalize_contact_request!(%Encounter{} = encounter, %Character{} = actor, decision) do
    status = if decision == :accept, do: :greeted, else: :avoided

    metadata =
      encounter.metadata
      |> Kernel.||(%{})
      |> Map.merge(%{
        "contact_decision" => to_string(decision),
        "contact_responder_character_id" => actor.id
      })

    encounter
    |> Encounter.changeset(%{
      status: status,
      resolved_at: DateTime.utc_now(),
      metadata: metadata
    })
    |> Repo.update!()
    |> Repo.preload([:location, :initiator_character, :target_character, :combat])
  end

  defp active_encounter_exists?(character_a_id, character_b_id) do
    Repo.exists?(
      from encounter in Encounter,
        where:
          encounter.status in [:pending, :active] and
            ((encounter.initiator_character_id == ^character_a_id and
                encounter.target_character_id == ^character_b_id) or
               (encounter.initiator_character_id == ^character_b_id and
                  encounter.target_character_id == ^character_a_id))
    )
  end

  defp response_exists?(encounter_id, actor_character_id) do
    Repo.exists?(
      from response in Response,
        where:
          response.encounter_id == ^encounter_id and
            response.actor_character_id == ^actor_character_id
    )
  end

  defp normalize_kind("player"), do: :player
  defp normalize_kind(:player), do: :player
  defp normalize_kind(_kind), do: :player

  defp normalize_action(action) when action in @actions, do: action
  defp normalize_action("greet"), do: :greet
  defp normalize_action("trade"), do: :trade
  defp normalize_action("attack"), do: :attack
  defp normalize_action("avoid"), do: :avoid
  defp normalize_action(_action), do: nil

  defp normalize_contact_decision(decision) when decision in @contact_decisions, do: decision
  defp normalize_contact_decision("accept"), do: :accept
  defp normalize_contact_decision("decline"), do: :decline
  defp normalize_contact_decision("cancel"), do: :cancel
  defp normalize_contact_decision(_decision), do: nil

  defp contact_response_action(:accept), do: :accept_contact
  defp contact_response_action(:decline), do: :decline_contact
  defp contact_response_action(:cancel), do: :cancel_contact

  defp notify_contact_result!(%{encounter: %Encounter{} = encounter, decision: :accept}) do
    notify_or_rollback!(fn ->
      Notifications.notify_overworld_contact_accepted(
        encounter.initiator_character,
        encounter,
        encounter.target_character
      )
    end)

    notify_or_rollback!(fn ->
      Notifications.notify_overworld_contact_accepted(
        encounter.target_character,
        encounter,
        encounter.initiator_character
      )
    end)
  end

  defp notify_contact_result!(%{encounter: %Encounter{} = encounter, decision: :decline}) do
    notify_or_rollback!(fn ->
      Notifications.notify_overworld_contact_rejected(
        encounter.initiator_character,
        encounter,
        encounter.target_character
      )
    end)
  end

  defp notify_contact_result!(%{encounter: %Encounter{} = encounter, decision: :cancel}) do
    notify_or_rollback!(fn ->
      Notifications.notify_overworld_contact_rejected(
        encounter.target_character,
        encounter,
        encounter.initiator_character
      )
    end)
  end

  defp notify_or_rollback!(fun) do
    case fun.() do
      {:ok, _notification} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp broadcast_contact_result({:ok, %{encounter: %Encounter{} = encounter}}),
    do: broadcast_contact_update(encounter)

  defp broadcast_contact_result(_result), do: :ok

  defp broadcast_contact_update(%Encounter{} = encounter) do
    Enum.each(
      [encounter.initiator_character_id, encounter.target_character_id],
      fn character_id ->
        Phoenix.PubSub.broadcast(
          MMGO.PubSub,
          character_topic(character_id),
          {:overworld_contact_updated, encounter.id}
        )
      end
    )
  end

  defp sanitize_contact_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.reject(fn {key, _value} ->
      key = to_string(key)
      key in @sensitive_contact_metadata_keys or String.starts_with?(key, "telegram_")
    end)
    |> Map.new(fn {key, value} -> {to_string(key), sanitize_contact_metadata(value)} end)
  end

  defp sanitize_contact_metadata(values) when is_list(values),
    do: Enum.map(values, &sanitize_contact_metadata/1)

  defp sanitize_contact_metadata(value), do: value

  defp lock_characters!(character_a_id, character_b_id) do
    characters =
      Character
      |> where([character], character.id in ^Enum.uniq([character_a_id, character_b_id]))
      |> order_by([character], asc: character.id)
      |> lock("FOR UPDATE")
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    {Map.fetch!(characters, character_a_id), Map.fetch!(characters, character_b_id)}
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_encounter!(encounter_id) do
    Encounter
    |> where([encounter], encounter.id == ^encounter_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp encounter_changeset(message) do
    %Encounter{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
