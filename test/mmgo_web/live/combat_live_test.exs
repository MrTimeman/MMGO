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
        formula: "Vocatio Sustineo",
        incantation_slots: %{"actio" => "Vocatio", "tempus" => "Sustineo"},
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
                 %{
                   character_id: challenger.id,
                   side: "attackers",
                   position: 0,
                   grimoire_id: grimoire.id
                 },
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
    assert has_element?(view, "#combat-command-form")
    assert has_element?(view, "#combat-command")

    # The formula is offered for reading, not for pressing: it writes the line.
    assert has_element?(view, "#combat-formula-#{spell.id}")
    assert has_element?(view, "#combat-target-#{defender_participant.id}")

    assert has_element?(
             view,
             "#combat-incantation-slots .cbt-slot[title='Actio · действие']",
             "A"
           )

    assert has_element?(view, "#combat-incantation-slots .cbt-slot[title='Forma · форма']", "F")
    assert has_element?(view, "#combat-incantation-slots .cbt-slot[title='Vis · сила']", "V")
    assert has_element?(view, "#combat-incantation-slots .cbt-slot[title='Tempus · время']", "T")

    assert has_element?(
             view,
             "#combat-incantation-slots .cbt-slot[title='Mutatio · изменение']",
             "M"
           )

    assert has_element?(view, "#combat-incantation-slots .cbt-slot[title='Pretium · цена']", "P")

    # Nothing is written yet, so nothing is lit. The seals answer the line.
    refute has_element?(view, "#combat-incantation-slots .cbt-slot.cbt-slot--lit")
    assert has_element?(view, "#combat-incantation-slots .cbt-slots__count", "0/6")

    view
    |> form("#combat-command-form", %{"command" => "vocatio sustineo"})
    |> render_change()

    assert has_element?(view, "#combat-incantation-slots .cbt-slots__count", "2/6")

    assert has_element?(
             view,
             "#combat-incantation-slots .cbt-slot.cbt-slot--lit[title='Actio · действие']"
           )

    assert has_element?(
             view,
             "#combat-incantation-slots .cbt-slot.cbt-slot--lit[title='Tempus · время']"
           )

    refute has_element?(
             view,
             "#combat-incantation-slots .cbt-slot.cbt-slot--lit[title='Forma · форма']"
           )

    refute has_element?(view, "#atmosphere-audio")

    view
    |> form("#combat-command-form", %{
      "command" => "#{spell.formula} по #{defender_participant.display_name}"
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
    refute has_element?(view, "#combat-command-form")
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

    # `ждать` is what ends a channel now, and the hint says so.
    assert has_element?(view, "#combat-verb-ждать")
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

    # Fleeing is a word like any other, and it is kept the moment it is written.
    assert has_element?(view, "#combat-verb-бежать")

    view
    |> form("#combat-command-form", %{"command" => "бежать"})
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
