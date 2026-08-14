defmodule MMGOWeb.ArenaLiveTest do
  use MMGOWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.Account
  alias MMGO.Arena
  alias MMGO.Combat.ArenaEvents
  alias MMGO.Combat.Participant
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "arena-live-#{suffix}",
        name: "Arena Live Realm",
        is_default: true
      })

    {:ok, _tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "Башня",
        kind: :tower,
        x: 0,
        y: 0,
        safe_zone: true
      })

    profile = arena_profile_fixture("arena-live-#{suffix}")

    %{profile: profile}
  end

  # The home is for finding a fight. What it used to carry besides — an
  # eight-card catalogue of arena events, a block advertising summons, and a
  # paragraph explaining what the Arena is — told the player things instead of
  # letting them do anything.
  test "the home is standing, a way into a fight, and what is open", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena")

    assert has_element?(view, "#arena-home")
    assert has_element?(view, "#arena-profile-card")
    assert has_element?(view, "#arena-ranked-queue[href='/arena/queue']")
    assert has_element?(view, "#arena-create-room[href='/arena/rooms/new']")
    assert has_element?(view, "#arena-open-rooms-section")

    refute has_element?(view, "#arena-system-highlights")
    refute has_element?(view, "#arena-summon-highlight")
    refute has_element?(view, "#arena-lore")

    for event_code <- ArenaEvents.event_codes() do
      refute has_element?(view, "#arena-event-#{event_code}")
    end
  end

  # The measured problem this rework exists to fix: the queue button used to sit
  # a screen and a half below the fold, under a 693px lore hero. The lore is
  # gone entirely now, and the button sits above everything that remains.
  test "the queue button is the first thing on the page", %{conn: conn, profile: profile} do
    {:ok, view, html} = live(arena_session(conn, profile), ~p"/arena")

    assert has_element?(view, "#arena-launch #arena-ranked-queue")

    [queue_at, rooms_at] =
      Enum.map(
        ["id=\"arena-ranked-queue\"", "id=\"arena-open-rooms-section\""],
        &:binary.match(html, &1)
      )

    assert queue_at < rooms_at
  end

  # The Arena had two navigations stacked on one screen — a bar and a shortcut
  # row — that both led to the grimoire, and the bar offered the page you were
  # standing on as though it were somewhere to go.
  test "one navigation, no destination offered twice", %{conn: conn, profile: profile} do
    {:ok, view, html} = live(arena_session(conn, profile), ~p"/arena")

    # The section you are in is marked as a place, not repeated as a button.
    assert has_element?(view, "#arena-nav-fights[aria-current='page']")
    refute has_element?(view, "#arena-nav-spellbook[aria-current='page']")

    # The shortcut row carries only what the bar cannot reach.
    refute has_element?(view, "#arena-launch-spellbook")
    assert has_element?(view, "#arena-create-room[href='/arena/rooms/new']")
    assert has_element?(view, "#arena-launch-seats[href='/arena/seats']")

    # No two navigation entries lead to the same place.
    nav_hrefs = [
      "/arena",
      "/arena/spellbook/books",
      "/arena/rankings",
      "/arena/rooms/new",
      "/arena/seats",
      "/arena/history"
    ]

    ids = ~w(
      arena-nav-fights arena-nav-spellbook arena-nav-rankings
      arena-create-room arena-launch-seats arena-launch-history
    )

    for {id, href} <- Enum.zip(ids, nav_hrefs) do
      assert has_element?(view, "##{id}[href='#{href}']"), "#{id} should lead to #{href}"
    end

    assert nav_hrefs == Enum.uniq(nav_hrefs)

    assert is_binary(html)
  end

  # `круг` is the spell-creation circle. A fight is a fight.
  test "a fight is never called a circle", %{conn: conn, profile: profile} do
    {:ok, _view, html} = live(arena_session(conn, profile), ~p"/arena")

    refute html =~ "Свой круг"
    refute html =~ "Три круга"
    refute html =~ "Дюжина кругов"
    assert html =~ "Своя комната"
  end

  test "a player with one profile is not offered a profile switcher", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena")

    refute has_element?(view, "#arena-profile-switch")

    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/profiles")

    assert has_element?(view, "#arena-profile-#{profile.id}")
    refute has_element?(view, "#arena-switch-profile-#{profile.id}")
  end

  test "history lists a settled fight and steps through its replay", %{
    conn: conn,
    profile: profile
  } do
    rival = arena_profile_fixture("arena-history-#{System.unique_integer([:positive])}")

    {:ok, _queued} = Arena.queue_ranked(profile)
    {:ok, paired} = Arena.queue_ranked(rival)

    {:ok, _resolved} = MMGO.Combat.resolve_turn(paired.combat, force?: true)

    combat =
      paired.combat_id
      |> MMGO.Combat.get_combat!()
      |> MMGO.Combat.Combat.changeset(%{
        status: :finished,
        winner_side: "a",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    {:ok, settled} = Arena.settle_match(combat)

    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/history")

    assert has_element?(view, "#arena-history-#{settled.id}")
    assert has_element?(view, "#arena-replay-#{settled.id}")

    {:ok, replay, _html} = live(arena_session(conn, profile), ~p"/arena/history/#{combat.id}")

    assert has_element?(replay, "#arena-replay-turn")
    assert has_element?(replay, "#arena-replay-prev[disabled]")
  end

  test "a finished fight lands on its result, with the way back into the queue", %{
    conn: conn,
    profile: profile
  } do
    rival = arena_profile_fixture("arena-result-#{System.unique_integer([:positive])}")

    {:ok, _queued} = Arena.queue_ranked(profile)
    {:ok, paired} = Arena.queue_ranked(rival)

    combat =
      paired.combat
      |> MMGO.Combat.Combat.changeset(%{
        status: :finished,
        winner_side: "a",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    {:ok, settled} = Arena.settle_match(combat)

    {:ok, view, html} = live(arena_session(conn, profile), ~p"/arena/result/#{settled.id}")

    assert has_element?(view, "#arena-result-rating")
    assert has_element?(view, "#arena-result-requeue")
    assert html =~ "Победа"

    # And the queue is genuinely one tap away.
    view |> element("#arena-result-requeue") |> render_click()
    assert %{status: :queued} = Arena.active_match_for_profile(profile)
  end

  test "the home board shows standing reasons to come back", %{conn: conn, profile: profile} do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena")

    assert has_element?(view, "#arena-quests")

    for quest <- MMGO.Arena.Quests.definitions() do
      assert has_element?(view, "#arena-quest-#{quest.code}")
    end

    # A player who has not played has no streak to boast about.
    refute has_element?(view, "#arena-streak")
  end

  test "the queue says who is waiting and how long it usually takes", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/queue")

    assert has_element?(view, "#arena-queue-population")
  end

  test "someone else's fight cannot be replayed", %{conn: conn, profile: profile} do
    rival = arena_profile_fixture("arena-nosy-#{System.unique_integer([:positive])}")

    {:ok, _queued} = Arena.queue_ranked(profile)
    {:ok, paired} = Arena.queue_ranked(rival)

    stranger = arena_profile_fixture("arena-stranger-#{System.unique_integer([:positive])}")

    assert {:error, {:live_redirect, %{to: "/arena/history"}}} =
             live(arena_session(conn, stranger), ~p"/arena/history/#{paired.combat_id}")
  end

  test "the seats screen names both seats and the way to them", %{conn: conn, profile: profile} do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/seats")

    assert has_element?(view, "#arena-seat-champion")
    assert has_element?(view, "#arena-seat-deputy")
    assert has_element?(view, "#arena-gauntlet-eligibility")
  end

  test "ranked search is persisted and can be cancelled from the queue", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/queue")

    assert has_element?(view, "#arena-queue-ready")

    view |> element("#arena-join-queue") |> render_click()

    assert has_element?(view, "#arena-searching")
    assert %{status: :queued, mode: :ranked} = Arena.active_match_for_profile(profile)

    view |> element("#arena-cancel-queue") |> render_click()

    assert has_element?(view, "#arena-queue-ready")
    assert Arena.active_match_for_profile(profile) == nil
  end

  test "host configures and creates a bounded friendly NvN room", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/rooms/new")

    assert has_element?(view, "#arena-room-form")
    assert has_element?(view, "#arena-team-size option[value='5']")
    assert has_element?(view, "#arena-turn-seconds option[value='120']")
    assert has_element?(view, "#arena-event-policy")

    view
    |> form("#arena-room-form", %{
      "arena_room" => %{
        "room_name" => "Два отряда",
        "description" => "Проверяем командные формулы",
        "team_size" => "2",
        "turn_seconds" => "90",
        "event_policy" => "fixed",
        "event_codes" => ["emberfall", "healing_rain"]
      }
    })
    |> render_submit()

    room = Arena.active_match_for_profile(profile)
    assert room.mode == :custom
    assert room.team_size == 2
    assert room.event_policy == :fixed
    assert room.event_codes == ["emberfall", "healing_rain"]
    assert room.settings["room_name"] == "Два отряда"
    assert room.settings["turn_seconds"] == 90
    assert_redirect(view, ~p"/arena/rooms/#{room.code}")
  end

  test "a room member can leave and a host can close the room", %{
    conn: conn,
    profile: profile
  } do
    assert {:ok, room} = Arena.create_custom_room(profile, %{team_size: 1})
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena/rooms/#{room.code}")

    assert has_element?(view, "#arena-leave-room", "Закрыть комнату")
    view |> element("#arena-leave-room") |> render_click()

    assert_redirect(view, ~p"/arena")
    assert Arena.get_match!(room.id).status == :cancelled
    assert Arena.active_match_for_profile(profile) == nil
  end

  test "arena combat foregrounds events and summons while disabling world items", %{
    conn: conn,
    profile: profile
  } do
    rival = arena_profile_fixture("arena-rival-#{System.unique_integer([:positive])}")

    assert {:ok, %{status: :queued}} = Arena.queue_ranked(profile)
    assert {:ok, %{status: :active}} = Arena.queue_ranked(rival)

    match = Arena.active_match_for_profile(profile)
    combat = MMGO.Combat.get_combat!(match.combat_id)
    participant = Enum.find(combat.participants, &(&1.character_id == profile.character_id))

    participant
    |> Participant.changeset(%{
      active_states: [
        %{
          "state" => "summoned_weapon",
          "display_name" => "Клинок грозы",
          "power" => 18,
          "remaining_turns" => 3,
          "applied_on_turn" => 0,
          "source_spell_id" =>
            participant.grimoire.entries |> List.first() |> Map.fetch!(:spell_id)
        }
      ]
    })
    |> Repo.update!()

    {:ok, view, _html} =
      live(arena_session(conn, profile), ~p"/arena/combat/#{match.combat_id}")

    # The screen is five things: status, gauges, who is standing, the
    # chronicle, and the line. Nothing else may appear on it.
    assert has_element?(view, "#combat-screen")
    assert has_element?(view, "#combat-deadline")
    assert has_element?(view, "#combat-events")
    assert has_element?(view, "#combat-command")

    # A summoned weapon is a word you may write, and the engine honours it.
    assert has_element?(view, "#combat-target-#{participant.id}")

    view
    |> form("#combat-command-form", %{"command" => "удар"})
    |> render_submit()

    refute has_element?(view, "#combat-action-error")
  end

  defp arena_profile_fixture(handle) do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Arena Live Mage",
        handle: handle
      })
      |> Repo.insert!()

    {:ok, profile} =
      Arena.create_profile(account, %{
        name: "Испытатель Арены",
        schools: [:fire, :water, :death]
      })

    profile
  end

  defp arena_session(conn, profile) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, profile.account_id)
    |> Plug.Conn.put_session(:current_character_id, profile.character_id)
    |> Plug.Conn.put_session(:game_mode, "arena")
  end
end
