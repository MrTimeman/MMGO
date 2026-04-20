defmodule MMGO.Economy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias MMGO.Accounts.Character
  alias MMGO.Economy.{EconomyAccount, LedgerEntry}
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def list_accounts_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from account in EconomyAccount,
        where: account.realm_id == ^realm_id,
        order_by: [asc: account.inserted_at]
    )
  end

  def list_ledger_entries_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from entry in LedgerEntry,
        where: entry.realm_id == ^realm_id,
        order_by: [asc: entry.inserted_at, asc: entry.id]
    )
  end

  def get_account!(id), do: Repo.get!(EconomyAccount, id)

  def treasury_account_for_realm(realm_id) when is_binary(realm_id) do
    Repo.get_by(EconomyAccount, realm_id: realm_id, owner_type: :treasury)
  end

  def ensure_treasury_account(%Realm{} = realm, initial_supply \\ 0) do
    case treasury_account_for_realm(realm.id) do
      %EconomyAccount{} = account -> {:ok, account}
      nil -> create_treasury_account(realm, initial_supply)
    end
  end

  def create_treasury_account(%Realm{} = realm, initial_supply) when is_integer(initial_supply) do
    if initial_supply < 0 do
      {:error, invalid_amount_changeset("must be greater than or equal to zero")}
    else
      Multi.new()
      |> Multi.insert(
        :treasury_account,
        EconomyAccount.changeset(%EconomyAccount{}, %{
          realm_id: realm.id,
          owner_type: :treasury,
          current_balance: initial_supply,
          metadata: %{"system" => "treasury"}
        })
      )
      |> maybe_insert_realm_seed(initial_supply, realm.id)
      |> Repo.transaction()
      |> case do
        {:ok, %{treasury_account: treasury_account}} -> {:ok, treasury_account}
        {:error, _step, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  def ensure_character_account(%Character{} = character) do
    case Repo.get_by(EconomyAccount, character_id: character.id, owner_type: :character) do
      %EconomyAccount{} = account ->
        {:ok, account}

      nil ->
        %EconomyAccount{}
        |> EconomyAccount.changeset(%{
          realm_id: character.realm_id,
          owner_type: :character,
          character_id: character.id,
          current_balance: 0
        })
        |> Repo.insert()
        |> case do
          {:ok, account} -> {:ok, account}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def create_escrow_account(%Realm{} = realm, metadata \\ %{}) do
    %EconomyAccount{}
    |> EconomyAccount.changeset(%{
      realm_id: realm.id,
      owner_type: :escrow,
      current_balance: 0,
      metadata: normalize_metadata(metadata)
    })
    |> Repo.insert()
  end

  def transfer(
        %EconomyAccount{} = debit_account,
        %EconomyAccount{} = credit_account,
        amount,
        attrs \\ %{}
      )
      when is_integer(amount) do
    attrs = normalize_metadata(attrs)

    with :ok <- validate_transfer_pair(debit_account, credit_account),
         :ok <- validate_amount(amount) do
      Repo.transaction(fn ->
        accounts = lock_accounts!([debit_account.id, credit_account.id])
        debit_account = Map.fetch!(accounts, debit_account.id)
        credit_account = Map.fetch!(accounts, credit_account.id)

        if debit_account.current_balance < amount do
          Repo.rollback(insufficient_funds_changeset())
        end

        ledger_entry =
          %LedgerEntry{}
          |> LedgerEntry.changeset(%{
            realm_id: debit_account.realm_id,
            entry_type: entry_type_from_attrs(attrs, :transfer),
            amount: amount,
            debit_account_id: debit_account.id,
            credit_account_id: credit_account.id,
            metadata: attrs
          })
          |> Repo.insert!()

        updated_debit =
          debit_account
          |> EconomyAccount.changeset(%{current_balance: debit_account.current_balance - amount})
          |> Repo.update!()

        updated_credit =
          credit_account
          |> EconomyAccount.changeset(%{current_balance: credit_account.current_balance + amount})
          |> Repo.update!()

        %{
          ledger_entries: [ledger_entry],
          debit_account: updated_debit,
          credit_account: updated_credit
        }
      end)
      |> normalize_transaction_result()
    end
  end

  def taxed_transfer(
        %EconomyAccount{} = payer_account,
        %EconomyAccount{} = receiver_account,
        amount,
        tax_rate_bps,
        attrs \\ %{}
      )
      when is_integer(amount) and is_integer(tax_rate_bps) do
    attrs = normalize_metadata(attrs)

    with :ok <- validate_transfer_pair(payer_account, receiver_account),
         :ok <- validate_amount(amount),
         :ok <- validate_tax_rate(tax_rate_bps),
         %EconomyAccount{} = treasury_account <-
           treasury_account_for_realm(payer_account.realm_id),
         :ok <- validate_treasury_realm(treasury_account, payer_account) do
      tax_amount = div(amount * tax_rate_bps, 10_000)
      net_amount = amount - tax_amount

      Repo.transaction(fn ->
        accounts = lock_accounts!([payer_account.id, receiver_account.id, treasury_account.id])
        payer_account = Map.fetch!(accounts, payer_account.id)
        receiver_account = Map.fetch!(accounts, receiver_account.id)
        treasury_account = Map.fetch!(accounts, treasury_account.id)

        if payer_account.current_balance < amount do
          Repo.rollback(insufficient_funds_changeset())
        end

        ledger_entries =
          []
          |> maybe_add_entry(net_amount, fn ->
            %LedgerEntry{}
            |> LedgerEntry.changeset(%{
              realm_id: payer_account.realm_id,
              entry_type: :transfer,
              amount: net_amount,
              debit_account_id: payer_account.id,
              credit_account_id: receiver_account.id,
              metadata: attrs
            })
            |> Repo.insert!()
          end)
          |> maybe_add_entry(tax_amount, fn ->
            %LedgerEntry{}
            |> LedgerEntry.changeset(%{
              realm_id: payer_account.realm_id,
              entry_type: :tax,
              amount: tax_amount,
              debit_account_id: payer_account.id,
              credit_account_id: treasury_account.id,
              metadata: Map.put(attrs, "tax_rate_bps", tax_rate_bps)
            })
            |> Repo.insert!()
          end)
          |> Enum.reverse()

        updated_payer =
          payer_account
          |> EconomyAccount.changeset(%{current_balance: payer_account.current_balance - amount})
          |> Repo.update!()

        {updated_receiver, updated_treasury} =
          if receiver_account.id == treasury_account.id do
            updated_account =
              receiver_account
              |> EconomyAccount.changeset(%{
                current_balance: receiver_account.current_balance + net_amount + tax_amount
              })
              |> Repo.update!()

            {updated_account, updated_account}
          else
            updated_receiver =
              receiver_account
              |> EconomyAccount.changeset(%{
                current_balance: receiver_account.current_balance + net_amount
              })
              |> Repo.update!()

            updated_treasury =
              treasury_account
              |> EconomyAccount.changeset(%{
                current_balance: treasury_account.current_balance + tax_amount
              })
              |> Repo.update!()

            {updated_receiver, updated_treasury}
          end

        %{
          ledger_entries: ledger_entries,
          debit_account: updated_payer,
          credit_account: updated_receiver,
          treasury_account: updated_treasury
        }
      end)
      |> normalize_transaction_result()
    else
      nil -> {:error, treasury_missing_changeset()}
      {:error, _reason} = error -> error
      :ok -> {:error, treasury_missing_changeset()}
    end
  end

  def grant_from_treasury(%Realm{} = realm, %Character{} = character, amount, attrs \\ %{})
      when is_integer(amount) do
    with %EconomyAccount{} = treasury_account <- treasury_account_for_realm(realm.id),
         {:ok, receiver_account} <- ensure_character_account(character) do
      transfer(
        treasury_account,
        receiver_account,
        amount,
        Map.put(normalize_metadata(attrs), "realm_id", realm.id)
      )
    else
      nil -> {:error, treasury_missing_changeset()}
      error -> error
    end
  end

  def change_account(%EconomyAccount{} = account, attrs \\ %{}) do
    EconomyAccount.changeset(account, attrs)
  end

  defp maybe_insert_realm_seed(multi, 0, _realm_id), do: multi

  defp maybe_insert_realm_seed(multi, initial_supply, realm_id) do
    Multi.insert(multi, :seed_entry, fn %{treasury_account: treasury_account} ->
      LedgerEntry.changeset(%LedgerEntry{}, %{
        realm_id: realm_id,
        entry_type: :realm_seed,
        amount: initial_supply,
        credit_account_id: treasury_account.id,
        metadata: %{"reason" => "realm_initial_money_supply"}
      })
    end)
  end

  defp validate_transfer_pair(%EconomyAccount{id: debit_id}, %EconomyAccount{id: credit_id})
       when debit_id == credit_id do
    {:error, same_account_changeset()}
  end

  defp validate_transfer_pair(%EconomyAccount{realm_id: debit_realm}, %EconomyAccount{
         realm_id: credit_realm
       })
       when debit_realm != credit_realm do
    {:error, cross_realm_changeset()}
  end

  defp validate_transfer_pair(_debit_account, _credit_account), do: :ok

  defp validate_amount(amount) when amount > 0, do: :ok

  defp validate_amount(_amount),
    do: {:error, invalid_amount_changeset("must be greater than zero")}

  defp validate_tax_rate(tax_rate_bps) when tax_rate_bps in 0..10_000, do: :ok
  defp validate_tax_rate(_tax_rate_bps), do: {:error, invalid_tax_rate_changeset()}

  defp validate_treasury_realm(%EconomyAccount{realm_id: treasury_realm_id}, %EconomyAccount{
         realm_id: realm_id
       })
       when treasury_realm_id == realm_id,
       do: :ok

  defp validate_treasury_realm(_treasury_account, _payer_account),
    do: {:error, treasury_missing_changeset()}

  defp lock_accounts!(account_ids) do
    account_ids = Enum.uniq(account_ids)

    accounts =
      EconomyAccount
      |> where([account], account.id in ^account_ids)
      |> order_by([account], asc: account.id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    if length(accounts) != length(account_ids) do
      Repo.rollback(missing_account_changeset())
    end

    Map.new(accounts, &{&1.id, &1})
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp maybe_add_entry(entries, 0, _builder), do: entries
  defp maybe_add_entry(entries, _amount, builder), do: [builder.() | entries]

  defp entry_type_from_attrs(attrs, fallback) do
    attrs["entry_type"] || Atom.to_string(fallback)
  end

  defp normalize_metadata(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp insufficient_funds_changeset do
    %EconomyAccount{}
    |> Changeset.change()
    |> Changeset.add_error(:current_balance, "is insufficient for this transfer")
  end

  defp invalid_amount_changeset(message) do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:amount, message)
  end

  defp invalid_tax_rate_changeset do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:metadata, "tax rate must be between 0 and 10000 basis points")
  end

  defp same_account_changeset do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:credit_account_id, "must differ from the debit account")
  end

  defp cross_realm_changeset do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:credit_account_id, "must belong to the same realm")
  end

  defp missing_account_changeset do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:debit_account_id, "referenced account could not be found")
  end

  defp treasury_missing_changeset do
    %LedgerEntry{}
    |> Changeset.change()
    |> Changeset.add_error(:credit_account_id, "treasury account is missing for this realm")
  end
end
