defmodule MMGO.Travel.ClockTest do
  use ExUnit.Case, async: true

  alias MMGO.Travel.Clock

  test "game_days_to_real_seconds/1 compresses the world clock" do
    assert Clock.game_days_to_real_seconds(1) == 237
    assert Clock.game_days_to_real_seconds(10) == 2_374
  end

  test "game_hours_to_real_seconds/1 follows the continuously running world clock" do
    assert Clock.game_hours_to_real_seconds(0) == 0
    assert Clock.game_hours_to_real_seconds(1) == 10
    assert Clock.game_hours_to_real_seconds(24) == Clock.game_days_to_real_seconds(1)
  end

  test "arrival_at/2 adds compressed travel duration" do
    started_at = ~U[2026-03-27 12:00:00Z]
    assert Clock.arrival_at(started_at, 10) == ~U[2026-03-27 12:39:34Z]
  end

  test "world_time/2 projects server time onto thirteen 28-day months" do
    epoch = ~U[2026-01-01 00:00:00Z]

    assert %{year: 847, month_number: 1, day: 1, season: :spring} =
             Clock.world_time(epoch, epoch: epoch)

    seventh_month = DateTime.add(epoch, Clock.game_days_to_real_seconds(6 * 28), :second)

    assert %{month_number: 7, month_name: "Месяц Жатвы", day: 1, season: :autumn} =
             Clock.world_time(seventh_month, epoch: epoch)

    next_year = DateTime.add(epoch, Clock.game_days_to_real_seconds(364), :second)

    assert %{year: 848, month_number: 1, day: 1} = Clock.world_time(next_year, epoch: epoch)
  end
end
