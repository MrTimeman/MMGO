defmodule MMGO.Arena.SeasonsTest do
  @moduledoc """
  A season ends by writing down where everyone finished and then letting go of
  the numbers.
  """

  use MMGO.DataCase, async: false

  alias MMGO.Accounts.Account
  alias MMGO.Arena
  alias MMGO.Arena.{Ladder, Seasons, Titles}
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "seasons-test", name: "Seasons Realm", is_default: true})

    {:ok, _tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "Башня",
        kind: :tower,
        x: 0,
        y: 0,
        safe_zone: true
      })

    %{realm: realm}
  end

  test "the first season opens on its own" do
    season = Seasons.current()

    assert season.number == 1
    assert season.status == :active
    # And asking again does not open a second one.
    assert Seasons.current().id == season.id
  end

  test "ending a season records where everyone finished", context do
    champion = profile_fixture(context, "season-champ", rating: 2_600, division: :champion)
    ordinary = profile_fixture(context, "season-ordinary", rating: 1_450, division: :gold)

    {:ok, _seat} = Titles.crown_champion(champion)

    assert {:ok, next} = Seasons.roll_over()
    assert next.number == 2
    assert next.status == :active

    assert [%{division: :champion, seat: :champion, rating: 2_600}] = Seasons.awards_for(champion)
    assert [%{division: :gold, seat: nil, rating: 1_450}] = Seasons.awards_for(ordinary)

    # The record outlives the reset that follows it.
    assert Arena.get_profile!(champion.id).rating < 2_600
  end

  test "a reset pulls the ladder halfway back, not to nothing", context do
    climber = profile_fixture(context, "season-climber", rating: 2_600, division: :champion)
    novice = profile_fixture(context, "season-novice", rating: 800, division: :initiate)

    {:ok, _next} = Seasons.roll_over()

    climber = Arena.get_profile!(climber.id)
    novice = Arena.get_profile!(novice.id)

    assert climber.rating == 1_800
    assert novice.rating == 900

    # A climb still counts for something next season.
    assert climber.rating > novice.rating
    assert climber.division == Ladder.division_for_rating(1_800)
    assert climber.season == 2
    assert climber.season_xp == 0
  end

  test "everyone plays placements after a reset, and they move the ladder harder", context do
    profile = profile_fixture(context, "season-placed", rating: 1_000, division: :bronze)

    {:ok, _next} = Seasons.roll_over()
    profile = Arena.get_profile!(profile.id)

    assert profile.placements_remaining == Seasons.placement_matches()

    placement = Ladder.settle(1_000, :bronze, 0.5, 1.0, placement?: true)
    ordinary = Ladder.settle(1_000, :bronze, 0.5, 1.0)

    assert placement.rating - 1_000 == (ordinary.rating - 1_000) * 2
  end

  test "the seats do not survive the season", context do
    champion = profile_fixture(context, "season-seat-champ", rating: 2_600, division: :champion)
    deputy = profile_fixture(context, "season-seat-deputy", rating: 2_400, division: :archmage)

    {:ok, _seat} = Titles.crown_champion(champion)
    {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    {:ok, _held} = Titles.accept_deputy(offer)

    {:ok, _next} = Seasons.roll_over()

    assert Titles.holder(:champion, 1) == nil
    assert Titles.holder(:deputy, 1) == nil
  end

  test "a funded realm pays the season's coins", context do
    {:ok, _treasury} = Economy.ensure_treasury_account(context.realm, 100_000)

    profile = profile_fixture(context, "season-paid", rating: 1_450, division: :gold)

    {:ok, _next} = Seasons.roll_over()

    assert [award] = Seasons.awards_for(profile)
    assert award.coins_awarded == Seasons.division_reward(:gold)
  end

  test "an unfunded realm still ends its season", context do
    profile = profile_fixture(context, "season-unpaid", rating: 1_450, division: :gold)

    assert {:ok, _next} = Seasons.roll_over()

    assert [award] = Seasons.awards_for(profile)
    assert award.coins_awarded == 0
    assert award.division == :gold
  end

  defp profile_fixture(_context, handle, standing) do
    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Season #{handle}", handle: handle})
      |> Repo.insert()

    {:ok, profile} =
      Arena.create_profile(account, %{"schools" => ["fire", "water", "air"]})

    profile
    |> Ecto.Changeset.change(Map.new(standing))
    |> Repo.update!()
  end
end
