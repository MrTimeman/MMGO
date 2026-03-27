defmodule MMGO.Travel.Clock do
  @seconds_per_real_day 86_400
  @game_days_per_real_day 364

  def game_days_to_real_seconds(game_days) when is_integer(game_days) and game_days >= 0 do
    round(game_days * @seconds_per_real_day / @game_days_per_real_day)
  end

  def real_seconds_to_game_days(real_seconds)
      when is_integer(real_seconds) and real_seconds >= 0 do
    real_seconds * @game_days_per_real_day / @seconds_per_real_day
  end

  def arrival_at(%DateTime{} = started_at, game_days)
      when is_integer(game_days) and game_days >= 0 do
    DateTime.add(started_at, game_days_to_real_seconds(game_days), :second)
  end
end
