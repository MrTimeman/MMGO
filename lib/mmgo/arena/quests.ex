defmodule MMGO.Arena.Quests do
  @moduledoc """
  Small standing reasons to come back.

  Quests are deliberately about things a player was going to do anyway — fight,
  and win — rather than errands that pull them away from the arena. They are
  counted from what a settled match already knows, granted the moment they are
  met, and never need claiming: a reward that waits behind a button is a chore.

  A day streak sits alongside them. It is the only engagement state that has to
  survive between sessions, so it lives on the profile.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Arena.{Profile, QuestProgress}
  alias MMGO.Notifications
  alias MMGO.Repo

  @definitions [
    %{
      code: "daily_matches",
      period: :daily,
      goal: 3,
      counts: :match,
      reward_xp: 60,
      name: "Три круга",
      description: "Проведите три боя за день."
    },
    %{
      code: "daily_win",
      period: :daily,
      goal: 1,
      counts: :win,
      reward_xp: 40,
      name: "Первая победа",
      description: "Выиграйте бой сегодня."
    },
    %{
      code: "weekly_matches",
      period: :weekly,
      goal: 12,
      counts: :match,
      reward_xp: 180,
      name: "Дюжина кругов",
      description: "Проведите двенадцать боёв за неделю."
    },
    %{
      code: "weekly_wins",
      period: :weekly,
      goal: 5,
      counts: :win,
      reward_xp: 220,
      name: "Пять побед",
      description: "Выиграйте пять боёв за неделю."
    }
  ]

  # How long a finished period's rows are worth keeping around.
  @progress_retention_days 21

  def definitions, do: @definitions
  def progress_retention_days, do: @progress_retention_days

  @doc "The quest board as it stands for a profile right now."
  def board_for(%Profile{} = profile, today \\ Date.utc_today()) do
    rows =
      QuestProgress
      |> where([row], row.profile_id == ^profile.id)
      |> where([row], row.period_key in ^Enum.map(@definitions, &period_key(&1.period, today)))
      |> Repo.all()
      |> Map.new(&{&1.code, &1})

    Enum.map(@definitions, fn definition ->
      row = Map.get(rows, definition.code)

      %{
        code: definition.code,
        name: definition.name,
        description: definition.description,
        period: definition.period,
        goal: definition.goal,
        reward_xp: definition.reward_xp,
        progress: (row && row.progress) || 0,
        completed?: not is_nil(row && row.completed_at)
      }
    end)
  end

  @doc """
  Counts one settled match toward the profile's quests and its day streak.

  Returns the quests that were completed by this match, so the caller can make a
  moment of them.
  """
  def record_match(%Profile{} = profile, outcome, now \\ DateTime.utc_now()) do
    today = DateTime.to_date(now)

    completed =
      @definitions
      |> Enum.filter(&counts?(&1, outcome))
      |> Enum.map(&advance(profile, &1, today, now))
      |> Enum.filter(& &1)

    profile = touch_streak(profile, today)
    reward = Enum.sum(Enum.map(completed, & &1.reward_xp))

    profile =
      if reward > 0 do
        profile
        |> Profile.changeset(%{season_xp: profile.season_xp + reward})
        |> Repo.update!()
      else
        profile
      end

    Enum.each(completed, &announce(profile, &1))

    %{profile: profile, completed: completed, reward_xp: reward}
  end

  @doc "The key naming the period a date belongs to."
  def period_key(:daily, %Date{} = date), do: Date.to_iso8601(date)

  def period_key(:weekly, %Date{} = date) do
    {year, week} = :calendar.iso_week_number(Date.to_erl(date))

    "#{year}-W#{String.pad_leading(to_string(week), 2, "0")}"
  end

  @doc """
  Forgets progress rows from periods nobody will ask about again, and breaks the
  streaks of players who did not come back.

  The streak is what genuinely needs a job: nothing else runs on behalf of
  someone who is not here, and a streak that only breaks when they return would
  greet them with a lie.
  """
  def sweep(now \\ DateTime.utc_now()) do
    today = DateTime.to_date(now)
    cutoff = Date.add(today, -@progress_retention_days)

    {pruned, _} =
      QuestProgress
      |> where([row], row.inserted_at < ^DateTime.new!(cutoff, ~T[00:00:00.000000]))
      |> Repo.delete_all()

    {broken, _} =
      Profile
      |> where([profile], profile.streak_days > 0)
      |> where(
        [profile],
        is_nil(profile.last_played_on) or profile.last_played_on < ^Date.add(today, -1)
      )
      |> Repo.update_all(set: [streak_days: 0, updated_at: DateTime.utc_now()])

    {:ok, %{pruned: pruned, streaks_broken: broken}}
  end

  defp counts?(%{counts: :match}, _outcome), do: true
  defp counts?(%{counts: :win}, outcome), do: outcome == :win
  defp counts?(_definition, _outcome), do: false

  # Returns the definition when this match is what completed it, and nil
  # otherwise, so a quest is only ever announced once.
  defp advance(profile, definition, today, now) do
    key = period_key(definition.period, today)

    row =
      case Repo.get_by(QuestProgress,
             profile_id: profile.id,
             code: definition.code,
             period_key: key
           ) do
        %QuestProgress{} = existing ->
          existing

        nil ->
          %QuestProgress{}
          |> QuestProgress.changeset(%{
            profile_id: profile.id,
            code: definition.code,
            period: definition.period,
            period_key: key,
            progress: 0,
            goal: definition.goal
          })
          |> Repo.insert!()
      end

    if row.completed_at do
      nil
    else
      progress = row.progress + 1
      completed? = progress >= definition.goal

      row
      |> QuestProgress.changeset(%{
        progress: progress,
        completed_at: if(completed?, do: now)
      })
      |> Repo.update!()

      if completed?, do: definition
    end
  end

  # A streak counts days played, not days visited: yesterday continues it, a
  # gap starts it over, and a second match today changes nothing.
  defp touch_streak(%Profile{last_played_on: today} = profile, today), do: profile

  defp touch_streak(%Profile{} = profile, today) do
    streak =
      case profile.last_played_on do
        nil -> 1
        last -> if Date.diff(today, last) == 1, do: (profile.streak_days || 0) + 1, else: 1
      end

    profile
    |> Profile.changeset(%{streak_days: streak, last_played_on: today})
    |> Repo.update!()
  end

  defp announce(%Profile{character_id: character_id}, definition) when is_binary(character_id) do
    case Repo.get(Character, character_id) do
      %Character{} = character ->
        Notifications.notify_arena_quest_completed(character, definition)

      nil ->
        :ok
    end
  end

  defp announce(_profile, _definition), do: :ok
end
