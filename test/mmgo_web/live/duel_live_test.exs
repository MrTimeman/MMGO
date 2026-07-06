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

    # A "tower" location so combat magic isn't suppressed by the default
    # ruleset (magic_scope: "tower_and_dungeon") — a plain city would block
    # spellcasting entirely and the duel combat could never finish.
    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "duel-tower",
        name: "Duel Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    challenger = character_fixture(realm, location, "challenger", "Challenger")
    opponent = character_fixture(realm, location, "opponent", "Opponent")
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

  test "a challenger outside the Tower is redirected to the map with an in-world flash", %{
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

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:demo_character_id, challenger.id)

    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} = live(conn, ~p"/pvp")
    assert flash["error"] =~ "Magic only works at the Tower"
  end

  test "accepting a duel on the web can be resolved to settle the wager, no Telegram involved",
       %{conn: conn, challenger: challenger, opponent: opponent, killing_blow: killing_blow} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:demo_character_id, challenger.id)
      |> Plug.Conn.put_session(:demo_opponent_id, opponent.id)

    {:ok, view, _html} = live(conn, ~p"/pvp")

    view |> element("button", "Challenge #{opponent.name}") |> render_click()

    duel =
      PVP.get_duel!(PVP.pending_duels_for_character(challenger.id) |> hd() |> Map.fetch!(:id))

    assert duel.status == :pending

    # Simulates the opponent accepting from their own session — the escrow
    # funding and combat creation is identical to what duel_live's own
    # "duel_accept" event triggers.
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)
    assert accepted_duel.status == :active
    assert accepted_duel.combat_id

    # Before this fix, there was no way to get from here (escrow funded,
    # combat active) to a settled duel except through the Telegram bot.
    # Remount so the LiveView's assigns reflect the now-active duel.
    {:ok, view, _html} = live(conn, ~p"/pvp")
    assert has_element?(view, "button", "Resolve Combat Turn")

    combat = Combat.get_combat!(accepted_duel.combat_id)
    challenger_participant = Enum.find(combat.participants, &(&1.character_id == challenger.id))

    assert {:ok, _turn} =
             Combat.submit_action(combat, challenger_participant.id, %{
               action_type: :cast_spell,
               spell_id: killing_blow.id,
               target_side: "defenders"
             })

    view
    |> element("button", "Resolve Combat Turn")
    |> render_click()

    # Read the duel back fresh from the DB (not the socket's cached assign)
    # to prove the win was actually persisted, not just reflected in an
    # in-memory struct.
    resolved_duel = PVP.get_duel!(accepted_duel.id)
    assert resolved_duel.status == :resolved
    assert resolved_duel.winner_character_id == challenger.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)

    # duel_live's "challenge_bot" stakes 100 gold each side (200 pot, taxed).
    # The challenger wins: their balance ends up above their post-stake floor
    # of 100, while the opponent's 100 stake is gone for good.
    assert Economy.get_account!(challenger_account.id).current_balance > 100
    assert Economy.get_account!(opponent_account.id).current_balance == 100
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
