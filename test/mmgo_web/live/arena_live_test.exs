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

  test "home makes ranked, custom, environmental, and summon play immediately visible", %{
    conn: conn,
    profile: profile
  } do
    {:ok, view, _html} = live(arena_session(conn, profile), ~p"/arena")

    assert has_element?(view, "#arena-home")
    assert has_element?(view, "#arena-ranked-queue[href='/arena/queue']")
    assert has_element?(view, "#arena-create-room[href='/arena/rooms/new']")
    assert has_element?(view, "#arena-create-summon-spell[href='/arena/spellbook']")
    assert has_element?(view, "#arena-system-highlights")

    for event_code <- ArenaEvents.event_codes() do
      assert has_element?(view, "#arena-event-#{event_code}")
    end
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
          "source_spell_id" =>
            participant.grimoire.entries |> List.first() |> Map.fetch!(:spell_id)
        }
      ]
    })
    |> Repo.update!()

    {:ok, view, _html} =
      live(arena_session(conn, profile), ~p"/arena/combat/#{match.combat_id}")

    assert has_element?(view, "#combat-back-to-arena[href='/arena']")
    assert has_element?(view, "#arena-active-event[data-event-code]")
    assert has_element?(view, "#arena-environment-tags span")
    assert has_element?(view, "#arena-event-deck .cbt-arena-deck__chip--active")
    assert has_element?(view, "#combat-manifestation-#{participant.id}-0", "Клинок грозы")
    assert has_element?(view, "#combat-summoned-weapon-hint")

    assert has_element?(
             view,
             "#combat-action-kind option[value='manifestation_strike']"
           )

    assert has_element?(view, "#combat-flee", "Сдаться")
    refute has_element?(view, "#combat-tool-item")
    refute has_element?(view, "#combat-action-kind option[value='use_item']")
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
