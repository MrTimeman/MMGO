defmodule MMGO.PlayTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Play
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Travel
  alias MMGO.Travel.Journey
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 220,
        safe_zone: false
      })

    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 20,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "travel_ration",
        name: "Travel Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "facade-mage", "Facade Mage")
    opponent = character_fixture(realm, city, "facade-rival", "Facade Rival")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    %{realm: realm, city: city, tower: tower, character: character, opponent: opponent}
  end

  test "load_demo_state/1 composes the current UI state", %{
    city: city,
    character: character
  } do
    assert {:ok, state} = Play.load_demo_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.id == city.id
    assert state.food_units == 20
    assert [%{destination_location: %{slug: "the-tower"}}] = state.routes
    assert state.active_journey == nil
    assert state.spells == []
    assert state.duel.active_duel == nil
    assert state.duel.pending_duels == []
  end

  test "start_journey/2 starts travel by destination slug and refreshes state", %{
    character: character,
    tower: tower
  } do
    assert {:ok, %{journey: journey, character: updated_character}} =
             Play.start_journey(character.id, "the-tower")

    assert journey.to_location_id == tower.id
    assert journey.to_location.slug == "the-tower"
    assert updated_character.id == character.id
    assert Travel.active_journey(character.id).id == journey.id

    assert {:ok, state} = Play.load_demo_state(character.id)
    assert state.active_journey.id == journey.id
    assert state.routes == []
  end

  test "travel_state/1 composes the journey and survival values for the web", %{
    character: character,
    tower: tower
  } do
    assert {:ok, %{journey: journey}} = Play.start_journey(character.id, "the-tower")

    assert {:ok, state} = Play.travel_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.slug == "capital-city"
    assert state.journey.id == journey.id
    assert state.journey.to_location.id == tower.id
    assert state.food_units < 20
    assert state.carried_weight > 0
    assert state.carry_capacity > state.carried_weight
  end

  test "inventory_state/1 composes carried items and capacity for the web", %{
    character: character
  } do
    assert {:ok, state} = Play.inventory_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.slug == "capital-city"
    assert [%{item_template: %{code: "travel_ration"}, quantity: 20}] = state.items
    assert Enum.all?(state.available_quantities, fn {_item_id, quantity} -> quantity >= 0 end)
    assert state.active_grimoire == nil
    assert state.food_units == 20
    assert state.carried_weight == 20
    assert state.carry_capacity > state.carried_weight
  end

  test "known_spells_and_duel_state/2 summarizes spells and duel state", %{
    character: character,
    opponent: opponent
  } do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        description: "A compiled fire sphere.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0}
        ],
        failure_profile: %{difficulty: 20, base_success_rate: 86, partial_success_rate: 8}
      })

    assert {:ok, pending_duel} = PVP.challenge_duel(character, opponent, 25)

    assert {:ok, summary} = Play.known_spells_and_duel_state(character.id, opponent.id)

    assert [%{id: spell_id}] = summary.spells
    assert spell_id == spell.id
    assert summary.duel.opponent.id == opponent.id
    assert [%{id: duel_id, status: :pending}] = summary.duel.pending_duels
    assert duel_id == pending_duel.id
  end

  test "the duel facade accepts the local opponent and only casts prepared spells", %{
    realm: realm,
    tower: tower,
    character: character,
    opponent: opponent
  } do
    character = move_to(character, tower)
    opponent = move_to(opponent, tower)
    {:ok, _character_funds} = Economy.grant_from_treasury(realm, character, 200)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 200)

    {:ok, spell} =
      Spells.create_spell(character, %{
        name: "Facade Ultima",
        formula: "Ignis Ultima Suprema",
        school: :fire,
        description: "A deterministic facade test spell.",
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

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Facade Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, %{activate_grimoire: _grimoire}} = Grimoires.activate_grimoire(character, grimoire)

    assert {:ok, state} = Play.start_demo_duel(character.id, opponent.id)
    assert state.duel.status == :active
    assert [%{id: spell_id}] = state.prepared_spells
    assert spell_id == spell.id

    assert {:error, :spell_not_prepared} =
             Play.cast_and_resolve_duel_turn(character.id, opponent.id)

    assert {:ok, resolved_state} = Play.cast_and_resolve_duel_turn(character.id, spell.id)
    assert resolved_state.duel.status == :resolved
    assert resolved_state.duel.winner_character_id == character.id
  end

  test "ensure_demo_character_usable/2 activates and stocks a demo character", %{
    city: city,
    character: character
  } do
    inactive =
      character
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: nil})
      |> Repo.update!()

    assert {:ok, usable} = Play.ensure_demo_character_usable(inactive.id, city)

    assert usable.status == :active
    assert usable.current_location_id == city.id
    assert usable.current_location.id == city.id
    assert MMGO.Survival.food_units_available(usable) >= 30
  end

  test "start_new_local_session/0 creates a character with the full starter kit", %{city: city} do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    assert character.status == :active
    assert character.realm_id == city.realm_id
    assert character.current_location_id == city.id
    assert opponent.current_location_id == city.id

    assert Repo.get_by!(EconomyAccount, character_id: character.id).current_balance == 1_000
    assert MMGO.Survival.food_units_available(character) >= 30

    inventory =
      character.id
      |> Inventory.list_inventory_for_character()
      |> Enum.map(& &1.item_template.code)

    assert "demo_travel_ration" in inventory
    assert "demo_lumen_dust" in inventory

    assert [%{name: "Ember Spark"}] = Spells.list_spells_for_character(character.id)
    assert %{status: :active} = Grimoires.active_grimoire_for_character(character.id)
  end

  test "continue_local_session/0 preserves local progress while reset rebuilds it", %{
    tower: tower
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()
    {:ok, %{journey: journey}} = Play.start_journey(character.id, "the-tower")
    {:ok, duel} = PVP.challenge_duel(character, opponent, 25)

    {:ok, account} = Economy.ensure_character_account(character)
    account |> EconomyAccount.changeset(%{current_balance: 2_500}) |> Repo.update!()

    assert {:ok, %{challenger: continued}} = Play.continue_local_session()
    assert continued.id == character.id
    assert Repo.get_by!(EconomyAccount, character_id: continued.id).current_balance == 2_500
    assert Travel.active_journey(continued.id).id == journey.id

    assert {:ok, %{challenger: reset}} = Play.reset_demo_session()
    assert reset.id == character.id
    assert reset.current_location_id != tower.id
    assert Travel.active_journey(reset.id) == nil
    assert Repo.get_by!(EconomyAccount, character_id: reset.id).current_balance == 1_000
    assert Repo.get!(Journey, journey.id).status == :cancelled
    assert PVP.get_duel!(duel.id).status == :cancelled
    assert PVP.pending_duels_for_character(reset.id) == []

    assert Repo.aggregate(
             from(item in InventoryItem, where: item.character_id == ^reset.id),
             :count
           ) >= 2

    assert [%{name: "Ember Spark"}] = Spells.list_spells_for_character(reset.id)
  end

  test "start_new_local_session/0 funds characters through a real treasury transfer", %{
    realm: realm
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    treasury = Economy.treasury_account_for_realm(realm.id)
    character_account = Repo.get_by!(EconomyAccount, character_id: character.id)
    opponent_account = Repo.get_by!(EconomyAccount, character_id: opponent.id)

    assert character_account.current_balance == 1_000
    assert opponent_account.current_balance == 1_000

    # Treasury supply must have actually decreased -- money moved, it wasn't
    # conjured out of nothing.
    assert treasury.current_balance == 100_000 - 1_000 - 1_000

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.debit_account_id == treasury.id and
               entry.credit_account_id == character_account.id and
               entry.amount == 1_000
           end)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.debit_account_id == treasury.id and
               entry.credit_account_id == opponent_account.id and
               entry.amount == 1_000
           end)
  end

  test "reset_demo_session/0 refunds an active duel's escrow instead of stranding it", %{
    realm: realm
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    {:ok, duel} = PVP.challenge_duel(character, opponent, 100)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

    escrow_account = Economy.get_account!(accepted_duel.escrow_account_id)
    assert escrow_account.current_balance == 200

    assert {:ok, _session} = Play.reset_demo_session()

    resolved_duel = PVP.get_duel!(duel.id)
    assert resolved_duel.status == :cancelled

    # The escrow must be drained back to the participants -- not left funded
    # forever with a cancelled duel sitting on top of it.
    refreshed_escrow = Economy.get_account!(accepted_duel.escrow_account_id)
    assert refreshed_escrow.current_balance == 0

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.count(ledger_entries, fn entry ->
             entry.debit_account_id == escrow_account.id and entry.amount == 100
           end) == 2
  end

  test "reset_demo_session/0 zeroes the balance through a real transfer back to treasury", %{
    realm: realm
  } do
    assert {:ok, %{challenger: character}} = Play.start_new_local_session()

    {:ok, account} = Economy.ensure_character_account(character)
    account |> EconomyAccount.changeset(%{current_balance: 2_500}) |> Repo.update!()

    treasury_before = Economy.treasury_account_for_realm(realm.id)

    assert {:ok, %{challenger: reset}} = Play.reset_demo_session()

    assert Repo.get_by!(EconomyAccount, character_id: reset.id).current_balance == 1_000

    treasury_after = Economy.treasury_account_for_realm(realm.id)

    # The 2_500 balance must have actually landed back in the treasury via a
    # transfer, not simply vanished via a bare balance write.
    assert treasury_after.current_balance == treasury_before.current_balance + 2_500 - 1_000

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.credit_account_id == treasury_after.id and entry.amount == 2_500
           end)
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

  defp move_to(character, location) do
    character
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
