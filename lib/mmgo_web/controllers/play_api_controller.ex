defmodule MMGOWeb.PlayApiController do
  use MMGOWeb, :controller

  alias MMGO.Play

  def state(conn, _params) do
    with {:ok, character_id} <- demo_character_id(conn),
         {:ok, state} <- Play.load_demo_state(character_id) do
      json(conn, state_payload(state))
    else
      {:error, _reason} -> json(conn, %{character: nil})
    end
  end

  def create_journey(conn, params) do
    with {:ok, character_id} <- demo_character_id(conn),
         {:ok, destination_slug} <- fetch_destination_slug(params),
         {:ok, %{journey: journey}} <- Play.start_journey(character_id, destination_slug) do
      json(conn, %{ok: true, journey: journey_payload(journey)})
    else
      {:error, :not_found} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "demo session not started"})

      {:error, :missing_destination} ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "destination_slug is required"})

      {:error, :no_direct_route} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "no direct route"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_changeset(changeset)})
    end
  end

  defp demo_character_id(conn) do
    case get_session(conn, :demo_character_id) do
      nil -> {:error, :not_found}
      character_id -> {:ok, character_id}
    end
  end

  defp state_payload(state) do
    %{
      character: %{
        id: state.character.id,
        name: state.character.name,
        level: state.character.level,
        realm_id: state.character.realm_id,
        food_units: state.food_units,
        current_location: location_payload(state.current_location)
      },
      routes: Enum.map(state.routes, &route_payload(&1, state.character.current_location_id)),
      active_journey: journey_payload(state.active_journey),
      known_spells: Enum.map(state.spells, &spell_payload/1),
      duel: duel_payload(state.duel)
    }
  end

  defp fetch_destination_slug(params) do
    case params["destination_slug"] || params["slug"] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :missing_destination}
    end
  end

  defp location_payload(nil), do: nil

  defp location_payload(location) do
    %{
      id: location.id,
      slug: location.slug,
      name: location.name,
      kind: location.kind,
      safe_zone: location.safe_zone
    }
  end

  defp route_payload(route, current_location_id) do
    destination = Play.route_destination(route, current_location_id)

    %{
      id: route.id,
      name: route.name,
      destination: location_payload(destination),
      travel_days: route.travel_days,
      risk_level: route.risk_level,
      required_food_units: route.travel_days
    }
  end

  defp journey_payload(nil), do: nil

  defp journey_payload(journey) do
    %{
      id: journey.id,
      status: journey.status,
      from_location: location_payload(journey.from_location),
      to_location: location_payload(journey.to_location),
      travel_days: journey.travel_days,
      food_units_consumed: journey.food_units_consumed,
      arrival_at: journey.arrival_at
    }
  end

  defp spell_payload(spell) do
    %{
      id: spell.id,
      name: spell.name,
      school: spell.school,
      fatigue_cost: spell.fatigue_cost,
      cooldown_turns: spell.cooldown_turns
    }
  end

  defp duel_payload(%{active_duel: active_duel, pending_duels: pending_duels}) do
    %{
      active_duel: duel_item_payload(active_duel),
      pending_duels: Enum.map(pending_duels, &duel_item_payload/1)
    }
  end

  defp duel_payload(_duel), do: %{active_duel: nil, pending_duels: []}

  defp duel_item_payload(nil), do: nil

  defp duel_item_payload(duel) do
    %{
      id: duel.id,
      status: duel.status,
      stake_amount: duel.stake_amount,
      pot_amount: duel.pot_amount
    }
  end

  defp format_changeset(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
