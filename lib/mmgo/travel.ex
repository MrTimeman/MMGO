defmodule MMGO.Travel do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Repo
  alias MMGO.Survival
  alias MMGO.Travel.{Clock, CompleteJourneyWorker, Journey}
  alias MMGO.Worlds.Route

  def active_journey(character_id) when is_binary(character_id) do
    Journey
    |> where([journey], journey.character_id == ^character_id and journey.status == :active)
    |> Repo.one()
  end

  def get_journey!(id), do: Repo.get!(Journey, id)

  def list_journeys_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from journey in Journey,
        where: journey.character_id == ^character_id,
        order_by: [desc: journey.inserted_at]
    )
  end

  def start_journey(%Character{} = character, %Route{} = route, opts \\ []) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      route = Repo.get!(Route, route.id)

      if character.realm_id != route.realm_id do
        Repo.rollback(route_changeset("route must belong to the same realm as the character"))
      end

      if active_journey(character.id) do
        Repo.rollback(active_journey_changeset())
      end

      {from_location_id, to_location_id} = resolve_route_direction(character, route)
      plan = Survival.travel_plan(character, route.travel_days)

      food_result =
        case Survival.consume_food(Repo, character, plan.required_food_units) do
          {:ok, food_result} -> food_result
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end

      arrival_at = Clock.arrival_at(started_at, plan.total_game_days)

      journey =
        %Journey{}
        |> Journey.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          route_id: route.id,
          from_location_id: from_location_id,
          to_location_id: to_location_id,
          status: :active,
          travel_days: plan.total_game_days,
          food_units_consumed: food_result.food_units_consumed,
          encumbrance_penalty_days: plan.encumbrance_penalty_days,
          carried_weight: plan.current_weight,
          carry_capacity: plan.carry_capacity,
          started_at: started_at,
          arrival_at: arrival_at
        })
        |> Repo.insert!()

      job =
        %{"journey_id" => journey.id}
        |> CompleteJourneyWorker.new(
          schedule_in: max(DateTime.diff(arrival_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{journey: journey, job: job, character: character}
    end)
    |> normalize_transaction_result()
  end

  def complete_journey_by_id(journey_id, opts \\ []) when is_binary(journey_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      journey =
        Journey
        |> where([journey], journey.id == ^journey_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(journey) do
        Repo.rollback(missing_journey_changeset())
      end

      if journey.status != :active do
        Repo.rollback(journey_status_changeset("journey is not active"))
      end

      if not force? and DateTime.compare(now, journey.arrival_at) == :lt do
        Repo.rollback(journey_status_changeset("journey is not due yet"))
      end

      character = lock_character!(journey.character_id)

      updated_character =
        character
        |> Character.travel_changeset(%{current_location_id: journey.to_location_id})
        |> Repo.update!()

      updated_journey =
        journey
        |> Journey.changeset(%{status: :arrived, completed_at: now})
        |> Repo.update!()

      %{journey: updated_journey, character: updated_character}
    end)
    |> normalize_transaction_result()
  end

  def complete_due_journeys(now \\ DateTime.utc_now()) do
    Journey
    |> where([journey], journey.status == :active and journey.arrival_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn journey -> complete_journey_by_id(journey.id, now: now, force: true) end)
  end

  defp resolve_route_direction(
         %Character{current_location_id: current_location_id},
         %Route{} = route
       )
       when current_location_id == route.origin_location_id do
    {route.origin_location_id, route.destination_location_id}
  end

  defp resolve_route_direction(
         %Character{current_location_id: current_location_id},
         %Route{bidirectional: true} = route
       )
       when current_location_id == route.destination_location_id do
    {route.destination_location_id, route.origin_location_id}
  end

  defp resolve_route_direction(%Character{current_location_id: nil}, _route) do
    Repo.rollback(route_changeset("character must be placed at a location before travelling"))
  end

  defp resolve_route_direction(_character, _route) do
    Repo.rollback(route_changeset("route is not connected to the character's current location"))
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp route_changeset(message) do
    %Journey{}
    |> Changeset.change()
    |> Changeset.add_error(:route_id, message)
  end

  defp active_journey_changeset do
    %Journey{}
    |> Changeset.change()
    |> Changeset.add_error(:status, "character already has an active journey")
  end

  defp journey_status_changeset(message) do
    %Journey{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp missing_journey_changeset do
    %Journey{}
    |> Changeset.change()
    |> Changeset.add_error(:id, "journey could not be found")
  end
end
