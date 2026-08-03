defmodule MMGO.Travel.Clock do
  @seconds_per_real_day 86_400
  @game_days_per_real_day 364
  @game_hours_per_day 24
  @game_days_per_year 364
  @days_per_month 28
  @world_epoch ~U[2026-01-01 00:00:00Z]
  @world_year 847

  @months [
    {"Месяц Семян", :spring, "Весна", "❀"},
    {"Месяц Трав", :spring, "Весна", "❀"},
    {"Месяц Цветения", :spring, "Весна", "❀"},
    {"Месяц Ливней", :summer, "Лето", "☀"},
    {"Месяц Долгих Дней", :summer, "Лето", "☀"},
    {"Месяц Зноя", :summer, "Лето", "☀"},
    {"Месяц Жатвы", :autumn, "Осень", "❧"},
    {"Месяц Листопада", :autumn, "Осень", "❧"},
    {"Месяц Туманов", :autumn, "Осень", "❧"},
    {"Месяц Первых Морозов", :winter, "Зима", "❄"},
    {"Месяц Долгой Ночи", :winter, "Зима", "❄"},
    {"Месяц Стужи", :winter, "Зима", "❄"},
    {"Месяц Талых Вод", :winter, "Зима", "❄"}
  ]

  def game_days_to_real_seconds(game_days) when is_integer(game_days) and game_days >= 0 do
    round(game_days * @seconds_per_real_day / @game_days_per_real_day)
  end

  @doc "Converts whole game hours to their compressed real-time duration."
  def game_hours_to_real_seconds(game_hours)
      when is_integer(game_hours) and game_hours >= 0 do
    round(game_hours * @seconds_per_real_day / (@game_days_per_real_day * @game_hours_per_day))
  end

  def real_seconds_to_game_days(real_seconds)
      when is_integer(real_seconds) and real_seconds >= 0 do
    real_seconds * @game_days_per_real_day / @seconds_per_real_day
  end

  def arrival_at(%DateTime{} = started_at, game_days)
      when is_integer(game_days) and game_days >= 0 do
    DateTime.add(started_at, game_days_to_real_seconds(game_days), :second)
  end

  @doc """
  Projects server time onto the canonical MMGO calendar: thirteen months of
  twenty-eight days, with one compressed 364-day year per real day.

  Tests may pass an explicit `:epoch` and `:year` without changing global
  runtime configuration.
  """
  def world_time(now \\ DateTime.utc_now(), opts \\ [])

  def world_time(%DateTime{} = now, opts) when is_list(opts) do
    epoch = Keyword.get(opts, :epoch, @world_epoch)
    base_year = Keyword.get(opts, :year, @world_year)
    elapsed_seconds = max(DateTime.diff(now, epoch, :second), 0)
    elapsed_game_days = div(elapsed_seconds * @game_days_per_real_day, @seconds_per_real_day)
    year_offset = div(elapsed_game_days, @game_days_per_year)
    day_of_year_index = rem(elapsed_game_days, @game_days_per_year)
    month_index = div(day_of_year_index, @days_per_month)
    day = rem(day_of_year_index, @days_per_month) + 1
    {month_name, season, season_name, season_glyph} = Enum.at(@months, month_index)

    %{
      year: base_year + year_offset,
      elapsed_game_days: elapsed_game_days,
      day_of_year: day_of_year_index + 1,
      month_index: month_index,
      month_number: month_index + 1,
      month_name: month_name,
      day: day,
      season: season,
      season_name: season_name,
      season_glyph: season_glyph
    }
  end
end
