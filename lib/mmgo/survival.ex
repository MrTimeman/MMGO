defmodule MMGO.Survival do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Survival.State
  alias MMGO.Worlds

  def carry_capacity(%Character{} = character) do
    base_capacity = 20 + character.level * 2
    bonus = character.metadata["carry_capacity_bonus"] || 0
    scale_bps = Worlds.realm_ruleset(character.realm_id)["carry_capacity_scale_bps"]

    div((base_capacity + bonus) * scale_bps, 1_000)
  end

  def carried_weight(%Character{} = character) do
    inventory_weight(character.id) + active_grimoire_weight(character.id)
  end

  def food_units_available(%Character{} = character) do
    food_inventory_items(character.id)
    |> Enum.reduce(0, fn item, total ->
      total + Inventory.available_quantity(item) * item.item_template.nutrition_units
    end)
  end

  def travel_plan(%Character{} = character, base_game_days)
      when is_integer(base_game_days) and base_game_days > 0 do
    current_weight = carried_weight(character)
    capacity = carry_capacity(character)
    penalty_days = encumbrance_penalty_days(current_weight, capacity, base_game_days)
    food_units = food_units_available(character)
    daily_food_units = food_units_per_game_day(character)
    baseline_game_days = base_game_days + penalty_days

    movement_penalty_days =
      if food_units < baseline_game_days * daily_food_units do
        1
      else
        0
      end

    total_game_days = baseline_game_days + movement_penalty_days
    required_food_units = total_game_days * daily_food_units
    food_shortage_days = ceil_div(max(required_food_units - food_units, 0), daily_food_units)

    %{
      current_weight: current_weight,
      carry_capacity: capacity,
      encumbered?: current_weight > capacity,
      encumbrance_penalty_days: penalty_days,
      total_game_days: total_game_days,
      required_food_units: required_food_units,
      food_units_available: food_units,
      daily_food_units: daily_food_units,
      food_shortage_days: food_shortage_days,
      movement_penalty_days: movement_penalty_days,
      health_drain: max(food_shortage_days - 1, 0)
    }
  end

  @doc """
  Returns the live player-facing survival state. Carry and flee consequences
  are calculated from real inventory/grimoire state, while starvation comes
  from the durable `Survival.State` record on the character.
  """
  def summary(%Character{} = character) do
    food_units = food_units_available(character)
    carried_weight = carried_weight(character)
    carry_capacity = carry_capacity(character)

    State.summary(State.load(character))
    |> Map.merge(%{
      food_units: food_units,
      carried_weight: carried_weight,
      carry_capacity: carry_capacity,
      encumbered?: carried_weight > carry_capacity,
      flee_available?: carried_weight <= carry_capacity
    })
  end

  @doc """
  Applies a completed journey or expedition's food-shortage consequence to a
  character. Expedition code can reuse this without knowing how state is
  serialized on the character.
  """
  def apply_starvation_consequences(repo \\ Repo, %Character{} = character, attrs)
      when is_map(attrs) do
    State.apply_journey_outcome(repo, character, attrs)
  end

  @doc """
  Clears recoverable starvation consequences after a supported food source is
  received or consumed. Inventory gains call this directly; a protected base
  rest calls it only after consuming a stored ration in the same transaction.
  """
  def recover_after_food(repo \\ Repo, %Character{} = character) do
    State.recover_after_food(repo, character)
  end

  def expedition_supply_summary(expedition_id) when is_binary(expedition_id) do
    expedition_id
    |> Parties.active_members_for_expedition()
    |> expedition_supply_summary()
  end

  def expedition_supply_summary(members) when is_list(members) do
    members = Enum.filter(members, &(&1.status == :active))

    member_summaries =
      Enum.map(members, fn member ->
        character = member.character || Repo.get!(Character, member.character_id)

        %{
          character_id: member.character_id,
          food_units: food_units_available(character),
          carried_weight: carried_weight(character),
          carry_capacity: carry_capacity(character)
        }
      end)

    total_food_units = Enum.reduce(member_summaries, 0, &(&1.food_units + &2))
    total_weight = Enum.reduce(member_summaries, 0, &(&1.carried_weight + &2))
    total_capacity = Enum.reduce(member_summaries, 0, &(&1.carry_capacity + &2))
    daily_food_demand = length(member_summaries)

    %{
      member_count: length(member_summaries),
      daily_food_demand: daily_food_demand,
      total_food_units: total_food_units,
      projected_days:
        if(daily_food_demand > 0, do: div(total_food_units, daily_food_demand), else: 0),
      total_carried_weight: total_weight,
      total_carry_capacity: total_capacity,
      encumbered?: total_weight > total_capacity,
      members: member_summaries
    }
  end

  def consume_food(repo \\ Repo, %Character{} = character, requested_units)
      when is_integer(requested_units) do
    cond do
      requested_units < 0 ->
        {:error, food_changeset("requested food must be zero or positive")}

      requested_units == 0 ->
        {:ok, %{food_units_consumed: 0, consumed_items: []}}

      true ->
        items = lock_food_items(repo, character.id)

        available_units = food_units_in_items(items)

        if available_units < requested_units do
          {:error, food_changeset("not enough food for the requested activity")}
        else
          consume_food_items(repo, items, requested_units)
        end
    end
  end

  @doc """
  Consumes every available food unit up to the requested journey demand.
  Unlike `consume_food/3`, it deliberately permits a shortfall and returns
  that deficit for Travel to persist as a starvation consequence.
  """
  def consume_available_food(repo \\ Repo, %Character{} = character, requested_units)
      when is_integer(requested_units) do
    cond do
      requested_units < 0 ->
        {:error, food_changeset("requested food must be zero or positive")}

      requested_units == 0 ->
        {:ok, %{food_units_consumed: 0, food_shortage_units: 0, consumed_items: []}}

      true ->
        items = lock_food_items(repo, character.id)
        available_units = food_units_in_items(items)
        units_to_consume = min(requested_units, available_units)

        with {:ok, result} <- consume_food_items(repo, items, units_to_consume) do
          {:ok, Map.put(result, :food_shortage_units, max(requested_units - available_units, 0))}
        end
    end
  end

  defp inventory_weight(character_id) do
    InventoryItem
    |> where([item], item.character_id == ^character_id and item.quantity > 0)
    |> preload(:item_template)
    |> Repo.all()
    |> Enum.reduce(0, fn item, total -> total + item.quantity * item.item_template.weight end)
  end

  defp active_grimoire_weight(character_id) do
    case Grimoires.active_grimoire_for_character(character_id) do
      nil -> 0
      grimoire -> grimoire.weight
    end
  end

  defp food_inventory_items(character_id) do
    InventoryItem
    |> where(
      [item],
      item.character_id == ^character_id and item.quantity > item.reserved_quantity
    )
    |> join(:inner, [item], template in assoc(item, :item_template))
    |> where([_item, template], template.item_type == :food and template.nutrition_units > 0)
    |> order_by([item, _template], asc: item.inserted_at)
    |> preload(:item_template)
    |> Repo.all()
  end

  defp lock_food_items(repo, character_id) do
    InventoryItem
    |> where(
      [item],
      item.character_id == ^character_id and item.quantity > item.reserved_quantity
    )
    |> join(:inner, [item], template in assoc(item, :item_template))
    |> where([_item, template], template.item_type == :food and template.nutrition_units > 0)
    |> order_by([item, _template], asc: item.inserted_at)
    |> lock("FOR UPDATE")
    |> preload(:item_template)
    |> repo.all()
  end

  defp food_units_in_items(items) do
    Enum.reduce(items, 0, fn item, total ->
      total + Inventory.available_quantity(item) * item.item_template.nutrition_units
    end)
  end

  defp consume_food_items(_repo, _items, 0) do
    {:ok, %{food_units_consumed: 0, consumed_items: []}}
  end

  defp consume_food_items(repo, items, requested_units) do
    {remaining_units, actual_consumed_units, consumed_items} =
      Enum.reduce_while(items, {requested_units, 0, []}, fn item,
                                                            {remaining, consumed, consumed_items} ->
        if remaining <= 0 do
          {:halt, {remaining, consumed, consumed_items}}
        else
          nutrition_units = item.item_template.nutrition_units

          items_to_consume =
            min(Inventory.available_quantity(item), ceil_div(remaining, nutrition_units))

          consumed_units = items_to_consume * nutrition_units
          updated_quantity = item.quantity - items_to_consume

          if updated_quantity == 0 do
            repo.delete!(item)
          else
            item
            |> InventoryItem.changeset(%{quantity: updated_quantity})
            |> repo.update!()
          end

          {:cont,
           {
             max(remaining - consumed_units, 0),
             consumed + consumed_units,
             [
               %{
                 inventory_item_id: item.id,
                 item_template_id: item.item_template_id,
                 quantity: items_to_consume,
                 nutrition_units: consumed_units
               }
               | consumed_items
             ]
           }}
        end
      end)

    if remaining_units > 0 do
      {:error, food_changeset("food consumption did not complete successfully")}
    else
      {:ok,
       %{
         food_units_consumed: actual_consumed_units,
         consumed_items: Enum.reverse(consumed_items)
       }}
    end
  end

  defp encumbrance_penalty_days(current_weight, carry_capacity, base_game_days) do
    overload = max(current_weight - carry_capacity, 0)

    if overload == 0 do
      0
    else
      ceil_div(base_game_days * overload, max(carry_capacity, 1))
    end
  end

  defp food_units_per_game_day(%Character{} = character) do
    Worlds.realm_ruleset(character.realm_id)["travel_food_units_per_day"]
  end

  defp ceil_div(value, divisor) when divisor > 0 do
    div(value + divisor - 1, divisor)
  end

  defp food_changeset(message) do
    %ItemTemplate{}
    |> Changeset.change()
    |> Changeset.add_error(:nutrition_units, message)
  end
end
