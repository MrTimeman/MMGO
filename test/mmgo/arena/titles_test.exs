defmodule MMGO.Arena.TitlesTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.Account
  alias MMGO.Arena.{Profile, TitleSeat, Titles}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "titles-test", name: "Titles Realm", is_default: true})

    %{realm: realm}
  end

  test "there can be only one holder of each seat", %{realm: realm} do
    first = profile_fixture(realm, "seat-one")
    second = profile_fixture(realm, "seat-two")

    assert {:ok, _crowned} = Titles.crown_champion(first)

    assert {:error, changeset} =
             %TitleSeat{}
             |> TitleSeat.changeset(%{
               seat: :champion,
               season: 1,
               status: :held,
               profile_id: second.id,
               account_id: second.account_id
             })
             |> Repo.insert()

    assert %{season: ["seat is already held this season"]} = errors_on(changeset)
  end

  test "a champion appoints a deputy who may accept", %{realm: realm} do
    champion = profile_fixture(realm, "appoint-champ")
    deputy = profile_fixture(realm, "appoint-deputy")

    {:ok, _seat} = Titles.crown_champion(champion)

    assert {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    assert offer.status == :offered
    assert offer.appointed_by_profile_id == champion.id
    assert Titles.holder(:deputy) == nil

    assert {:ok, held} = Titles.accept_deputy(offer)
    assert held.status == :held
    assert Titles.holder(:deputy).profile_id == deputy.id
  end

  test "a declined offer leaves the seat empty", %{realm: realm} do
    champion = profile_fixture(realm, "decline-champ")
    deputy = profile_fixture(realm, "decline-deputy")

    {:ok, _seat} = Titles.crown_champion(champion)
    {:ok, offer} = Titles.appoint_deputy(champion, deputy)

    assert {:ok, declined} = Titles.decline_deputy(offer)
    assert declined.status == :declined
    assert Titles.holder(:deputy) == nil
  end

  test "only the champion may appoint, and never themselves", %{realm: realm} do
    champion = profile_fixture(realm, "only-champ")
    pretender = profile_fixture(realm, "pretender")

    {:ok, _seat} = Titles.crown_champion(champion)

    assert {:error, :not_the_champion} = Titles.appoint_deputy(pretender, champion)
    assert {:error, :cannot_appoint_yourself} = Titles.appoint_deputy(champion, champion)
  end

  test "a champion without a deputy is frozen out of ranked play but unchallengeable",
       %{realm: realm} do
    champion = profile_fixture(realm, "frozen-champ")
    deputy = profile_fixture(realm, "frozen-deputy")

    {:ok, _seat} = Titles.crown_champion(champion)

    refute Titles.ranked_play_allowed?(champion)
    refute Titles.challengeable?(:champion)

    {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    {:ok, _held} = Titles.accept_deputy(offer)

    assert Titles.ranked_play_allowed?(champion)
    assert Titles.challengeable?(:champion)
  end

  test "everyone other than a seatless champion may queue", %{realm: realm} do
    champion = profile_fixture(realm, "queue-champ")
    ordinary = profile_fixture(realm, "queue-ordinary")

    {:ok, _seat} = Titles.crown_champion(champion)

    assert Titles.ranked_play_allowed?(ordinary)
  end

  test "a coup vacates both seats and the new champion appoints fresh", %{realm: realm} do
    champion = profile_fixture(realm, "coup-champ")
    deputy = profile_fixture(realm, "coup-deputy")
    challenger = profile_fixture(realm, "coup-challenger")

    {:ok, _seat} = Titles.crown_champion(champion)
    {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    {:ok, _held} = Titles.accept_deputy(offer)

    assert {:ok, _crowned} = Titles.crown_champion(challenger)

    assert Titles.holder(:champion).profile_id == challenger.id
    assert Titles.holder(:deputy) == nil
    refute Titles.ranked_play_allowed?(challenger)
  end

  test "an absent champion is answered for by the deputy", %{realm: realm} do
    champion = profile_fixture(realm, "idle-champ")
    deputy = profile_fixture(realm, "idle-deputy")

    {:ok, seat} = Titles.crown_champion(champion)
    {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    {:ok, _held} = Titles.accept_deputy(offer)

    now = DateTime.utc_now()
    assert Titles.acting_champion(1, now).profile_id == champion.id

    long_gone = DateTime.add(now, Titles.idle_after_days() + 1, :day)
    assert Titles.idle?(seat, long_gone)
    assert Titles.acting_champion(1, long_gone).profile_id == deputy.id
  end

  test "an unanswered challenge is claimable only after the deadline" do
    challenged_at = DateTime.utc_now()

    refute Titles.claimable_by_default?(challenged_at, challenged_at)

    deadline =
      DateTime.add(challenged_at, Titles.unanswered_challenge_days(), :day)

    assert Titles.claimable_by_default?(challenged_at, deadline)
  end

  test "only the top division opens the gauntlet", %{realm: realm} do
    contender = profile_fixture(realm, "gauntlet-contender")

    refute Titles.eligible_to_challenge?(%{contender | division: :diamond})
    assert Titles.eligible_to_challenge?(%{contender | division: :archmage})
  end

  test "one person cannot hold both seats through a second arena character",
       %{realm: realm} do
    champion = profile_fixture(realm, "two-seats-champ")
    alter_ego = second_profile_for_account(realm, champion, "alter-ego")

    {:ok, _seat} = Titles.crown_champion(champion)

    assert {:error, :cannot_appoint_your_own_account} =
             Titles.appoint_deputy(champion, alter_ego)

    # And the database refuses it even if the rule above were bypassed.
    assert {:error, changeset} =
             %TitleSeat{}
             |> TitleSeat.changeset(%{
               seat: :deputy,
               season: 1,
               status: :held,
               profile_id: alter_ego.id,
               account_id: alter_ego.account_id
             })
             |> Repo.insert()

    assert %{season: ["you already hold a seat this season"]} = errors_on(changeset)
  end

  describe "the gauntlet" do
    setup %{realm: realm} do
      champion = profile_fixture(realm, "gauntlet-champ")
      deputy = profile_fixture(realm, "gauntlet-deputy")
      challenger = profile_fixture(realm, "gauntlet-challenger")

      {:ok, _seat} = Titles.crown_champion(champion)
      {:ok, offer} = Titles.appoint_deputy(champion, deputy)
      {:ok, _held} = Titles.accept_deputy(offer)

      %{champion: champion, deputy: deputy, challenger: challenger}
    end

    test "the Champion cannot be called out before the Deputy is beaten", %{
      challenger: challenger
    } do
      assert {:error, :deputy_not_yet_beaten} = Titles.challenge_champion(challenger)
    end

    test "beating the Deputy earns an expiring right to the Champion", %{
      challenger: challenger,
      deputy: deputy
    } do
      assert {:ok, challenge} = Titles.challenge_deputy(challenger)
      assert challenge.seat == :deputy
      assert challenge.defender_profile_id == deputy.id

      assert {:ok, won} = Titles.settle(challenge, challenger.id)
      assert won.status == :won
      assert Titles.gauntlet_right?(challenger)

      # And the right lapses if it is not used.
      lapsed = DateTime.add(won.grants_until, 1, :second)
      refute Titles.gauntlet_right?(challenger, 1, lapsed)
      assert {:error, :deputy_not_yet_beaten} = Titles.challenge_champion(challenger, 1, lapsed)

      assert {:ok, title_bout} = Titles.challenge_champion(challenger)
      assert title_bout.seat == :champion
    end

    test "beating the Champion takes the seat and vacates both", %{
      challenger: challenger
    } do
      {:ok, deputy_fight} = Titles.challenge_deputy(challenger)
      {:ok, _won} = Titles.settle(deputy_fight, challenger.id)
      {:ok, title_bout} = Titles.challenge_champion(challenger)

      assert {:ok, settled} = Titles.settle(title_bout, challenger.id)
      assert settled.status == :won
      assert Titles.holder(:champion).profile_id == challenger.id
      assert Titles.holder(:deputy) == nil
    end

    test "a failed challenge costs a cooldown, not the ladder", %{challenger: challenger} do
      {:ok, challenge} = Titles.challenge_deputy(challenger)

      assert {:ok, lost} = Titles.settle(challenge, challenge.defender_profile_id)
      assert lost.status == :lost

      assert {:error, :challenge_cooldown} = Titles.challenge_deputy(challenger)

      after_cooldown = DateTime.add(lost.resolved_at, Titles.failure_cooldown_days() + 1, :day)
      assert {:ok, _again} = Titles.challenge_deputy(challenger, 1, after_cooldown)
    end

    test "a title challenge cannot be declined", %{challenger: challenger} do
      {:ok, challenge} = Titles.challenge_deputy(challenger)

      assert {:error, :title_challenge_cannot_be_declined} = Titles.decline_challenge(challenge)
      assert Titles.open_challenge(:deputy).id == challenge.id
    end

    test "a challenge left unanswered is claimed by the challenger", %{challenger: challenger} do
      {:ok, challenge} = Titles.challenge_deputy(challenger)

      assert {:error, :challenge_still_answerable} = Titles.claim_unanswered(challenge)

      deadline =
        DateTime.add(challenge.challenged_at, Titles.unanswered_challenge_days(), :day)

      assert {:ok, claimed} = Titles.claim_unanswered(challenge, deadline)
      assert claimed.status == :claimed
      assert Titles.gauntlet_right?(challenger, 1, deadline)
    end

    test "an unanswered call on the Champion takes the seat outright", %{
      challenger: challenger
    } do
      {:ok, deputy_fight} = Titles.challenge_deputy(challenger)
      {:ok, _won} = Titles.settle(deputy_fight, challenger.id)
      {:ok, title_bout} = Titles.challenge_champion(challenger)

      deadline =
        DateTime.add(title_bout.challenged_at, Titles.unanswered_challenge_days(), :day)

      assert {:ok, claimed} = Titles.claim_unanswered(title_bout, deadline)
      assert claimed.status == :claimed
      assert Titles.holder(:champion).profile_id == challenger.id
    end

    test "a seat holder who fights is not away", %{champion: champion} do
      seat = Titles.holder(:champion)
      long_after = DateTime.add(DateTime.utc_now(), Titles.idle_after_days() + 1, :day)

      assert Titles.idle?(seat, long_after)

      :ok = Titles.touch_activity(champion, 1, long_after)

      assert Titles.holder(:champion) |> Titles.idle?(long_after) == false
      assert Titles.acting_champion(1, long_after).profile_id == champion.id
    end

    test "the Deputy defends and never challenges", %{deputy: deputy} do
      assert {:error, :deputy_may_not_challenge} = Titles.challenge_deputy(deputy)
      assert {:error, :deputy_may_not_challenge} = Titles.challenge_champion(deputy)
    end

    test "one seat may only be challenged by one pretender at a time", %{
      realm: realm,
      challenger: challenger
    } do
      other = profile_fixture(realm, "gauntlet-other")

      {:ok, _challenge} = Titles.challenge_deputy(challenger)

      assert {:error, changeset} = Titles.challenge_deputy(other)
      assert %{season: ["this seat is already being challenged"]} = errors_on(changeset)
    end

    test "a division below Archmage cannot enter the gauntlet at all", %{
      realm: realm
    } do
      hopeful = profile_fixture(realm, "gauntlet-hopeful")

      hopeful =
        hopeful |> Ecto.Changeset.change(division: :diamond) |> Repo.update!()

      assert {:error, :division_too_low} = Titles.challenge_deputy(hopeful)
    end

    test "an empty Deputy seat cannot be challenged", %{realm: realm, champion: champion} do
      Titles.holder(:deputy) |> Ecto.Changeset.change(status: :vacated) |> Repo.update!()

      other = profile_fixture(realm, "gauntlet-orphan")

      assert {:error, :seat_not_challengeable} = Titles.challenge_deputy(other)
      # And a Champion with no Deputy is unreachable while they stay that way.
      assert {:error, :seat_not_challengeable} = Titles.challenge_champion(other)
      refute Titles.ranked_play_allowed?(champion)
    end
  end

  defp second_profile_for_account(realm, %Profile{} = existing, handle) do
    character =
      %MMGO.Accounts.Character{account_id: existing.account_id, realm_id: realm.id}
      |> MMGO.Accounts.Character.changeset(%{
        name: "Alter #{handle}",
        status: :active,
        metadata: %{"profile_kind" => "arena"}
      })
      |> Repo.insert!()

    %Profile{account_id: existing.account_id, character_id: character.id}
    |> Profile.changeset(%{schools: [:earth, :life, :death], rating: 2_600, division: :archmage})
    |> Repo.insert!()
  end

  defp profile_fixture(realm, handle) do
    {:ok, account} =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Title #{handle}",
        handle: handle
      })
      |> Repo.insert()

    character =
      %MMGO.Accounts.Character{account_id: account.id, realm_id: realm.id}
      |> MMGO.Accounts.Character.changeset(%{
        name: "Champion #{handle}",
        status: :active,
        metadata: %{"profile_kind" => "arena"}
      })
      |> Repo.insert!()

    %Profile{account_id: account.id, character_id: character.id}
    |> Profile.changeset(%{schools: [:fire, :water, :air], rating: 2_600, division: :archmage})
    |> Repo.insert!()
  end
end
