defmodule MMGO.Arena.Seasons do
  @moduledoc """
  The ladder's clock.

  A season ends by writing down where everyone finished and then letting go of
  the numbers: ratings fall back toward the middle rather than to zero, so a
  climb still counts for something, and everyone plays placement matches in
  which the ladder moves faster because it knows less about them again.

  Both seats vacate with the season. A Champion holds their title for a season,
  not forever.
  """

  import Ecto.Query, warn: false

  alias MMGO.Arena.{Ladder, Profile, Season, SeasonAward, TitleSeat}
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  # How many matches the ladder treats as placements after a reset.
  @placement_matches 5
  # A reset pulls ratings this far back toward the starting rating: half way.
  @reset_pull 2
  @starting_rating 1_000

  # What finishing a season in each division is worth, in coins.
  @division_rewards %{
    initiate: 0,
    bronze: 50,
    silver: 120,
    gold: 250,
    platinum: 450,
    diamond: 700,
    archmage: 1_100,
    champion: 2_000
  }

  # Sitting a seat is worth more than the division that reached it.
  @seat_rewards %{champion: 1_500, deputy: 700}

  def placement_matches, do: @placement_matches
  def division_reward(division), do: Map.get(@division_rewards, division, 0)
  def seat_reward(seat), do: Map.get(@seat_rewards, seat, 0)

  @doc "The season being played, opening the first one if none has been."
  def current do
    case Repo.one(from(season in Season, where: season.status == :active)) do
      %Season{} = season -> season
      nil -> open_season(1)
    end
  end

  @doc "Every finished season, most recent first."
  def finished do
    Season
    |> where([season], season.status == :finished)
    |> order_by([season], desc: season.number)
    |> Repo.all()
  end

  @doc "Where a profile has finished the seasons it has played."
  def awards_for(%Profile{id: profile_id}) do
    SeasonAward
    |> where([award], award.profile_id == ^profile_id)
    |> join(:inner, [award], season in Season, on: season.id == award.season_id)
    |> order_by([_award, season], desc: season.number)
    |> preload([:season])
    |> Repo.all()
  end

  @doc """
  Ends the running season and opens the next.

  Everything happens in one transaction: the record is written, the seats are
  vacated, the ladder is pulled back toward the middle, and placements are
  handed out. Nobody plays half a reset.
  """
  def roll_over(now \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      season = current()
      profiles = Repo.all(from(profile in Profile, order_by: [desc: profile.rating]))
      seats = held_seats(season.number)

      Enum.each(profiles, fn profile ->
        award!(season, profile, Map.get(seats, profile.id), now)
        reset!(profile, season.number + 1)
      end)

      vacate_seats!(season.number, now)

      season
      |> Season.changeset(%{status: :finished, ended_at: now})
      |> Repo.update!()

      open_season(season.number + 1, now)
    end)
  end

  defp open_season(number, now \\ DateTime.utc_now()) do
    %Season{}
    |> Season.changeset(%{number: number, status: :active, started_at: now})
    |> Repo.insert!()
  end

  defp held_seats(season_number) do
    TitleSeat
    |> where([seat], seat.season == ^season_number and seat.status == :held)
    |> Repo.all()
    |> Map.new(&{&1.profile_id, &1.seat})
  end

  defp award!(season, profile, seat, now) do
    coins = pay_reward(profile, profile.division, seat)

    %SeasonAward{}
    |> SeasonAward.changeset(%{
      season_id: season.id,
      profile_id: profile.id,
      division: profile.division,
      rating: profile.rating,
      wins: profile.wins,
      losses: profile.losses,
      seat: seat,
      coins_awarded: coins,
      metadata: %{"awarded_at" => DateTime.to_iso8601(now)}
    })
    |> Repo.insert!()
  end

  # The record is the reward that always lands. Coins are paid on top when the
  # realm's treasury can afford them, and a realm that cannot does not block the
  # season from ending.
  defp pay_reward(profile, division, seat) do
    owed = division_reward(division) + seat_reward(seat)

    with true <- owed > 0,
         %Character{} = character <- Repo.get(Character, profile.character_id),
         %Realm{} = realm <- Repo.get(Realm, character.realm_id),
         {:ok, _transfer} <-
           Economy.grant_from_treasury(realm, character, owed, %{
             "reason" => "arena_season_reward"
           }) do
      owed
    else
      _unpaid -> 0
    end
  end

  # A reset that wiped everything would throw away the season's evidence; one
  # that changed nothing would make the season meaningless. Halfway back is the
  # compromise: a Champion starts the next season ahead, but not where they
  # stopped.
  defp reset!(profile, next_season) do
    rating = div(profile.rating + @starting_rating * (@reset_pull - 1), @reset_pull)

    profile
    |> Profile.changeset(%{
      season: next_season,
      rating: rating,
      division: Ladder.division_for_rating(rating),
      season_xp: 0,
      placements_remaining: @placement_matches
    })
    |> Repo.update!()
  end

  defp vacate_seats!(season_number, now) do
    TitleSeat
    |> where([seat], seat.season == ^season_number and seat.status in [:held, :offered])
    |> Repo.update_all(set: [status: :vacated, vacated_at: now, updated_at: now])
  end
end
