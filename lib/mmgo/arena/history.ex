defmodule MMGO.Arena.History do
  @moduledoc """
  What already happened, read back.

  Nothing here records anything new. Every turn of every fight is already
  persisted — `MMGO.Combat.Turn` keeps its own resolution and narration, the
  events keep their payloads, and the combat keeps the seed that produced them —
  so a replay is a reader over that record rather than a re-simulation. What a
  player sees is exactly what the engine did, because it is the same rows.

  History is not kept forever. A finished fight is a memory with a lifetime;
  `prune/2` is what enforces it.
  """

  import Ecto.Query, warn: false

  alias MMGO.Arena.{Ladder, Match, MatchMember, Profile}
  alias MMGO.Combat.{Combat, Event, Turn}
  alias MMGO.Repo

  # How long a finished fight stays readable before it is forgotten.
  @retention_days 30

  def retention_days, do: @retention_days

  @doc """
  The profile's finished fights, most recent first.

  Each entry carries what the match did to this profile — the outcome and the
  rating it moved — and who was on the other side of it.
  """
  def list_for_profile(%Profile{id: profile_id}, limit \\ 20) do
    MatchMember
    |> where([member], member.profile_id == ^profile_id)
    |> join(:inner, [member], match in Match, on: match.id == member.match_id)
    |> where([_member, match], match.status == :finished)
    |> order_by([_member, match], desc: match.finished_at, desc: match.id)
    |> limit(^min(limit, 100))
    |> select([member, match], %{member: member, match: match})
    |> Repo.all()
    |> Enum.map(&entry/1)
  end

  @doc """
  What one finished match did to one profile.

  This is the material for the moment after a fight: what the rating did, what
  the season made of it, and whether the ladder moved underneath them. Returns
  nil when the profile did not play that match, or it has not settled yet.
  """
  def settlement(%Profile{id: profile_id}, match_id) when is_binary(match_id) do
    MatchMember
    |> where([member], member.profile_id == ^profile_id and member.match_id == ^match_id)
    |> join(:inner, [member], match in Match, on: match.id == member.match_id)
    |> where([_member, match], match.status == :finished)
    |> select([member, match], %{member: member, match: match})
    |> Repo.one()
    |> case do
      nil ->
        nil

      %{member: member, match: match} = row ->
        row
        |> entry()
        |> Map.merge(%{
          division_before: member.division_before,
          division_after: member.division_after,
          season_xp_gained: member.season_xp_gained,
          promoted?: promoted?(member),
          demoted?: demoted?(member),
          mode: match.mode
        })
    end
  end

  def settlement(_profile, _match_id), do: nil

  defp promoted?(%MatchMember{division_before: before, division_after: later})
       when not is_nil(before) and not is_nil(later),
       do: Ladder.ordinal(later) > Ladder.ordinal(before)

  defp promoted?(_member), do: false

  defp demoted?(%MatchMember{division_before: before, division_after: later})
       when not is_nil(before) and not is_nil(later),
       do: Ladder.ordinal(later) < Ladder.ordinal(before)

  defp demoted?(_member), do: false

  @doc """
  One fight, turn by turn.

  Returns nil for a fight that has been forgotten or never existed.
  """
  def replay(combat_id) when is_binary(combat_id) do
    case Repo.get(Combat, combat_id) do
      nil ->
        nil

      combat ->
        combat = Repo.preload(combat, participants: [:character, :actor_template])

        %{
          combat: combat,
          seed: combat.seed,
          winner_side: combat.winner_side,
          finished_at: combat.finished_at,
          turns: replay_turns(combat.id)
        }
    end
  end

  def replay(_combat_id), do: nil

  @doc """
  Forgets fights finished longer ago than the retention window.

  Turns, actions and events are removed by the database along with their
  combat; the arena match rows are left alone, so the ladder's record of who
  played whom survives the loss of the blow-by-blow.
  """
  def prune(now \\ DateTime.utc_now(), retention_days \\ @retention_days) do
    cutoff = DateTime.add(now, -retention_days, :day)

    {count, _} =
      Combat
      |> where([combat], combat.kind == :arena_match)
      |> where([combat], combat.status == :finished)
      |> where([combat], combat.finished_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  defp entry(%{member: member, match: match}) do
    %{
      match_id: match.id,
      combat_id: match.combat_id,
      mode: match.mode,
      finished_at: match.finished_at,
      outcome: member.outcome || implied_outcome(member, match),
      rating_before: member.rating_before,
      rating_after: member.rating_after,
      rating_delta: rating_delta(member),
      opponents: opponent_names(match.id, member.team),
      replayable?: not is_nil(match.combat_id)
    }
  end

  # Matches settled before outcomes were recorded still have a winning team.
  defp implied_outcome(_member, %Match{winner_team: nil}), do: :draw
  defp implied_outcome(%MatchMember{team: team}, %Match{winner_team: team}), do: :win
  defp implied_outcome(_member, _match), do: :loss

  defp rating_delta(%MatchMember{rating_before: before, rating_after: later})
       when is_integer(before) and is_integer(later),
       do: later - before

  defp rating_delta(_member), do: nil

  defp opponent_names(match_id, team) do
    MatchMember
    |> where([member], member.match_id == ^match_id and member.team != ^team)
    |> join(:inner, [member], profile in Profile, on: profile.id == member.profile_id)
    |> join(:inner, [_member, profile], character in assoc(profile, :character))
    |> order_by([member], asc: member.position)
    |> select([_member, _profile, character], character.name)
    |> Repo.all()
  end

  defp replay_turns(combat_id) do
    events =
      Event
      |> where([event], event.combat_id == ^combat_id)
      |> order_by([event], asc: event.turn_number, asc: event.sequence)
      |> Repo.all()
      |> Enum.group_by(& &1.turn_number)

    Turn
    |> where([turn], turn.combat_id == ^combat_id and turn.status == :resolved)
    |> order_by([turn], asc: turn.number)
    |> Repo.all()
    |> Enum.map(fn turn ->
      %{
        number: turn.number,
        narration: turn.narration,
        resolution: turn.resolution || %{},
        events: Map.get(events, turn.number, [])
      }
    end)
  end
end
