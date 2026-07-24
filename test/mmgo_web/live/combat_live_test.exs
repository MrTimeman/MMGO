defmodule MMGOWeb.CombatLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.{Participant, ResolveTurnWorker, Turn}
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "combat-live", name: "Combat Live Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "combat-live-tower",
        name: "Combat Live Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "combat-live-city",
        name: "Combat Live City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    challenger = character_fixture(realm, tower, "combat-live-challenger", "Live Challenger")
    defender = character_fixture(realm, tower, "combat-live-defender", "Live Defender")
    outsider = character_fixture(realm, tower, "combat-live-outsider", "Live Outsider")
    intruder = character_fixture(realm, city, "combat-live-intruder", "Live Intruder")

    spell =
      spell_fixture(challenger, %{
        name: "Live Ultima",
        formula: "Ignis Ultima Suprema",
        effects: [
          %{applies_to: :target, state: "impact", intensity: 100, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    {:ok, grimoire} =
      Grimoires.create_grimoire(challenger, %{name: "Live Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, _active_grimoire} = Grimoires.activate_grimoire(challenger, grimoire)

    assert {:ok, %{combat: combat}} =
             Combat.create_duel(realm, %{
               participants: [
                 %{character_id: challenger.id, side: "attackers", position: 0},
                 %{character_id: defender.id, side: "defenders", position: 0}
               ],
               metadata: %{location_id: tower.id, location_kind: "tower"}
             })

    combat = Combat.get_combat!(combat.id)
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    %{
      realm: realm,
      challenger: challenger,
      defender: defender,
      outsider: outsider,
      intruder: intruder,
      spell: spell,
      combat: combat,
      defender_participant: defender_participant
    }
  end

  test "a participant seals a real action and sees the worker-resolved outcome", %{
    conn: conn,
    challenger: challenger,
    spell: spell,
    combat: combat,
    defender_participant: defender_participant
  } do
    conn = session_conn(conn, challenger)
    combat_path = ~p"/combat/#{combat.id}"

    {:ok, view, _html} = live(conn, combat_path)

    assert has_element?(view, "#combat-screen")
    assert has_element?(view, "#combat-action-form")
    assert has_element?(view, "#combat-action-kind")
    assert has_element?(view, "#combat-cast-spell option[value=\"#{spell.id}\"]")
    assert has_element?(view, "#combat-target-#{defender_participant.id}")

    refute has_element?(view, "#atmosphere-audio")

    view
    |> form("#combat-action-form", %{
      "combat_action" => %{
        "action_type" => "cast_spell",
        "spell_id" => spell.id,
        "incantation" => spell.formula,
        "inventory_item_id" => "",
        "tool_action" => "",
        "target_side" => "defenders",
        "target_participant_id" => defender_participant.id
      }
    })
    |> render_submit()

    assert has_element?(view, "#combat-resolving")

    job =
      Oban.Job
      |> Repo.all()
      |> Enum.find(fn job ->
        job.worker == "MMGO.Combat.ResolveTurnWorker" and
          job.args["combat_id"] == combat.id and job.args["trigger"] == "all_actions"
      end)

    assert job
    assert :ok = ResolveTurnWorker.perform(%Oban.Job{args: job.args})
    assert %Turn{status: :resolved} = Repo.get!(Turn, job.args["turn_id"])

    {:ok, resolved_view, _html} = live(conn, combat_path)
    assert has_element?(resolved_view, "#combat-outcome")
  end

  test "a same-location non-participant sees a read-only spectator view", %{
    conn: conn,
    outsider: outsider,
    combat: combat
  } do
    {:ok, view, _html} = live(session_conn(conn, outsider), ~p"/combat/#{combat.id}")

    assert has_element?(view, "#combat-spectator")
    refute has_element?(view, "#combat-action-form")
  end

  test "a channeling participant can clearly choose to interrupt the channel", %{
    conn: conn,
    challenger: challenger,
    combat: combat
  } do
    challenger_participant =
      Enum.find(combat.participants, &(&1.character_id == challenger.id))

    challenger_participant
    |> Participant.changeset(%{
      active_states: [%{"state" => "channeling", "intensity" => 1, "duration" => 2}]
    })
    |> Repo.update!()

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/combat/#{combat.id}")

    assert has_element?(view, "#combat-channeling-hint")

    assert has_element?(
             view,
             "#combat-action-kind option[value='wait']",
             "Прервать канал"
           )
  end

  test "a remote non-participant is redirected away from a guessed combat ID", %{
    conn: conn,
    intruder: intruder,
    combat: combat
  } do
    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} =
             live(session_conn(conn, intruder), ~p"/combat/#{combat.id}")

    assert flash["error"] =~ "недоступен"
  end

  test "the flee control seals a real forfeit", %{
    conn: conn,
    challenger: challenger,
    combat: combat
  } do
    conn = session_conn(conn, challenger)
    combat_path = ~p"/combat/#{combat.id}"
    {:ok, view, _html} = live(conn, combat_path)

    assert has_element?(view, "#combat-flee")
    view |> element("#combat-flee") |> render_click()
    assert has_element?(view, "#combat-resolving")

    job =
      Oban.Job
      |> Repo.all()
      |> Enum.find(fn job ->
        job.worker == "MMGO.Combat.ResolveTurnWorker" and
          job.args["combat_id"] == combat.id and job.args["trigger"] == "all_actions"
      end)

    assert job
    assert :ok = ResolveTurnWorker.perform(%Oban.Job{args: job.args})
    assert %{status: :finished, winner_side: "defenders"} = Combat.get_combat!(combat.id)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp spell_fixture(character, attrs) do
    defaults = %{
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      description: "A combat screen fixture spell.",
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
    }

    {:ok, spell} = Spells.create_spell(character, Map.merge(defaults, attrs))
    spell
  end

  defp session_conn(conn, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, character.account_id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
