defmodule MMGO.Overworld do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Combat
  alias MMGO.Overworld.{Encounter, Response}
  alias MMGO.Repo
  alias MMGO.Travel
  alias MMGO.Worlds.Location
  alias MMGO.Worlds.Realm

  @actions [:greet, :trade, :attack, :avoid]

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

  def create_encounter(%Character{} = initiator, %Character{} = target, attrs \\ %{}) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      initiator = lock_character!(initiator.id)
      target = lock_character!(target.id)
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

  defp attack_response!(%Encounter{} = encounter, %Character{} = actor) do
    location = Repo.get!(Location, encounter.location_id)

    if location.safe_zone do
      Repo.rollback(encounter_changeset("attacks are not allowed in safe zones"))
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
