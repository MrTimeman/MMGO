defmodule MMGO.Arena.Titles do
  @moduledoc """
  The two seats at the top of the ladder and the rules that move players
  between them.

  There is one Champion and one Deputy per season. The Deputy exists to defend
  the Champion and may never challenge them, so the only route to the Champion's
  seat is through the Deputy first. Winning that gauntlet takes the seat; losing
  it costs nothing but time.

  A Champion with no Deputy is frozen rather than protected: they cannot be
  challenged, but they cannot enter ranked play either, so refusing to appoint
  ends their season instead of preserving it.
  """

  import Ecto.Query, warn: false

  alias MMGO.Arena.{Ladder, Profile, TitleChallenge, TitleSeat}
  alias MMGO.Repo

  # How long a seat holder may be silent before the ladder treats them as away.
  @idle_after_days 7
  # An unanswered title challenge is claimed by the challenger after this long.
  @unanswered_challenge_days 7
  # How long the right to call out the Champion stands once it is earned.
  @gauntlet_right_days 3
  # How long a failed challenger waits before trying the gauntlet again.
  @failure_cooldown_days 3
  # The division a challenger must hold before the gauntlet opens to them.
  @eligible_division :archmage

  def idle_after_days, do: @idle_after_days
  def unanswered_challenge_days, do: @unanswered_challenge_days
  def gauntlet_right_days, do: @gauntlet_right_days
  def failure_cooldown_days, do: @failure_cooldown_days
  def eligible_division, do: @eligible_division

  @doc "True when the profile holds `seat` this season."
  def holds_seat?(profile, seat), do: holds_seat?(profile, seat, 1)

  def holds_seat?(%Profile{} = profile, seat, season) do
    case holder(seat, season) do
      %TitleSeat{profile_id: profile_id} when profile_id == profile.id -> true
      _other -> false
    end
  end

  def holds_seat?(_profile, _seat, _season), do: false

  @doc "The profile holding `seat` this season, or nil."
  def holder(seat, season \\ 1) when seat in [:champion, :deputy] do
    TitleSeat
    |> where([s], s.seat == ^seat and s.season == ^season and s.status == :held)
    |> preload(profile: :character)
    |> Repo.one()
  end

  @doc "The seat a profile holds this season, or nil."
  def seat_held_by(%Profile{id: profile_id}, season \\ 1) do
    TitleSeat
    |> where([s], s.profile_id == ^profile_id and s.season == ^season and s.status == :held)
    |> select([s], s.seat)
    |> Repo.one()
  end

  @doc """
  The mana pool a profile fights with.

  The seats sit above every ordinary division: the Champion holds the widest
  pool in the game and the Deputy the second widest. That gap is the mechanical
  reason to want the Champion's seat rather than the Deputy's.
  """
  def mana_pool_for(%Profile{} = profile, season \\ 1) do
    case seat_held_by(profile, season) do
      :champion -> Ladder.max_mana_for(:champion)
      :deputy -> Ladder.deputy_mana()
      _no_seat -> Ladder.max_mana_for(profile.division)
    end
  end

  @doc """
  Records that a seat holder is still here.

  Idleness is measured from the seat's own tenure, so something has to mark it
  when they play; without this a Champion would be treated as absent seven days
  after being crowned no matter how much they fought.
  """
  def touch_activity(%Profile{} = profile, season \\ 1, now \\ DateTime.utc_now()) do
    TitleSeat
    |> where([s], s.profile_id == ^profile.id and s.season == ^season and s.status == :held)
    |> Repo.all()
    |> Enum.each(fn seat ->
      seat
      |> TitleSeat.changeset(%{
        metadata: Map.put(seat.metadata || %{}, "last_active_at", DateTime.to_iso8601(now))
      })
      |> Repo.update!()
    end)

    :ok
  end

  @doc "The outstanding Deputy offer for this season, or nil."
  def pending_deputy_offer(season \\ 1) do
    TitleSeat
    |> where([s], s.seat == :deputy and s.season == ^season and s.status == :offered)
    |> preload([:profile, :appointed_by_profile])
    |> Repo.one()
  end

  @doc """
  True when the profile may be challenged for its seat.

  A Champion without a Deputy is unchallengeable — the cost of that shelter is
  that they are also barred from ranked play until they appoint one.
  """
  def challengeable?(seat, season \\ 1)

  def challengeable?(:deputy, season), do: not is_nil(holder(:deputy, season))

  def challengeable?(:champion, season) do
    not is_nil(holder(:champion, season)) and not is_nil(holder(:deputy, season))
  end

  @doc """
  Whether a profile may enter ranked play.

  Everyone may, except a sitting Champion who has left the Deputy seat empty.
  """
  def ranked_play_allowed?(%Profile{} = profile, season \\ 1) do
    case holder(:champion, season) do
      %TitleSeat{profile_id: champion_id} when champion_id == profile.id ->
        not is_nil(holder(:deputy, season))

      _not_the_champion ->
        true
    end
  end

  @doc "Whether the profile's division opens the gauntlet to them."
  def eligible_to_challenge?(%Profile{} = profile) do
    Ladder.at_least?(profile.division, @eligible_division)
  end

  @doc """
  Who effectively answers for the Champion's seat right now.

  While the Champion is away the Deputy acts in their place, which is what makes
  an absent Champion easier to depose rather than impossible to reach.
  """
  def acting_champion(season \\ 1, now \\ DateTime.utc_now()) do
    champion = holder(:champion, season)

    if is_nil(champion) or not idle?(champion, now) do
      champion
    else
      holder(:deputy, season) || champion
    end
  end

  @doc "True when a seat holder has been silent long enough to be treated as away."
  def idle?(%TitleSeat{} = seat, now \\ DateTime.utc_now()) do
    case last_seen(seat) do
      nil -> false
      seen -> DateTime.diff(now, seen, :day) >= @idle_after_days
    end
  end

  @doc "True when an unanswered challenge has stood long enough to be claimed."
  def claimable_by_default?(challenged_at, now \\ DateTime.utc_now())

  def claimable_by_default?(%DateTime{} = challenged_at, now) do
    DateTime.diff(now, challenged_at, :day) >= @unanswered_challenge_days
  end

  def claimable_by_default?(_challenged_at, _now), do: false

  @doc """
  Offers the Deputy seat to a profile.

  Only the sitting Champion may appoint, only one offer may stand at a time, and
  the appointee is free to refuse.
  """
  def appoint_deputy(%Profile{} = champion, %Profile{} = appointee, season \\ 1) do
    Repo.transaction(fn ->
      with :ok <- ensure_champion(champion, season),
           :ok <- ensure_seat_vacant(:deputy, season),
           :ok <- ensure_no_pending_offer(season),
           :ok <- ensure_not_self(champion, appointee),
           :ok <- ensure_different_account(champion, appointee) do
        %TitleSeat{}
        |> TitleSeat.changeset(%{
          seat: :deputy,
          season: season,
          status: :offered,
          profile_id: appointee.id,
          account_id: appointee.account_id,
          appointed_by_profile_id: champion.id,
          offered_at: DateTime.utc_now()
        })
        |> Repo.insert()
        |> case do
          {:ok, offer} -> offer
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Accepts an outstanding Deputy offer."
  def accept_deputy(%TitleSeat{seat: :deputy, status: :offered} = offer) do
    offer
    |> TitleSeat.changeset(%{status: :held, accepted_at: DateTime.utc_now()})
    |> Repo.update()
    |> widen_book_on_seat()
  end

  def accept_deputy(%TitleSeat{}), do: {:error, :not_a_pending_offer}

  @doc "Declines an outstanding Deputy offer, leaving the seat empty."
  def decline_deputy(%TitleSeat{seat: :deputy, status: :offered} = offer) do
    offer
    |> TitleSeat.changeset(%{status: :declined, vacated_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def decline_deputy(%TitleSeat{}), do: {:error, :not_a_pending_offer}

  @doc """
  Seats the top of the ladder on an empty throne.

  The Champion's rank is no longer a band anyone can climb into: the ladder
  stops at Archmage, and the highest-rated Archmage takes the empty seat rather
  than fighting their way into a room with nobody in it. Holding it is still
  earned — the gauntlet is how it is lost — and the new Champion appoints their
  own Deputy afterwards.

  Returns `{:ok, seat}` when someone was crowned, `:noop` when the seat is
  already held or nobody stands high enough yet.
  """
  def ensure_champion_seated(season \\ 1) do
    if holder(:champion, season) do
      :noop
    else
      case top_of_the_ladder() do
        nil -> :noop
        %Profile{} = claimant -> crown_champion(claimant, season)
      end
    end
  end

  # Rating breaks the tie, and an older profile breaks a tie in rating, so the
  # throne never depends on the order rows happen to come back in.
  defp top_of_the_ladder do
    Profile
    |> where([p], p.division == ^@eligible_division)
    |> order_by([p], desc: p.rating, asc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Crowns a challenger who has won the gauntlet.

  Both seats vacate: the deposed Champion falls back to the ladder, and the
  incoming Champion appoints a Deputy of their own choosing.
  """
  def crown_champion(%Profile{} = challenger, season \\ 1) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      vacate_seat(:champion, season, now)
      vacate_seat(:deputy, season, now)
      withdraw_pending_offer(season, now)

      %TitleSeat{}
      |> TitleSeat.changeset(%{
        seat: :champion,
        season: season,
        status: :held,
        profile_id: challenger.id,
        account_id: challenger.account_id,
        accepted_at: now
      })
      |> Repo.insert()
      |> case do
        {:ok, seat} -> seat
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> widen_book_on_seat()
  end

  # A seat carries the widest book in the game, and the shelf enforces the
  # number it stores rather than recomputing it, so taking a seat has to widen
  # the book then and there. Called fully qualified: `MMGO.Arena` already knows
  # this module, and this is the only direction the dependency runs back.
  defp widen_book_on_seat({:ok, %TitleSeat{profile_id: profile_id} = seat})
       when not is_nil(profile_id) do
    case MMGO.Arena.get_profile(profile_id) do
      nil ->
        {:ok, seat}

      profile ->
        MMGO.Arena.raise_grimoire_capacity(profile, MMGO.Arena.grimoire_capacity_for(profile))
        {:ok, seat}
    end
  end

  defp widen_book_on_seat(result), do: result

  @doc """
  Calls out the Deputy.

  The gauntlet starts here for everyone: the Deputy defends, and only beating
  them opens the way to the Champion. The Deputy themselves may never do this —
  they hold their seat by defending it, not by climbing.
  """
  def challenge_deputy(%Profile{} = challenger, season \\ 1, now \\ DateTime.utc_now()) do
    with {:ok, defender} <- seat_defender(:deputy, season),
         :ok <- ensure_may_challenge(challenger, defender, season, now) do
      open_challenge(:deputy, challenger, defender, season, now)
    end
  end

  @doc """
  Calls out the Champion.

  Only a challenger holding an unlapsed right earned against the Deputy may do
  this. An absent Champion is answered for by their Deputy, which is what makes
  staying away costly rather than safe.
  """
  def challenge_champion(%Profile{} = challenger, season \\ 1, now \\ DateTime.utc_now()) do
    with {:ok, defender} <- seat_defender(:champion, season),
         :ok <- ensure_may_challenge(challenger, defender, season, now),
         :ok <- ensure_gauntlet_right(challenger, season, now) do
      open_challenge(:champion, challenger, defender, season, now)
    end
  end

  @doc """
  A title challenge cannot be declined.

  It exists so that refusing one is an explicit, named outcome rather than a
  silent no-op: the only ways out are to fight it or to let it be claimed.
  """
  def decline_challenge(%TitleChallenge{}), do: {:error, :title_challenge_cannot_be_declined}

  @doc "The outstanding challenge on a seat this season, or nil."
  def open_challenge(seat, season \\ 1) when seat in [:champion, :deputy] do
    TitleChallenge
    |> where([c], c.seat == ^seat and c.season == ^season and c.status == :open)
    |> preload(challenger_profile: :character, defender_profile: :character)
    |> Repo.one()
  end

  @doc "The outstanding challenge this profile has made, or nil."
  def open_challenge_by(%Profile{id: profile_id}, season \\ 1) do
    TitleChallenge
    |> where([c], c.challenger_profile_id == ^profile_id and c.season == ^season)
    |> where([c], c.status == :open)
    |> preload([:challenger_profile, :defender_profile])
    |> Repo.one()
  end

  @doc "Records which match will settle a challenge."
  def attach_match(%TitleChallenge{} = challenge, match_id) when is_binary(match_id) do
    challenge
    |> TitleChallenge.changeset(%{arena_match_id: match_id})
    |> Repo.update()
  end

  @doc """
  Settles a fought challenge.

  Beating the Deputy earns the expiring right to call out the Champion; beating
  the Champion takes the seat, which vacates both and leaves the new Champion to
  appoint fresh. Losing costs nothing but the cooldown before trying again.
  """
  def settle(challenge, winner_profile_id, now \\ DateTime.utc_now())

  def settle(%TitleChallenge{status: :open} = challenge, winner_profile_id, now) do
    won? = winner_profile_id == challenge.challenger_profile_id

    Repo.transaction(fn ->
      challenge =
        challenge
        |> TitleChallenge.changeset(settled_attrs(challenge, won?, now))
        |> Repo.update()
        |> case do
          {:ok, settled} -> settled
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if won? and challenge.seat == :champion do
        case crown_champion(Repo.get!(Profile, challenge.challenger_profile_id), challenge.season) do
          {:ok, _seat} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end

      challenge
    end)
  end

  def settle(%TitleChallenge{}, _winner_profile_id, _now), do: {:error, :challenge_not_open}

  @doc """
  Claims a challenge the defender never answered.

  Seven days of silence is treated exactly as a defeat would be: the seat
  changes hands, or the right to the Champion is earned, without a fight.
  """
  def claim_unanswered(challenge, now \\ DateTime.utc_now())

  def claim_unanswered(%TitleChallenge{status: :open} = challenge, now) do
    if claimable_by_default?(challenge.challenged_at, now) do
      Repo.transaction(fn ->
        challenge =
          challenge
          |> TitleChallenge.changeset(
            challenge
            |> settled_attrs(true, now)
            |> Map.put(:status, :claimed)
          )
          |> Repo.update()
          |> case do
            {:ok, claimed} -> claimed
            {:error, changeset} -> Repo.rollback(changeset)
          end

        if challenge.seat == :champion do
          case crown_champion(
                 Repo.get!(Profile, challenge.challenger_profile_id),
                 challenge.season
               ) do
            {:ok, _seat} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end

        challenge
      end)
    else
      {:error, :challenge_still_answerable}
    end
  end

  def claim_unanswered(%TitleChallenge{}, _now), do: {:error, :challenge_not_open}

  @doc "Whether the profile currently holds an unlapsed right to call out the Champion."
  def gauntlet_right?(%Profile{id: profile_id}, season \\ 1, now \\ DateTime.utc_now()) do
    TitleChallenge
    |> where([c], c.challenger_profile_id == ^profile_id and c.season == ^season)
    |> where([c], c.seat == :deputy and c.status in [:won, :claimed])
    |> where([c], c.grants_until > ^now)
    |> Repo.exists?()
  end

  @doc "When a failed challenger may try the gauntlet again, or nil when they may now."
  def cooldown_until(%Profile{id: profile_id}, season \\ 1) do
    TitleChallenge
    |> where([c], c.challenger_profile_id == ^profile_id and c.season == ^season)
    |> where([c], c.status == :lost and not is_nil(c.resolved_at))
    |> order_by([c], desc: c.resolved_at)
    |> limit(1)
    |> select([c], c.resolved_at)
    |> Repo.one()
    |> case do
      nil -> nil
      resolved_at -> DateTime.add(resolved_at, @failure_cooldown_days, :day)
    end
  end

  defp settled_attrs(%TitleChallenge{seat: :deputy}, true, now) do
    %{
      status: :won,
      resolved_at: now,
      grants_until: DateTime.add(now, @gauntlet_right_days, :day)
    }
  end

  defp settled_attrs(%TitleChallenge{}, true, now), do: %{status: :won, resolved_at: now}
  defp settled_attrs(%TitleChallenge{}, false, now), do: %{status: :lost, resolved_at: now}

  defp open_challenge(seat, challenger, defender, season, now) do
    %TitleChallenge{}
    |> TitleChallenge.changeset(%{
      seat: seat,
      season: season,
      status: :open,
      challenger_profile_id: challenger.id,
      defender_profile_id: defender.id,
      challenged_at: now,
      expires_at: DateTime.add(now, @unanswered_challenge_days, :day)
    })
    |> Repo.insert()
  end

  defp seat_defender(seat, season) do
    cond do
      not challengeable?(seat, season) -> {:error, :seat_not_challengeable}
      true -> {:ok, acting_defender(seat, season)}
    end
  end

  # The Deputy answers for an absent Champion, so an idle seat holder is easier
  # to depose rather than unreachable.
  defp acting_defender(:champion, season), do: acting_champion(season).profile
  defp acting_defender(:deputy, season), do: holder(:deputy, season).profile

  defp ensure_may_challenge(challenger, defender, season, now) do
    cooldown = cooldown_until(challenger, season)

    cond do
      # The Deputy defends; they never climb. Their only route to the Champion's
      # seat is to give up the one they hold. This is checked before anything
      # else so the reason a Deputy is refused is the rule, not a coincidence of
      # who happens to be defending.
      seat_held_by(challenger, season) == :deputy ->
        {:error, :deputy_may_not_challenge}

      seat_held_by(challenger, season) == :champion ->
        {:error, :champion_may_not_challenge}

      challenger.id == defender.id ->
        {:error, :cannot_challenge_yourself}

      challenger.account_id == defender.account_id ->
        {:error, :cannot_challenge_your_own_account}

      not eligible_to_challenge?(challenger) ->
        {:error, :division_too_low}

      not is_nil(open_challenge_by(challenger, season)) ->
        {:error, :challenge_already_outstanding}

      not is_nil(cooldown) and DateTime.compare(now, cooldown) == :lt ->
        {:error, :challenge_cooldown}

      true ->
        :ok
    end
  end

  defp ensure_gauntlet_right(challenger, season, now) do
    if gauntlet_right?(challenger, season, now),
      do: :ok,
      else: {:error, :deputy_not_yet_beaten}
  end

  defp vacate_seat(seat, season, now) do
    TitleSeat
    |> where([s], s.seat == ^seat and s.season == ^season and s.status == :held)
    |> Repo.update_all(set: [status: :vacated, vacated_at: now, updated_at: now])
  end

  defp withdraw_pending_offer(season, now) do
    TitleSeat
    |> where([s], s.seat == :deputy and s.season == ^season and s.status == :offered)
    |> Repo.update_all(set: [status: :declined, vacated_at: now, updated_at: now])
  end

  defp ensure_champion(%Profile{id: profile_id}, season) do
    case holder(:champion, season) do
      %TitleSeat{profile_id: ^profile_id} -> :ok
      _other -> {:error, :not_the_champion}
    end
  end

  defp ensure_seat_vacant(seat, season) do
    if holder(seat, season), do: {:error, :seat_already_held}, else: :ok
  end

  defp ensure_no_pending_offer(season) do
    if pending_deputy_offer(season), do: {:error, :offer_already_pending}, else: :ok
  end

  defp ensure_not_self(%Profile{id: id}, %Profile{id: id}), do: {:error, :cannot_appoint_yourself}
  defp ensure_not_self(_champion, _appointee), do: :ok

  # Arena players may keep several profiles, so the same person must not be able
  # to hold both seats through a second character.
  defp ensure_different_account(%Profile{account_id: account_id}, %Profile{
         account_id: account_id
       }),
       do: {:error, :cannot_appoint_your_own_account}

  defp ensure_different_account(_champion, _appointee), do: :ok

  # A seat records activity on its own row so a holder's silence is measured
  # from their tenure rather than from unrelated world play.
  defp last_seen(%TitleSeat{metadata: metadata, accepted_at: accepted_at}) do
    with raw when is_binary(raw) <- is_map(metadata) && Map.get(metadata, "last_active_at"),
         {:ok, parsed, _offset} <- DateTime.from_iso8601(raw) do
      parsed
    else
      _absent_or_invalid -> accepted_at
    end
  end
end
