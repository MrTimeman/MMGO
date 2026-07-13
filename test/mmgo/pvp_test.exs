defmodule MMGO.PVPTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.Resolution, as: CombatResolution
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
        slug: "duel-tower",
        name: "Duel Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
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

  test "challenge_duel/4 rejects protected safe-zone duels", %{
    realm: realm,
    challenger: challenger
  } do
    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "protected-city",
        name: "Protected City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    protected_opponent = character_fixture(realm, city, "protected-rival", "Protected Rival")

    challenger
    |> Character.travel_changeset(%{current_location_id: city.id})
    |> Repo.update!()

    assert {:error, changeset} = PVP.challenge_duel(challenger, protected_opponent, 25)
    assert "duels cannot start in a safe zone" in errors_on(changeset).status
  end

  test "accept_duel/2 creates escrow and combat", %{
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 25)

    assert {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)
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

  test "accept_duel/2 rejects a non-opponent actor and moves no funds", %{
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 25)

    {:ok, challenger_account_before} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account_before} = Economy.ensure_character_account(opponent)

    location = Worlds.get_location!(challenger.current_location_id)
    bystander = character_fixture(realm, location, "bystander", "Bystander")
    {:ok, _bystander_funds} = Economy.grant_from_treasury(realm, bystander, 100)

    assert {:error, changeset} = PVP.accept_duel(duel, bystander)
    assert "only the challenged opponent can accept this duel" in errors_on(changeset).status

    assert {:error, challenger_changeset} = PVP.accept_duel(duel, challenger)

    assert "only the challenged opponent can accept this duel" in errors_on(challenger_changeset).status

    reloaded_duel = PVP.get_duel!(duel.id)
    assert reloaded_duel.status == :pending
    refute reloaded_duel.escrow_account_id
    refute reloaded_duel.combat_id

    assert Economy.get_account!(challenger_account_before.id).current_balance ==
             challenger_account_before.current_balance

    assert Economy.get_account!(opponent_account_before.id).current_balance ==
             opponent_account_before.current_balance
  end

  test "settle_duel_from_combat/1 pays the winner and taxes the pot", %{
    realm: realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 20)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

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

    # Re-fetch from the DB (not the struct settle_duel_from_combat handed
    # back) to prove the winner was actually persisted, not just reflected
    # on an in-memory struct that never made it into the UPDATE statement.
    assert PVP.get_duel!(duel.id).winner_character_id == challenger.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    treasury = Economy.treasury_account_for_realm(realm.id)
    escrow = Economy.get_account!(accepted_duel.escrow_account_id)

    assert Economy.get_account!(challenger_account.id).current_balance == 118
    assert Economy.get_account!(opponent_account.id).current_balance == 80
    assert Economy.get_account!(treasury.id).current_balance == 802
    assert escrow.current_balance == 0
  end

  test "Combat.Resolution.finalize/1 settles a finished duel without going through Telegram", %{
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 20)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

    combat =
      accepted_duel.combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "defenders",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    # This is the domain-layer hook that any caller (web LiveView, Telegram,
    # future API) is expected to call after MMGO.Combat.resolve_turn/1
    # returns a finished combat. It must settle the wager on its own —
    # nothing here touches MMGO.PVP or the Telegram dispatcher directly.
    assert {:ok, resolved_duel} = CombatResolution.finalize(combat)
    assert resolved_duel.status == :resolved
    assert resolved_duel.winner_character_id == opponent.id

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    escrow = Economy.get_account!(accepted_duel.escrow_account_id)

    assert Economy.get_account!(challenger_account.id).current_balance == 80
    assert Economy.get_account!(opponent_account.id).current_balance == 118
    assert escrow.current_balance == 0

    # Reflects the previously-broken web path: a duel accepted (escrow
    # funded, combat created) is not stuck forever once its combat finishes,
    # because settlement no longer lives only inside the Telegram dispatcher.
    # Re-fetching fresh from the DB (rather than reusing resolved_duel) also
    # proves the winner was actually persisted, not just present on an
    # in-memory struct that never reached the database.
    reloaded_duel = PVP.get_duel!(duel.id)
    assert reloaded_duel.status == :resolved
    assert reloaded_duel.winner_character_id == opponent.id
  end

  test "Combat.Resolution.finalize/1 is a no-op for a duel combat that has not finished", %{
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 20)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

    assert {:ok, :no_op} = CombatResolution.finalize(accepted_duel.combat)

    unchanged_duel = PVP.get_duel!(duel.id)
    assert unchanged_duel.status == :active
  end

  test "cancel_duel/2 rejects an active duel so its wager cannot be refunded", %{
    realm: _realm,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, duel} = PVP.challenge_duel(challenger, opponent, 15)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

    assert {:error, changeset} = PVP.cancel_duel(accepted_duel, challenger)
    assert "active duels must be resolved through combat or flee" in errors_on(changeset).status

    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)
    escrow = Economy.get_account!(accepted_duel.escrow_account_id)

    assert Economy.get_account!(challenger_account.id).current_balance == 85
    assert Economy.get_account!(opponent_account.id).current_balance == 85
    assert escrow.current_balance == 30
    assert PVP.get_duel!(duel.id).status == :active
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
