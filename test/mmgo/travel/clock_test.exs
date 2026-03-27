defmodule MMGO.Travel.ClockTest do
  use ExUnit.Case, async: true

  alias MMGO.Travel.Clock

  test "game_days_to_real_seconds/1 compresses the world clock" do
    assert Clock.game_days_to_real_seconds(1) == 237
    assert Clock.game_days_to_real_seconds(10) == 2_374
  end

  test "arrival_at/2 adds compressed travel duration" do
    started_at = ~U[2026-03-27 12:00:00Z]
    assert Clock.arrival_at(started_at, 10) == ~U[2026-03-27 12:39:34Z]
  end
end
