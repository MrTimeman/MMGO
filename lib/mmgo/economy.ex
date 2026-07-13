defmodule MMGO.Economy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias MMGO.Accounts.Character
  alias MMGO.Economy.{EconomyAccount, LedgerEntry}
  alias MMGO.Organizations.Organization
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  @public_organization_activity_entry_limit 250

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

  @doc """
  Returns a public, bounded activity score for organization treasuries in one
  realm. The result deliberately contains no balances or amounts: the map may
  show that a linked organization is economically active without exposing its
  private treasury.
  """
  def public_organization_activity_for_realm(realm_id) when is_binary(realm_id) do
    LedgerEntry
    |> where([entry], entry.realm_id == ^realm_id)
    |> order_by([entry], desc: entry.inserted_at, desc: entry.id)
    |> limit(^@public_organization_activity_entry_limit)
    |> Repo.all()
    |> Enum.reduce(%{}, fn entry, activity ->
      case organization_id_from_ledger_entry(entry) do
        organization_id when is_binary(organization_id) ->
          Map.update(activity, organization_id, 1, &(&1 + 1))

        _other ->
          activity
      end
    end)
  end

  def public_organization_activity_for_realm(_realm_id), do: %{}

  @doc "Lists the append-only entries that debit or credit one account."
  def list_ledger_entries_for_account(account_id) when is_binary(account_id) do
    Repo.all(
      from entry in LedgerEntry,
        where: entry.debit_account_id == ^account_id or entry.credit_account_id == ^account_id,
        order_by: [desc: entry.inserted_at, desc: entry.id]
    )
  end

  def get_account!(id), do: Repo.get!(EconomyAccount, id)

  def treasury_account_for_realm(realm_id) when is_binary(realm_id) do
    Repo.get_by(EconomyAccount, realm_id: realm_id, owner_type: :treasury)
  end

  @doc "Returns the realm-local charity fund account, if the fund has been opened."
  def charity_fund_account_for_realm(realm_id) when is_binary(realm_id) do
    Repo.get_by(EconomyAccount, realm_id: realm_id, owner_type: :charity_fund)
  end

  def charity_fund_account_for_realm(_realm_id), do: nil

  def ensure_treasury_account(%Realm{} = realm, initial_supply \\ 0) do
    case treasury_account_for_realm(realm.id) do
      %EconomyAccount{} = account -> {:ok, account}
      nil -> create_treasury_account(realm, initial_supply)
    end
  end

  @doc "Ensures one durable charity fund account exists for a realm."
  def ensure_charity_fund_account(%Realm{} = realm) do
    Repo.transaction(fn ->
      _realm = lock_realm!(realm.id)

      case charity_fund_account_for_realm(realm.id) do
        %EconomyAccount{} = account ->
          account

        nil ->
          %EconomyAccount{}
          |> EconomyAccount.changeset(%{
            realm_id: realm.id,
            owner_type: :charity_fund,
            current_balance: 0,
            metadata: %{"system" => "charity_fund"}
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
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

  @doc """
  Returns the durable treasury account for one organization.

  Organization accounts use the existing closed-ledger table rather than a
  browser-side balance. The organization context serializes creation by
  locking the organization row before calling `ensure_organization_account/1`.
  """
  def organization_account_for_organization(%Organization{} = organization) do
    EconomyAccount
    |> where(
      [account],
      account.realm_id == ^organization.realm_id and account.owner_type == :organization
    )
    |> Repo.all()
    |> Enum.find(fn account ->
      Map.get(account.metadata || %{}, "organization_id") == organization.id
    end)
  end

  def organization_account_for_organization(_organization), do: nil

  @doc """
  Ensures a zero-balance account exists for an organization treasury.

  Callers that can create accounts must hold the organization row lock first;
  this makes the metadata-backed owner reference safe without a new schema
  migration.
  """
  def ensure_organization_account(%Organization{} = organization) do
    case organization_account_for_organization(organization) do
      %EconomyAccount{} = account ->
        {:ok, account}

      nil ->
        %EconomyAccount{}
        |> EconomyAccount.changeset(%{
          realm_id: organization.realm_id,
          owner_type: :organization,
          current_balance: 0,
          metadata: %{
            "system" => "organization_treasury",
            "organization_id" => organization.id
          }
        })
        |> Repo.insert()
    end
  end

  def ensure_organization_account(_organization), do: {:error, missing_account_changeset()}

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

  @doc """
  Atomically transfers one account's balance to distinct same-realm recipients.

  Each transfer is a map with `:credit_account`, `:amount`, and optional
  `:metadata`. The debit account is locked once and all credits are locked in a
  stable order, so a collective payout cannot leave a partial split behind.
  """
  def transfer_many(debit_account, transfers, attrs \\ %{})

  def transfer_many(%EconomyAccount{} = debit_account, transfers, attrs)
      when is_list(transfers) and is_map(attrs) do
    attrs = normalize_metadata(attrs)

    with {:ok, transfers} <- normalize_many_transfers(debit_account, transfers) do
      total_amount = transfers |> Enum.map(& &1.amount) |> Enum.sum()

      Repo.transaction(fn ->
        account_ids = [debit_account.id | Enum.map(transfers, & &1.credit_account.id)]
        accounts = lock_accounts!(account_ids)
        debit_account = Map.fetch!(accounts, debit_account.id)

        if debit_account.current_balance < total_amount do
          Repo.rollback(insufficient_funds_changeset())
        end

        ledger_entries =
          Enum.map(transfers, fn transfer ->
            credit_account = Map.fetch!(accounts, transfer.credit_account.id)

            %LedgerEntry{}
            |> LedgerEntry.changeset(%{
              realm_id: debit_account.realm_id,
              entry_type: entry_type_from_attrs(attrs, :transfer),
              amount: transfer.amount,
              debit_account_id: debit_account.id,
              credit_account_id: credit_account.id,
              metadata: Map.merge(attrs, transfer.metadata)
            })
            |> Repo.insert!()
          end)

        updated_debit =
          debit_account
          |> EconomyAccount.changeset(%{
            current_balance: debit_account.current_balance - total_amount
          })
          |> Repo.update!()

        updated_credit_accounts =
          Enum.map(transfers, fn transfer ->
            credit_account = Map.fetch!(accounts, transfer.credit_account.id)

            credit_account
            |> EconomyAccount.changeset(%{
              current_balance: credit_account.current_balance + transfer.amount
            })
            |> Repo.update!()
          end)

        %{
          ledger_entries: ledger_entries,
          debit_account: updated_debit,
          credit_accounts: updated_credit_accounts
        }
      end)
      |> normalize_transaction_result()
    end
  end

  def transfer_many(_debit_account, _transfers, _attrs), do: {:error, missing_account_changeset()}

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

  defp normalize_many_transfers(%EconomyAccount{} = debit_account, transfers) do
    case Enum.reduce_while(transfers, {:ok, []}, fn
           %{credit_account: %EconomyAccount{} = credit_account, amount: amount} = transfer,
           {:ok, normalized}
           when is_integer(amount) ->
             with :ok <- validate_transfer_pair(debit_account, credit_account),
                  :ok <- validate_amount(amount) do
               metadata =
                 case Map.get(transfer, :metadata, %{}) do
                   value when is_map(value) -> normalize_metadata(value)
                   _other -> %{}
                 end

               {:cont,
                {:ok,
                 [
                   %{credit_account: credit_account, amount: amount, metadata: metadata}
                   | normalized
                 ]}}
             else
               {:error, _reason} = error -> {:halt, error}
             end

           _transfer, _normalized ->
             {:halt, {:error, invalid_amount_changeset("recipient transfers are invalid")}}
         end) do
      {:ok, []} ->
        {:error, invalid_amount_changeset("at least one recipient is required")}

      {:ok, normalized} ->
        transfers = Enum.reverse(normalized)
        credit_account_ids = Enum.map(transfers, & &1.credit_account.id)

        if length(credit_account_ids) == length(Enum.uniq(credit_account_ids)) do
          {:ok, transfers}
        else
          {:error, invalid_amount_changeset("recipient accounts must be distinct")}
        end

      {:error, _reason} = error ->
        error
    end
  end

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

  defp lock_realm!(realm_id) do
    Realm
    |> where([realm], realm.id == ^realm_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
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

  defp organization_id_from_ledger_entry(%LedgerEntry{metadata: metadata})
       when is_map(metadata) do
    case Map.get(metadata, "organization_id") do
      organization_id when is_binary(organization_id) -> organization_id
      _other -> nil
    end
  end

  defp organization_id_from_ledger_entry(_entry), do: nil

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
