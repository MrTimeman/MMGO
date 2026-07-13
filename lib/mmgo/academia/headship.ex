defmodule MMGO.Academia.Headship do
  @moduledoc """
  Durable, professor-governed Academy Head elections.

  The academy is realm-wide public infrastructure rather than a player-created
  organization. Its small constitution therefore lives under one namespaced
  block in `realms.metadata`, and every mutation locks that realm row before
  taking a snapshot of the active player professor roster.

  Elections are deliberately on-demand: no background scheduler is claimed or
  required for correctness. A term lasts ten real days; when it expires an
  eligible professor opens the next one-day plurality election. If every
  snapshotted voter participates, it resolves immediately; otherwise an
  eligible professor may settle it after the deadline. A tie or no turnout
  keeps the incumbent (or leaves the office vacant), rather than inventing a
  winner.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academia.Professor
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  @metadata_key "academy_headship"
  @version 1
  @term_days 10
  @election_window_hours 24

  @doc "Returns a presentation-safe Academy Head state for one realm."
  def state(realm_or_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    actor_id = Keyword.get(opts, :actor_id)

    with %Realm{} = realm <- get_realm(realm_or_id) do
      professors = list_active_player_professors(realm.id)
      {:ok, presentation_state(realm, professors, actor_id, now)}
    else
      nil -> {:error, :academy_headship_unavailable}
    end
  end

  @doc "Opens the next election when the current ten-day term is absent or has expired."
  def open_election(actor, opts \\ [])

  def open_election(%Character{} = actor, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    election_window_hours = Keyword.get(opts, :election_window_hours, @election_window_hours)

    if not valid_election_window?(election_window_hours) do
      {:error, headship_changeset("academy head election window is invalid")}
    else
      Repo.transaction(fn ->
        realm = lock_realm!(actor.realm_id)
        professors = lock_active_player_professors!(realm.id)
        headship = headship_metadata(realm)

        cond do
          not active_professor?(professors, actor.id) ->
            Repo.rollback(
              headship_changeset("only an active professor may open an Academy Head election")
            )

          open_election?(headship) ->
            Repo.rollback(headship_changeset("an Academy Head election is already open"))

          active_term?(headship, now) ->
            Repo.rollback(headship_changeset("the current Academy Head term is still active"))

          professors == [] ->
            Repo.rollback(headship_changeset("the realm has no active player professors"))

          true ->
            election = new_election(professors, now, election_window_hours)
            updated_realm = update_headship!(realm, Map.put(headship, "election", election))

            %{realm: updated_realm, election: election_summary(election, professors, actor.id)}
        end
      end)
      |> normalize_transaction_result()
    end
  end

  def open_election(_actor, _opts),
    do: {:error, headship_changeset("academy head election is unavailable")}

  @doc "Records one professor's immutable vote for a candidate from the snapshotted roster."
  def cast_vote(voter, candidate_character_id, opts \\ [])

  def cast_vote(%Character{} = voter, candidate_character_id, opts)
      when is_binary(candidate_character_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(voter.realm_id)
      professors = lock_active_player_professors!(realm.id)
      headship = headship_metadata(realm)
      election = current_open_election(headship)

      cond do
        is_nil(election) ->
          Repo.rollback(headship_changeset("an Academy Head election is not open"))

        election_expired?(election, now) ->
          Repo.rollback(
            headship_changeset("this Academy Head election must be settled before voting")
          )

        not active_professor?(professors, voter.id) ->
          Repo.rollback(headship_changeset("only an active professor may vote for Academy Head"))

        voter.id not in election_voter_ids(election) ->
          Repo.rollback(headship_changeset("voter was not in the Academy Head election snapshot"))

        candidate_character_id not in election_candidate_ids(election) ->
          Repo.rollback(
            headship_changeset("candidate was not in the Academy Head election snapshot")
          )

        not active_professor?(professors, candidate_character_id) ->
          Repo.rollback(
            headship_changeset("Academy Head candidate is no longer an active professor")
          )

        Map.has_key?(election_votes(election), voter.id) ->
          Repo.rollback(headship_changeset("professor has already voted for Academy Head"))

        true ->
          election = put_vote(election, voter.id, candidate_character_id)

          if every_voter_has_voted?(election) do
            resolve_election!(realm, headship, election, professors, voter.id, now)
          else
            updated_realm =
              update_headship!(realm, Map.put(headship, "election", election))

            %{
              realm: updated_realm,
              election: election_summary(election, professors, voter.id),
              resolution: :pending
            }
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def cast_vote(_voter, _candidate_character_id, _opts),
    do: {:error, headship_changeset("Academy Head vote is unavailable")}

  @doc "Settles an open election only after its server-owned closing time."
  def settle_election(actor, opts \\ [])

  def settle_election(%Character{} = actor, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(actor.realm_id)
      professors = lock_active_player_professors!(realm.id)
      headship = headship_metadata(realm)
      election = current_open_election(headship)

      cond do
        not active_professor?(professors, actor.id) ->
          Repo.rollback(
            headship_changeset("only an active professor may settle an Academy Head election")
          )

        is_nil(election) ->
          Repo.rollback(headship_changeset("an Academy Head election is not open"))

        not election_expired?(election, now) ->
          Repo.rollback(headship_changeset("Academy Head election is still open for voting"))

        true ->
          resolve_election!(realm, headship, election, professors, actor.id, now)
      end
    end)
    |> normalize_transaction_result()
  end

  def settle_election(_actor, _opts),
    do: {:error, headship_changeset("Academy Head election settlement is unavailable")}

  @doc "Vacates an active term when its current Head retires from the professor roster."
  def vacate_for_retirement(retiring_professor, opts \\ [])

  def vacate_for_retirement(%Character{} = retiring_professor, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(retiring_professor.realm_id)
      headship = headship_metadata(realm)

      if Map.get(headship, "head_character_id") == retiring_professor.id do
        updated_headship =
          headship
          |> Map.put("head_character_id", nil)
          |> Map.put("term_ends_at", DateTime.to_iso8601(now))
          |> Map.put("vacated_at", DateTime.to_iso8601(now))
          |> Map.put("vacated_by_character_id", retiring_professor.id)
          |> Map.put("vacated_reason", "professor_retired")

        %{realm: update_headship!(realm, updated_headship), vacated?: true}
      else
        %{realm: realm, vacated?: false}
      end
    end)
    |> normalize_transaction_result()
  end

  def vacate_for_retirement(_retiring_professor, _opts),
    do: {:error, headship_changeset("Academy Head retirement is unavailable")}

  @doc "Checks whether the given character currently holds an unexpired Academy Head term."
  def current_head?(character, opts \\ [])

  def current_head?(%Character{} = character, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case state(character.realm_id, now: now, actor_id: character.id) do
      {:ok, %{head: %{character_id: character_id}, term_active?: true}} ->
        character_id == character.id

      _other ->
        false
    end
  end

  def current_head?(_character, _opts), do: false

  defp resolve_election!(realm, headship, election, professors, actor_id, now) do
    {resolution, winner_character_id} = plurality_result(election)

    completed_election =
      election
      |> Map.put("status", Atom.to_string(resolution))
      |> Map.put("resolved_at", DateTime.to_iso8601(now))
      |> Map.put("winner_character_id", winner_character_id)

    updated_headship =
      headship
      |> Map.delete("election")
      |> Map.put("last_election", completed_election)
      |> apply_resolution(resolution, winner_character_id, now)

    updated_realm = update_headship!(realm, updated_headship)

    %{
      realm: updated_realm,
      election: election_summary(completed_election, professors, actor_id),
      resolution: resolution,
      head_character_id: winner_character_id
    }
  end

  defp apply_resolution(headship, :elected, winner_character_id, now)
       when is_binary(winner_character_id) do
    headship
    |> Map.put("head_character_id", winner_character_id)
    |> Map.put("term_started_at", DateTime.to_iso8601(now))
    |> Map.put(
      "term_ends_at",
      DateTime.to_iso8601(DateTime.add(now, @term_days * 86_400, :second))
    )
  end

  defp apply_resolution(headship, _resolution, _winner_character_id, _now), do: headship

  defp presentation_state(realm, professors, actor_id, now) do
    headship = headship_metadata(realm)
    head_character_id = Map.get(headship, "head_character_id")
    election = current_open_election(headship)
    term_ends_at = parse_datetime(Map.get(headship, "term_ends_at"))
    actor_is_professor? = active_professor?(professors, actor_id)
    head = Enum.find(professors, &(&1.character_id == head_character_id))
    term_active? = not is_nil(head) and active_term?(headship, now)

    last_result =
      case Map.get(headship, "last_election") do
        election when is_map(election) -> Map.get(election, "status")
        _other -> nil
      end

    %{
      realm: realm,
      head: head,
      term_ends_at: term_ends_at,
      term_active?: term_active?,
      eligible_professors: professors,
      actor_is_professor?: actor_is_professor?,
      can_open_election?: actor_is_professor? and is_nil(election) and not term_active?,
      can_settle_election?:
        actor_is_professor? and not is_nil(election) and election_expired?(election, now),
      open_election: election_summary(election, professors, actor_id),
      last_result: last_result
    }
  end

  defp new_election(professors, now, election_window_hours) do
    professor_ids = Enum.map(professors, & &1.character_id)

    %{
      "id" => Ecto.UUID.generate(),
      "status" => "open",
      "opened_at" => DateTime.to_iso8601(now),
      "closes_at" =>
        now
        |> DateTime.add(election_window_hours * 3_600, :second)
        |> DateTime.to_iso8601(),
      "voter_character_ids" => professor_ids,
      "candidate_character_ids" => professor_ids,
      "votes" => %{}
    }
  end

  defp election_summary(nil, _professors, _actor_id), do: nil

  defp election_summary(election, professors, actor_id) when is_map(election) do
    votes = election_votes(election)
    candidate_ids = election_candidate_ids(election)

    %{
      id: Map.get(election, "id"),
      status: Map.get(election, "status"),
      closes_at: parse_datetime(Map.get(election, "closes_at")),
      voter_count: length(election_voter_ids(election)),
      votes_cast: map_size(votes),
      candidates:
        Enum.filter(professors, &(&1.character_id in candidate_ids))
        |> Enum.map(fn professor ->
          %{
            professor: professor,
            votes:
              Enum.count(votes, fn {_voter_id, candidate_id} ->
                candidate_id == professor.character_id
              end)
          }
        end),
      can_vote?:
        is_binary(actor_id) and actor_id in election_voter_ids(election) and
          not Map.has_key?(votes, actor_id)
    }
  end

  defp plurality_result(election) do
    votes = election_votes(election)
    candidate_ids = election_candidate_ids(election)

    counts = Map.new(candidate_ids, &{&1, 0})

    counts =
      Enum.reduce(votes, counts, fn {_voter_id, candidate_id}, counts ->
        if Map.has_key?(counts, candidate_id),
          do: Map.update!(counts, candidate_id, &(&1 + 1)),
          else: counts
      end)

    max_votes = counts |> Map.values() |> Enum.max(fn -> 0 end)

    winners =
      counts
      |> Enum.filter(fn {_candidate_id, votes} -> votes == max_votes and votes > 0 end)
      |> Enum.map(&elem(&1, 0))

    case winners do
      [] -> {:no_turnout, nil}
      [winner_character_id] -> {:elected, winner_character_id}
      _tied -> {:tied, nil}
    end
  end

  defp put_vote(election, voter_id, candidate_character_id) do
    Map.put(
      election,
      "votes",
      Map.put(election_votes(election), voter_id, candidate_character_id)
    )
  end

  defp every_voter_has_voted?(election) do
    voter_ids = election_voter_ids(election)
    votes = election_votes(election)
    voter_ids != [] and Enum.all?(voter_ids, &Map.has_key?(votes, &1))
  end

  defp current_open_election(headship) do
    case Map.get(headship, "election") do
      %{"status" => "open"} = election -> election
      _other -> nil
    end
  end

  defp open_election?(headship), do: not is_nil(current_open_election(headship))

  defp election_expired?(election, now) do
    case parse_datetime(Map.get(election, "closes_at")) do
      %DateTime{} = closes_at -> DateTime.compare(now, closes_at) != :lt
      nil -> true
    end
  end

  defp active_term?(headship, now) do
    case {Map.get(headship, "head_character_id"),
          parse_datetime(Map.get(headship, "term_ends_at"))} do
      {character_id, %DateTime{} = term_ends_at} when is_binary(character_id) ->
        DateTime.compare(now, term_ends_at) == :lt

      _other ->
        false
    end
  end

  defp election_voter_ids(election),
    do: valid_character_ids(Map.get(election, "voter_character_ids"))

  defp election_candidate_ids(election),
    do: valid_character_ids(Map.get(election, "candidate_character_ids"))

  defp valid_character_ids(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp valid_character_ids(_ids), do: []

  defp election_votes(%{"votes" => votes}) when is_map(votes) do
    Enum.reduce(votes, %{}, fn
      {voter_id, candidate_id}, normalized when is_binary(voter_id) and is_binary(candidate_id) ->
        Map.put(normalized, voter_id, candidate_id)

      _entry, normalized ->
        normalized
    end)
  end

  defp election_votes(_election), do: %{}

  defp headship_metadata(%Realm{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, @metadata_key) do
      headship when is_map(headship) ->
        headship
        |> Map.put_new("version", @version)
        |> Map.put_new("head_character_id", nil)

      _other ->
        %{"version" => @version, "head_character_id" => nil}
    end
  end

  defp update_headship!(%Realm{} = realm, headship) do
    realm
    |> Realm.changeset(%{metadata: Map.put(realm.metadata || %{}, @metadata_key, headship)})
    |> Repo.update!()
  end

  defp list_active_player_professors(realm_id) do
    Professor
    |> join(:inner, [professor], character in assoc(professor, :character))
    |> where(
      [professor, character],
      professor.realm_id == ^realm_id and professor.status == :active and
        character.status == :active
    )
    |> order_by([professor, _character], asc: professor.appointed_at, asc: professor.character_id)
    |> preload([_professor, character], character: character)
    |> Repo.all()
    |> Enum.reject(&npc_faculty?/1)
  end

  defp lock_active_player_professors!(realm_id) do
    Professor
    |> join(:inner, [professor], character in assoc(professor, :character))
    |> where(
      [professor, character],
      professor.realm_id == ^realm_id and professor.status == :active and
        character.status == :active
    )
    |> order_by([professor, _character], asc: professor.character_id, asc: professor.id)
    |> lock("FOR UPDATE")
    |> preload([_professor, character], character: character)
    |> Repo.all()
    |> Enum.reject(&npc_faculty?/1)
  end

  defp active_professor?(professors, character_id) when is_binary(character_id),
    do: Enum.any?(professors, &(&1.character_id == character_id))

  defp active_professor?(_professors, _character_id), do: false

  defp npc_faculty?(%Professor{} = professor),
    do: Map.get(professor.metadata || %{}, "npc_faculty") == true

  defp lock_realm!(realm_id) do
    Realm
    |> where([realm], realm.id == ^realm_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp get_realm(%Realm{} = realm), do: realm
  defp get_realm(realm_id) when is_binary(realm_id), do: Repo.get(Realm, realm_id)
  defp get_realm(_realm), do: nil

  defp valid_election_window?(hours), do: is_integer(hours) and hours in 1..168

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp headship_changeset(message) do
    %Realm{}
    |> Changeset.change()
    |> Changeset.add_error(:metadata, message)
  end
end
