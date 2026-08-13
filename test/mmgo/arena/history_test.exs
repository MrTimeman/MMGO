defmodule MMGO.Arena.HistoryTest do
  @moduledoc """
  History is a reader over what the engine already wrote, and a fight is a
  memory with a lifetime.
  """

  use MMGO.DataCase, async: false

  alias MMGO.Accounts.Account
  alias MMGO.Arena
  alias MMGO.Arena.History
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "history-test", name: "History Realm", is_default: true})

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

  test "a settled match is readable as history", context do
    winner = profile_fixture(context, "history-winner", [:fire, :water, :air])
    loser = profile_fixture(context, "history-loser", [:earth, :life, :death])

    {:ok, _queued} = Arena.queue_ranked(winner)
    {:ok, paired} = Arena.queue_ranked(loser)

    combat =
      paired.combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "a",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    {:ok, _settled} = Arena.settle_match(combat)

    assert [entry] = History.list_for_profile(winner)
    assert entry.outcome == :win
    assert entry.rating_delta > 0
    assert entry.mode == :ranked
    assert entry.replayable?
    assert entry.opponents == [loser.character.name]

    assert [%{outcome: :loss, rating_delta: delta}] = History.list_for_profile(loser)
    assert delta < 0
  end

  test "a replay reads back the turns the engine resolved", context do
    first = profile_fixture(context, "replay-one", [:fire, :water, :air])
    second = profile_fixture(context, "replay-two", [:earth, :life, :death])

    {:ok, _queued} = Arena.queue_ranked(first)
    {:ok, paired} = Arena.queue_ranked(second)

    {:ok, _resolved} = Combat.resolve_turn(paired.combat, force?: true)

    replay = History.replay(paired.combat_id)

    assert replay.seed == paired.combat.seed
    assert [%{number: 1} = turn | _rest] = replay.turns
    assert is_binary(turn.narration)
    # Every turn the engine resolved carries its own events, in sequence.
    assert Enum.map(turn.events, & &1.sequence) == Enum.sort(Enum.map(turn.events, & &1.sequence))
  end

  test "an unknown fight has no replay" do
    assert History.replay(Ecto.UUID.generate()) == nil
    assert History.replay(nil) == nil
  end

  test "fights older than the retention window are forgotten", context do
    first = profile_fixture(context, "prune-one", [:fire, :water, :air])
    second = profile_fixture(context, "prune-two", [:earth, :life, :death])

    {:ok, _queued} = Arena.queue_ranked(first)
    {:ok, paired} = Arena.queue_ranked(second)

    long_ago = DateTime.add(DateTime.utc_now(), -(History.retention_days() + 1), :day)

    combat =
      paired.combat
      |> CombatSchema.changeset(%{status: :finished, winner_side: "a", finished_at: long_ago})
      |> Repo.update!()

    {:ok, _settled} = Arena.settle_match(combat)

    assert {:ok, 1} = History.prune()
    assert History.replay(paired.combat_id) == nil

    # The ladder's record of who played whom survives the loss of the record of
    # how they played.
    assert [%{replayable?: false}] = History.list_for_profile(first)
  end

  test "a recent fight is kept", context do
    first = profile_fixture(context, "keep-one", [:fire, :water, :air])
    second = profile_fixture(context, "keep-two", [:earth, :life, :death])

    {:ok, _queued} = Arena.queue_ranked(first)
    {:ok, paired} = Arena.queue_ranked(second)

    paired.combat
    |> CombatSchema.changeset(%{
      status: :finished,
      winner_side: "a",
      finished_at: DateTime.utc_now()
    })
    |> Repo.update!()

    assert {:ok, 0} = History.prune()
    refute is_nil(History.replay(paired.combat_id))
  end

  defp profile_fixture(_context, handle, schools) do
    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{display_name: "History #{handle}", handle: handle})
      |> Repo.insert()

    {:ok, profile} =
      Arena.create_profile(account, %{"schools" => Enum.map(schools, &to_string/1)})

    Repo.preload(profile, :character)
  end
end
