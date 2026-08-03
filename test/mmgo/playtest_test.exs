defmodule MMGO.PlaytestTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Play
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    previous = Application.get_env(:mmgo, MMGO.CombatPlaytest)
    Application.put_env(:mmgo, MMGO.CombatPlaytest, unrestricted?: true)

    on_exit(fn ->
      if previous do
        Application.put_env(:mmgo, MMGO.CombatPlaytest, previous)
      else
        Application.delete_env(:mmgo, MMGO.CombatPlaytest)
      end
    end)

    {:ok, realm} =
      Worlds.create_realm(%{slug: "playtest", name: "Playtest Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, first_city} =
      Worlds.create_location(realm, %{
        slug: "first-playtest-city",
        name: "First Playtest City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, second_city} =
      Worlds.create_location(realm, %{
        slug: "second-playtest-city",
        name: "Second Playtest City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: "Playtest Road",
        origin_location_id: first_city.id,
        destination_location_id: second_city.id,
        travel_days: 2,
        risk_level: 0,
        bidirectional: true
      })

    {:ok, remote_realm} =
      Worlds.create_realm(%{slug: "remote-playtest", name: "Remote Playtest"})

    {:ok, remote_city} =
      Worlds.create_location(remote_realm, %{
        slug: "remote-playtest-city",
        name: "Remote Playtest City",
        kind: :city,
        x: 30,
        y: 30,
        safe_zone: true
      })

    caster = character_fixture(realm, first_city, "playtest-caster", "Playtest Caster")
    rival = character_fixture(remote_realm, remote_city, "playtest-rival", "Playtest Rival")

    %{caster: caster, rival: rival, second_city: second_city}
  end

  test "active characters can create trained spells from every school without Academy", %{
    caster: caster,
    second_city: second_city
  } do
    assert {:ok, %{journey: _journey}} = Play.start_journey(caster.id, second_city.slug)

    assert {:ok, state} = Play.spellbook_state(caster)
    assert state.composition_available?
    assert state.spell_circle_tier == :trained

    assert Enum.sort(state.permitted_schools) ==
             Enum.sort(~w(fire water earth air life death chaos order))

    assert {:ok, compiled_spell} =
             Play.compile_structured_spell(caster, %{
               "school" => "chaos",
               "actio" => "Misceo",
               "forma" => "Sphaera"
             })

    assert compiled_spell.school == :chaos
    assert compiled_spell.school_quirk == :volatility

    assert {:ok, %{attempt: attempt}} =
             Play.begin_spell_creation(caster, %{
               "school" => "death",
               "actio" => "Translatio",
               "forma" => "Vinculum"
             })

    assert attempt.character_id == caster.id
  end

  test "active characters can accept a free consensual duel across realms and locations", %{
    caster: caster,
    rival: rival
  } do
    assert {:ok, lobby} = Play.duel_lobby_state(caster)
    assert lobby.unrestricted_playtest?
    assert Enum.any?(lobby.opponents, &(&1.id == rival.id))

    assert {:ok, %{duel: pending_duel}} = Play.challenge_duel(caster, rival.id, 100)
    assert pending_duel.stake_amount == 0
    assert pending_duel.pot_amount == 0

    assert {:ok, %{duel: active_duel}} = Play.accept_duel(rival, pending_duel.id)
    assert active_duel.status == :active
    assert active_duel.combat_id

    escrow = Economy.get_account!(active_duel.escrow_account_id)
    assert escrow.current_balance == 0
    assert PVP.active_duel_for_character(caster.id).id == active_duel.id
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 1})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
