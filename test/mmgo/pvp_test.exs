defmodule MMGO.PVPTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Economy
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "duel-yard",
        name: "Duel Yard",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    challenger = character_fixture(realm, location, "challenger", "Challenger")
    opponent = character_fixture(realm, location, "opponent", "Opponent")
    {:ok, _challenger_funds} = Economy.grant_from_treasury(realm, challenger, 100)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 100)

    %{realm: realm, challenger: challenger, opponent: opponent}
  end

  test "challenge_duel/4 creates a pending wagered duel", %{
    challenger: challenger,
    opponent: opponent
  } do
    assert {:ok, duel} = PVP.challenge_duel(challenger, opponent, 25)

    assert duel.status == :pending
    assert duel.stake_amount == 25
    assert duel.pot_amount == 50
  end

  test "accept_duel/1 creates escrow and combat", %{
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 25)

    assert {:ok, accepted_duel} = PVP.accept_duel(duel)
    assert accepted_duel.status == :active
    assert accepted_duel.combat_id
    assert accepted_duel.escrow_account_id

    escrow = Economy.get_account!(accepted_duel.escrow_account_id)
    assert escrow.owner_type == :escrow
    assert escrow.current_balance == 50
    assert %CombatSchema{} = Repo.get!(CombatSchema, accepted_duel.combat_id)

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    assert Economy.get_account!(challenger_account.id).current_balance == 75
    assert Economy.get_account!(opponent_account.id).current_balance == 75
    assert Economy.treasury_account_for_realm(realm.id).current_balance == 800
  end

  test "settle_duel_from_combat/1 pays the winner and taxes the pot", %{
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 20)
    {:ok, accepted_duel} = PVP.accept_duel(duel)

    combat =
      accepted_duel.combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "attackers",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, resolved_duel} = PVP.settle_duel_from_combat(combat)
    assert resolved_duel.status == :resolved
    assert resolved_duel.winner_character_id == challenger.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    treasury = Economy.treasury_account_for_realm(realm.id)
    escrow = Economy.get_account!(accepted_duel.escrow_account_id)

    assert Economy.get_account!(challenger_account.id).current_balance == 118
    assert Economy.get_account!(opponent_account.id).current_balance == 80
    assert Economy.get_account!(treasury.id).current_balance == 802
    assert escrow.current_balance == 0
    assert Repo.get!(Character, challenger.id).xp == 30
    assert Repo.get!(Character, opponent.id).xp == 20
  end

  test "cancel_duel/2 refunds active duel escrow", %{
    realm: _realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 15)
    {:ok, accepted_duel} = PVP.accept_duel(duel)

    assert {:ok, cancelled_duel} = PVP.cancel_duel(accepted_duel, challenger)
    assert cancelled_duel.status == :cancelled

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    escrow = Economy.get_account!(accepted_duel.escrow_account_id)

    assert Economy.get_account!(challenger_account.id).current_balance == 100
    assert Economy.get_account!(opponent_account.id).current_balance == 100
    assert escrow.current_balance == 0
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
end
