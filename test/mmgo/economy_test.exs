defmodule MMGO.EconomyTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Economy.{EconomyAccount, LedgerEntry}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    sender = character_fixture(realm, "economy-sender", "Economy Sender")
    receiver = character_fixture(realm, "economy-receiver", "Economy Receiver")

    %{realm: realm, sender: sender, receiver: receiver}
  end

  test "create_treasury_account/2 seeds the initial money supply into the treasury", %{
    realm: realm
  } do
    assert {:ok, treasury_account} = Economy.create_treasury_account(realm, 1_000)

    assert treasury_account.owner_type == :treasury
    assert treasury_account.current_balance == 1_000

    seed_entry = Repo.one!(LedgerEntry)
    assert seed_entry.entry_type == :realm_seed
    assert seed_entry.amount == 1_000
    assert seed_entry.credit_account_id == treasury_account.id
  end

  test "grant_from_treasury/4 and transfer/4 move balances through append-only entries", %{
    realm: realm,
    sender: sender,
    receiver: receiver
  } do
    {:ok, treasury_account} = Economy.ensure_treasury_account(realm, 1_000)
    {:ok, sender_account} = Economy.ensure_character_account(sender)
    {:ok, receiver_account} = Economy.ensure_character_account(receiver)

    assert {:ok, %{ledger_entries: [grant_entry]}} =
             Economy.grant_from_treasury(realm, sender, 150)

    assert grant_entry.entry_type == :transfer

    assert {:ok, %{ledger_entries: [transfer_entry]}} =
             Economy.transfer(sender_account, receiver_account, 40, %{entry_type: "purchase"})

    assert transfer_entry.entry_type == :purchase
    assert Economy.get_account!(treasury_account.id).current_balance == 850
    assert Economy.get_account!(sender_account.id).current_balance == 110
    assert Economy.get_account!(receiver_account.id).current_balance == 40

    assert Repo.aggregate(LedgerEntry, :count, :id) == 3
    assert balance_sum(realm.id) == 1_000
  end

  test "taxed_transfer/5 splits tax back to the treasury", %{
    realm: realm,
    sender: sender,
    receiver: receiver
  } do
    {:ok, treasury_account} = Economy.ensure_treasury_account(realm, 1_000)
    {:ok, sender_account} = Economy.ensure_character_account(sender)
    {:ok, receiver_account} = Economy.ensure_character_account(receiver)
    {:ok, _grant_result} = Economy.grant_from_treasury(realm, sender, 100)

    assert {:ok, %{ledger_entries: ledger_entries, treasury_account: updated_treasury}} =
             Economy.taxed_transfer(sender_account, receiver_account, 25, 1_000, %{
               reason: "market_tax"
             })

    assert Enum.map(ledger_entries, & &1.entry_type) == [:transfer, :tax]
    assert Economy.get_account!(sender_account.id).current_balance == 75
    assert Economy.get_account!(receiver_account.id).current_balance == 23
    assert updated_treasury.id == treasury_account.id
    assert Economy.get_account!(treasury_account.id).current_balance == 902
    assert balance_sum(realm.id) == 1_000
  end

  test "transfer/4 rejects overdrafts", %{realm: realm, sender: sender, receiver: receiver} do
    {:ok, _treasury_account} = Economy.ensure_treasury_account(realm, 1_000)
    {:ok, sender_account} = Economy.ensure_character_account(sender)
    {:ok, receiver_account} = Economy.ensure_character_account(receiver)

    assert {:error, changeset} = Economy.transfer(sender_account, receiver_account, 10)
    assert %{current_balance: ["is insufficient for this transfer"]} = errors_on(changeset)
    assert balance_sum(realm.id) == 1_000
  end

  test "taxed_transfer/5 rejects invalid tax rates", %{
    realm: realm,
    sender: sender,
    receiver: receiver
  } do
    {:ok, _treasury_account} = Economy.ensure_treasury_account(realm, 500)
    {:ok, sender_account} = Economy.ensure_character_account(sender)
    {:ok, receiver_account} = Economy.ensure_character_account(receiver)

    assert {:error, changeset} =
             Economy.taxed_transfer(sender_account, receiver_account, 10, 20_000)

    assert %{metadata: ["tax rate must be between 0 and 10000 basis points"]} =
             errors_on(changeset)
  end

  defp balance_sum(realm_id) do
    EconomyAccount
    |> Ecto.Query.where([account], account.realm_id == ^realm_id)
    |> Repo.aggregate(:sum, :current_balance)
    |> Decimal.to_integer()
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
  end
end
