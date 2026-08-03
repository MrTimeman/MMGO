defmodule MMGOWeb.DuelLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "duel-tower",
        name: "Duel Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    challenger = character_fixture(realm, tower, "challenger", "Challenger")
    opponent = character_fixture(realm, tower, "opponent", "Opponent")

    {:ok, _challenger_funds} = Economy.grant_from_treasury(realm, challenger, 200)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 200)

    killing_blow =
      spell_fixture(challenger, %{
        name: "Ignis Ultima",
        formula: "Ignis Ultima Suprema",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
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

    _grimoire = grimoire_fixture(challenger, killing_blow, "Challenger Grimoire")

    %{realm: realm, challenger: challenger, opponent: opponent, killing_blow: killing_blow}
  end

  test "a protected city renders a safe-zone explanation instead of exposing a duel form", %{
    conn: conn,
    realm: realm,
    challenger: challenger
  } do
    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "duel-city",
        name: "Duel City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    challenger
    |> Character.travel_changeset(%{current_location_id: city.id})
    |> Repo.update!()

    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/pvp")

    assert has_element?(view, "#duel-safe-zone")
    refute has_element?(view, "#duel-challenge-form")
  end

  test "two scoped players create and accept a pending duel through the browser", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent,
    killing_blow: killing_blow
  } do
    {:ok, challenger_view, _html} = live(session_conn(conn, challenger), ~p"/pvp")

    challenger_view
    |> form("#duel-challenge-form", %{
      "duel_challenge" => %{"opponent_id" => opponent.id, "stake" => "100"}
    })
    |> render_submit()

    [pending_duel] = PVP.pending_duels_for_character(challenger.id)
    assert pending_duel.status == :pending
    assert has_element?(challenger_view, "#duel-outgoing-#{pending_duel.id}")
    assert PVP.active_duel_for_character(challenger.id) == nil

    {:ok, opponent_view, _html} = live(session_conn(conn, opponent), ~p"/pvp")
    assert has_element?(opponent_view, "#duel-incoming-#{pending_duel.id}")

    assert {:error, {:live_redirect, %{to: combat_path}}} =
             opponent_view |> element("#duel-accept-#{pending_duel.id}") |> render_click()

    active_duel = PVP.active_duel_for_character(challenger.id)
    assert active_duel.status == :active
    assert combat_path == "/combat/#{active_duel.combat_id}"

    {:ok, combat_view, _html} = live(session_conn(conn, challenger), combat_path)
    assert has_element?(combat_view, "#combat-screen")
    assert has_element?(combat_view, "#combat-action-form")
    assert has_element?(combat_view, "#combat-cast-spell option[value=\"#{killing_blow.id}\"]")
  end

  test "the sealed combat worker resolves and settles the wager", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent,
    killing_blow: killing_blow
  } do
    active_duel = accept_duel(challenger, opponent)
    combat = Combat.get_combat!(active_duel.combat_id)
    defender_participant = Enum.find(combat.participants, &(&1.character_id == opponent.id))

    assert {:ok, _wait} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    {:ok, combat_view, _html} = live(session_conn(conn, challenger), ~p"/combat/#{combat.id}")

    combat_view
    |> form("#combat-action-form", %{
      "combat_action" => %{
        "action_type" => "cast_spell",
        "spell_id" => killing_blow.id,
        "incantation" => killing_blow.formula,
        "inventory_item_id" => "",
        "tool_action" => "",
        "target_side" => "defenders",
        "target_participant_id" => defender_participant.id
      }
    })
    |> render_submit()

    perform_all_actions_worker(active_duel.combat_id)

    resolved_duel = PVP.get_duel!(active_duel.id)
    assert resolved_duel.status == :resolved
    assert resolved_duel.winner_character_id == challenger.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    assert Economy.get_account!(challenger_account.id).current_balance > 100
    assert Economy.get_account!(opponent_account.id).current_balance == 100
  end

  test "fleeing an active duel forfeits the wager instead of cancelling it", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    active_duel = accept_duel(challenger, opponent)
    combat = Combat.get_combat!(active_duel.combat_id)
    defender_participant = Enum.find(combat.participants, &(&1.character_id == opponent.id))

    assert {:ok, _wait} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    {:ok, combat_view, _html} = live(session_conn(conn, challenger), ~p"/combat/#{combat.id}")
    combat_view |> element("#combat-flee") |> render_click()
    assert has_element?(combat_view, "#combat-flee-confirmation")
    combat_view |> element("#combat-flee-confirm") |> render_click()

    perform_all_actions_worker(active_duel.combat_id)

    resolved_duel = PVP.get_duel!(active_duel.id)
    assert resolved_duel.status == :resolved
    assert resolved_duel.winner_character_id == opponent.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    assert Economy.get_account!(challenger_account.id).current_balance == 100
    assert Economy.get_account!(opponent_account.id).current_balance > 100
  end

  defp accept_duel(challenger, opponent) do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 100)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)
    accepted_duel
  end

  defp perform_all_actions_worker(combat_id) do
    job =
      Oban.Job
      |> Repo.all()
      |> Enum.find(fn job ->
        job.worker == "MMGO.Combat.ResolveTurnWorker" and
          job.args["combat_id"] == combat_id and job.args["trigger"] == "all_actions"
      end)

    assert job
    assert :ok = MMGO.Combat.ResolveTurnWorker.perform(%Oban.Job{args: job.args})
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: active_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    active_grimoire
  end
end
