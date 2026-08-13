defmodule MMGO.Arena.QuestsTest do
  @moduledoc """
  Quests count what a player was going to do anyway, grant themselves, and reset
  by period rather than by anyone remembering to reset them.
  """

  use MMGO.DataCase, async: false

  alias MMGO.Accounts.Account
  alias MMGO.Arena
  alias MMGO.Arena.{Profile, Quests}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "quests-test", name: "Quests Realm", is_default: true})

    {:ok, _tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "Башня",
        kind: :tower,
        x: 0,
        y: 0,
        safe_zone: true
      })

    %{realm: realm, profile: profile_fixture("quests-mage")}
  end

  test "a fresh board is all zeroes", %{profile: profile} do
    board = Quests.board_for(profile)

    assert length(board) == length(Quests.definitions())
    assert Enum.all?(board, &(&1.progress == 0))
    refute Enum.any?(board, & &1.completed?)
  end

  test "a match counts toward the quests it belongs to", %{profile: profile} do
    %{profile: profile} = Quests.record_match(profile, :loss)

    board = Map.new(Quests.board_for(profile), &{&1.code, &1})

    assert board["daily_matches"].progress == 1
    # A loss is a match, and only a match.
    assert board["daily_win"].progress == 0
  end

  test "a quest grants itself the moment it is met", %{profile: profile} do
    assert %{completed: [], reward_xp: 0} = Quests.record_match(profile, :loss)

    profile = Arena.get_profile!(profile.id)
    assert %{completed: [quest], reward_xp: reward} = Quests.record_match(profile, :win)

    assert quest.code == "daily_win"
    assert reward == quest.reward_xp
    assert Arena.get_profile!(profile.id).season_xp >= reward
  end

  test "a completed quest is not completed twice", %{profile: profile} do
    %{profile: profile} = Quests.record_match(profile, :win)
    assert %{completed: completed} = Quests.record_match(profile, :win)

    refute Enum.any?(completed, &(&1.code == "daily_win"))
  end

  test "a new day is a new board", %{profile: profile} do
    today = DateTime.utc_now()
    tomorrow = DateTime.add(today, 1, :day)

    %{profile: profile} = Quests.record_match(profile, :win, today)
    assert Enum.any?(Quests.board_for(profile, DateTime.to_date(today)), & &1.completed?)

    tomorrow_board = Quests.board_for(profile, DateTime.to_date(tomorrow))
    daily = Enum.filter(tomorrow_board, &(&1.period == :daily))

    assert Enum.all?(daily, &(&1.progress == 0))
    # The weekly quest carries on across the day boundary.
    weekly = Enum.find(tomorrow_board, &(&1.code == "weekly_matches"))
    assert weekly.progress == 1
  end

  describe "streaks" do
    test "playing on consecutive days builds one", %{profile: profile} do
      day_one = ~U[2026-08-10 12:00:00.000000Z]

      profile = played_on(profile, day_one)
      assert profile.streak_days == 1

      profile = played_on(profile, DateTime.add(day_one, 1, :day))
      assert profile.streak_days == 2

      # A second match the same day changes nothing.
      profile = played_on(profile, DateTime.add(day_one, 1, :day))
      assert profile.streak_days == 2
    end

    test "a missed day starts it over", %{profile: profile} do
      day_one = ~U[2026-08-10 12:00:00.000000Z]

      profile = played_on(profile, day_one)
      profile = played_on(profile, DateTime.add(day_one, 3, :day))

      assert profile.streak_days == 1
    end

    test "the nightly sweep breaks the streak of someone who did not come back", %{
      profile: profile
    } do
      %{profile: profile} = Quests.record_match(profile, :win, ~U[2026-08-10 12:00:00.000000Z])
      assert profile.streak_days == 1

      # Two days later, still nothing from them.
      assert {:ok, %{streaks_broken: 1}} = Quests.sweep(~U[2026-08-12 00:05:00.000000Z])
      assert Arena.get_profile!(profile.id).streak_days == 0
    end

    test "the sweep leaves a streak that is still alive alone", %{profile: profile} do
      %{profile: profile} = Quests.record_match(profile, :win, ~U[2026-08-10 12:00:00.000000Z])

      assert {:ok, %{streaks_broken: 0}} = Quests.sweep(~U[2026-08-11 00:05:00.000000Z])
      assert Arena.get_profile!(profile.id).streak_days == 1
    end
  end

  defp played_on(%Profile{} = profile, at) do
    %{profile: profile} = Quests.record_match(profile, :win, at)
    profile
  end

  defp profile_fixture(handle) do
    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Quest #{handle}", handle: handle})
      |> Repo.insert()

    {:ok, profile} = Arena.create_profile(account, %{"schools" => ["fire", "water", "air"]})

    profile
  end
end
