defmodule MMGO.Combat.ArenaEventsTest do
  use ExUnit.Case, async: true

  alias MMGO.Combat.ArenaEvents

  test "builds only allowlisted schedules" do
    assert {:ok,
            %{
              "policy" => "fixed",
              "codes" => ["emberfall", "healing_rain"],
              "seed" => 41
            }} = ArenaEvents.schedule(:fixed, ["emberfall", "healing_rain"], 41)

    assert {:error, :invalid_event_code} =
             ArenaEvents.schedule(:random, ["player_supplied_effect"], 41)
  end

  test "random schedules default to the complete event deck" do
    assert {:ok, %{"codes" => codes}} = ArenaEvents.schedule("random", [], 7)
    assert codes == ArenaEvents.event_codes()
    assert length(codes) == length(Enum.uniq(codes))
  end

  test "an event remains active for two turns and resolves deterministically" do
    assert {:ok, schedule} = ArenaEvents.schedule(:random, [], 9_001)

    first_turn = ArenaEvents.event_for_turn(schedule, 1)
    second_turn = ArenaEvents.event_for_turn(schedule, 2)

    assert first_turn["code"] == second_turn["code"]
    assert first_turn["remaining_turns"] == 2
    assert second_turn["remaining_turns"] == 1
    assert first_turn == ArenaEvents.event_for_turn(schedule, 1)
    assert ArenaEvents.active_tags(schedule, 1) == first_turn["tags"]
  end

  test "disabled schedules have no active event" do
    assert {:ok, schedule} = ArenaEvents.schedule(:none, ["emberfall"], 12)
    assert schedule["codes"] == []
    assert ArenaEvents.event_for_turn(schedule, 1) == nil
    assert ArenaEvents.active_tags(schedule, 1) == []
  end

  test "the public catalog omits executable effects" do
    assert Enum.all?(ArenaEvents.catalog(), &(not Map.has_key?(&1, "effect")))
  end
end
