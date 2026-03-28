defmodule MMGO.Federation do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Federation.{ExchangeRate, Migration}
  alias MMGO.Notifications
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  def list_discoverable_realms(origin_realm_id \\ nil) do
    Realm
    |> where([realm], realm.status == :active and realm.allow_migration == true)
    |> maybe_exclude_realm(origin_realm_id)
    |> order_by([realm], asc: realm.inserted_at)
    |> Repo.all()
  end

  def list_exchange_rates_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from exchange_rate in ExchangeRate,
        where:
          exchange_rate.source_realm_id == ^realm_id or
            exchange_rate.destination_realm_id == ^realm_id,
        order_by: [asc: exchange_rate.inserted_at],
        preload: [:source_realm, :destination_realm]
    )
  end

  def get_exchange_rate(source_realm_id, destination_realm_id)
      when is_binary(source_realm_id) and is_binary(destination_realm_id) do
    ExchangeRate
    |> Repo.get_by(
      source_realm_id: source_realm_id,
      destination_realm_id: destination_realm_id,
      status: :active
    )
    |> case do
      nil -> nil
      exchange_rate -> Repo.preload(exchange_rate, [:source_realm, :destination_realm])
    end
  end

  def quote_exchange(source_realm_id, destination_realm_id, amount)
      when is_binary(source_realm_id) and is_binary(destination_realm_id) and is_integer(amount) do
    cond do
      amount <= 0 ->
        {:error, migration_changeset("amount must be greater than zero")}

      true ->
        with %ExchangeRate{} = exchange_rate <-
               get_exchange_rate(source_realm_id, destination_realm_id) do
          converted_amount = div(amount * exchange_rate.numerator, exchange_rate.denominator)

          {:ok,
           %{
             exchange_rate: exchange_rate,
             source_amount: amount,
             converted_amount: converted_amount
           }}
        else
          nil ->
            {:error, migration_changeset("no active exchange rate exists between these realms")}
        end
    end
  end

  def set_exchange_rate(%Realm{} = source_realm, %Realm{} = destination_realm, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    numerator = attrs["numerator"] || 1
    denominator = attrs["denominator"] || 1

    cond do
      source_realm.id == destination_realm.id ->
        {:error, migration_changeset("source and destination realms must differ")}

      numerator <= 0 or denominator <= 0 ->
        {:error, migration_changeset("exchange rates must be positive")}

      true ->
        case Repo.get_by(ExchangeRate,
               source_realm_id: source_realm.id,
               destination_realm_id: destination_realm.id
             ) do
          nil ->
            %ExchangeRate{}
            |> ExchangeRate.changeset(%{
              source_realm_id: source_realm.id,
              destination_realm_id: destination_realm.id,
              numerator: numerator,
              denominator: denominator,
              status: :active,
              metadata: attrs["metadata"] || %{}
            })
            |> Repo.insert()

          %ExchangeRate{} = exchange_rate ->
            exchange_rate
            |> ExchangeRate.changeset(%{
              numerator: numerator,
              denominator: denominator,
              status: :active,
              metadata: attrs["metadata"] || %{}
            })
            |> Repo.update()
        end
    end
  end

  def list_migrations_for_account(account_id) when is_binary(account_id) do
    Repo.all(
      from migration in Migration,
        where: migration.account_id == ^account_id,
        order_by: [desc: migration.inserted_at],
        preload: [:origin_realm, :destination_realm, :origin_character, :destination_character]
    )
  end

  def active_migration_for_character(character_id) when is_binary(character_id) do
    Repo.get_by(Migration, origin_character_id: character_id, status: :active)
  end

  def get_migration!(id) do
    Migration
    |> Repo.get!(id)
    |> Repo.preload([
      :origin_realm,
      :destination_realm,
      :origin_character,
      :destination_character
    ])
  end

  def start_migration(
        %Character{} = origin_character,
        %Realm{} = destination_realm,
        currency_amount,
        opts \\ []
      )
      when is_integer(currency_amount) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    freeze_game_days = Keyword.get(opts, :freeze_game_days, freeze_game_days())

    Repo.transaction(fn ->
      origin_character = lock_character!(origin_character.id)
      origin_realm = Repo.get!(Realm, origin_character.realm_id)
      destination_realm = Repo.get!(Realm, destination_realm.id)

      validate_migration_start!(
        origin_character,
        origin_realm,
        destination_realm,
        currency_amount
      )

      {:ok, %{converted_amount: converted_amount}} =
        quote_exchange(origin_realm.id, destination_realm.id, currency_amount)

      destination_level = migrated_level(origin_character.level)
      destination_xp = migrated_xp(origin_character.xp)
      freeze_ends_at = Clock.arrival_at(started_at, freeze_game_days)
      destination_name = unique_character_name(destination_realm.id, origin_character.name)

      account = Repo.get!(Account, origin_character.account_id)

      destination_character =
        %Character{account_id: account.id, realm_id: destination_realm.id}
        |> Character.changeset(%{
          name: destination_name,
          status: :active,
          level: destination_level,
          xp: destination_xp,
          metadata: %{"migrated_from_realm_id" => origin_realm.id}
        })
        |> Repo.insert!()
        |> Character.travel_changeset(%{current_location_id: destination_realm.entry_location_id})
        |> Repo.update!()

      {:ok, origin_account} = Economy.ensure_character_account(origin_character)
      {:ok, destination_account} = Economy.ensure_character_account(destination_character)
      origin_treasury = Economy.treasury_account_for_realm(origin_realm.id)
      destination_treasury = Economy.treasury_account_for_realm(destination_realm.id)

      {:ok, _origin_settlement} =
        Economy.transfer(origin_account, origin_treasury, currency_amount, %{
          entry_type: "transfer",
          source: "inter_realm_migration_out",
          origin_character_id: origin_character.id,
          destination_realm_id: destination_realm.id
        })

      {:ok, _destination_settlement} =
        Economy.transfer(destination_treasury, destination_account, converted_amount, %{
          entry_type: "transfer",
          source: "inter_realm_migration_in",
          destination_character_id: destination_character.id,
          origin_realm_id: origin_realm.id
        })

      updated_origin_character =
        origin_character
        |> Character.changeset(%{status: :frozen})
        |> Repo.update!()

      migration =
        %Migration{}
        |> Migration.changeset(%{
          account_id: account.id,
          origin_realm_id: origin_realm.id,
          destination_realm_id: destination_realm.id,
          origin_character_id: origin_character.id,
          destination_character_id: destination_character.id,
          status: :active,
          currency_amount: currency_amount,
          converted_currency_amount: converted_amount,
          source_level: origin_character.level,
          destination_level: destination_level,
          source_xp: origin_character.xp,
          destination_xp: destination_xp,
          freeze_started_at: started_at,
          freeze_ends_at: freeze_ends_at,
          passive_xp_awarded: 0,
          metadata: %{}
        })
        |> Repo.insert!()

      _ =
        Notifications.notify_realm_migration_started(
          updated_origin_character,
          migration,
          destination_realm
        )

      %{
        migration: preload_migration(migration),
        origin_character: updated_origin_character,
        destination_character: destination_character
      }
    end)
    |> normalize_transaction_result()
  end

  def complete_migration_by_id(migration_id, opts \\ []) when is_binary(migration_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      migration = lock_migration!(migration_id)
      origin_character = lock_character!(migration.origin_character_id)

      cond do
        migration.status != :active ->
          Repo.rollback(migration_changeset("migration is not active"))

        not force? and DateTime.compare(now, migration.freeze_ends_at) == :lt ->
          Repo.rollback(migration_changeset("migration is not due yet"))

        true ->
          passive_xp_awarded = passive_xp_award(migration)

          updated_origin_character =
            origin_character
            |> Character.changeset(%{
              status: :active,
              xp: origin_character.xp + passive_xp_awarded
            })
            |> Repo.update!()

          updated_migration =
            migration
            |> Migration.changeset(%{
              status: :completed,
              completed_at: now,
              passive_xp_awarded: passive_xp_awarded
            })
            |> Repo.update!()

          _ =
            Notifications.notify_realm_migration_completed(
              updated_origin_character,
              updated_migration
            )

          %{
            migration: preload_migration(updated_migration),
            origin_character: updated_origin_character
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_migrations(now \\ DateTime.utc_now()) do
    Migration
    |> where([migration], migration.status == :active and migration.freeze_ends_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn migration -> complete_migration_by_id(migration.id, now: now, force: true) end)
  end

  def export_realm_manifest(%Realm{} = realm) do
    %{
      slug: realm.slug,
      name: realm.name,
      status: realm.status,
      ruleset_version: realm.ruleset_version,
      currency_code: realm.currency_code,
      public_endpoint: realm.public_endpoint,
      public_description: realm.public_description,
      operator_name: realm.operator_name,
      allow_migration: realm.allow_migration,
      population_hint: realm.population_hint,
      metadata: realm.metadata
    }
  end

  defp validate_migration_start!(
         %Character{} = origin_character,
         %Realm{} = origin_realm,
         %Realm{} = destination_realm,
         currency_amount
       ) do
    cond do
      origin_realm.id == destination_realm.id ->
        Repo.rollback(migration_changeset("origin and destination realms must differ"))

      destination_realm.allow_migration != true ->
        Repo.rollback(migration_changeset("destination realm is not accepting migrations"))

      is_nil(destination_realm.entry_location_id) ->
        Repo.rollback(migration_changeset("destination realm has no configured entry location"))

      origin_character.status != :active ->
        Repo.rollback(migration_changeset("origin character must be active"))

      currency_amount <= 0 ->
        Repo.rollback(migration_changeset("currency amount must be greater than zero"))

      active_migration_for_character(origin_character.id) ->
        Repo.rollback(migration_changeset("character already has an active migration"))

      true ->
        :ok
    end
  end

  defp maybe_exclude_realm(query, nil), do: query
  defp maybe_exclude_realm(query, realm_id), do: where(query, [realm], realm.id != ^realm_id)

  defp migrated_level(level), do: max(div(level * level_retention_bps(), 1000), 1)
  defp migrated_xp(xp), do: max(div(xp * xp_retention_bps(), 1000), 0)

  defp passive_xp_award(%Migration{} = migration) do
    max(div(migration.source_xp, 100), 10)
  end

  defp freeze_game_days do
    Application.get_env(:mmgo, __MODULE__, [])[:freeze_game_days] || 28
  end

  defp level_retention_bps do
    Application.get_env(:mmgo, __MODULE__, [])[:level_retention_bps] || 800
  end

  defp xp_retention_bps do
    Application.get_env(:mmgo, __MODULE__, [])[:xp_retention_bps] || 700
  end

  defp unique_character_name(realm_id, base_name) do
    candidate = base_name

    if Repo.exists?(
         from character in Character,
           where: character.realm_id == ^realm_id and character.name == ^candidate
       ) do
      candidate <> " #{String.slice(Ecto.UUID.generate(), 0, 4)}"
    else
      candidate
    end
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_migration!(migration_id) do
    Migration
    |> where([migration], migration.id == ^migration_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp preload_migration(%Migration{} = migration) do
    Repo.preload(migration, [
      :origin_realm,
      :destination_realm,
      :origin_character,
      :destination_character
    ])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp migration_changeset(message) do
    %Migration{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
