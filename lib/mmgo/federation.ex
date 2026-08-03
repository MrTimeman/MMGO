defmodule MMGO.Federation do
  import Ecto.Query, warn: false

  alias Ecto.{Changeset, Multi}
  alias MMGO.Accounts.{Account, Character, CharacterProfiles}
  alias MMGO.Economy
  alias MMGO.Federation.{ExchangeRate, Migration, RemoteRealm, Ruleset}
  alias MMGO.Notifications
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  def local_realm do
    MMGO.Worlds.get_default_realm()
  end

  def local_realm! do
    MMGO.Worlds.get_default_realm!()
  end

  def list_discoverable_realms(origin_realm_id \\ nil) do
    origin_realm = if origin_realm_id, do: Repo.get(Realm, origin_realm_id), else: nil

    list_remote_realms()
    |> Enum.reject(&(origin_realm && &1.slug == origin_realm.slug))
  end

  def list_remote_realms do
    Repo.all(
      from remote_realm in RemoteRealm,
        where: remote_realm.status == :active,
        order_by: [asc: remote_realm.inserted_at]
    )
  end

  def get_remote_realm!(id), do: Repo.get!(RemoteRealm, id)

  def get_remote_realm_by_slug(slug) when is_binary(slug) do
    Repo.get_by(RemoteRealm, slug: slug, status: :active)
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

  def quote_remote_exchange(%Realm{} = source_realm, %RemoteRealm{} = remote_realm, amount)
      when is_integer(amount) do
    cond do
      amount <= 0 ->
        {:error, migration_changeset("amount must be greater than zero")}

      remote_realm.allow_migration != true ->
        {:error, migration_changeset("remote realm is not accepting migrations")}

      true ->
        source_population = max(population_for_local_realm(source_realm.id), 1)
        destination_population = max(remote_realm.population_hint || 1, 1)
        raw_amount = div(amount * source_population, destination_population)
        converted_amount = raw_amount |> max(1) |> min(amount * 5)

        {:ok,
         %{
           source_amount: amount,
           converted_amount: converted_amount,
           source_population: source_population,
           destination_population: destination_population,
           ratio_numerator: source_population,
           ratio_denominator: destination_population,
           remote_realm: remote_realm
         }}
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

  def export_realm_manifest(%Realm{} = realm) do
    realm = Repo.preload(realm, :entry_location)

    %{
      slug: realm.slug,
      name: realm.name,
      status: to_string(realm.status),
      ruleset_version: realm.ruleset_version,
      currency_code: realm.currency_code,
      public_endpoint: manifest_public_endpoint(realm),
      public_description: realm.public_description,
      operator_name: realm.operator_name,
      allow_migration: realm.allow_migration,
      population_hint: population_for_local_realm(realm.id),
      entry_location_slug: realm.entry_location && realm.entry_location.slug,
      ruleset: Ruleset.normalize(realm.ruleset),
      metadata: realm.metadata
    }
  end

  def validate_manifest(manifest) when is_map(manifest) do
    manifest = stringify_keys(manifest)

    with true <- is_binary(manifest["slug"]),
         true <- is_binary(manifest["name"]),
         true <- is_binary(manifest["public_endpoint"]),
         true <- is_binary(manifest["currency_code"]),
         true <- is_boolean(manifest["allow_migration"]),
         true <- is_integer(manifest["population_hint"]) and manifest["population_hint"] >= 1,
         {:ok, ruleset} <- Ruleset.validate(manifest["ruleset"] || %{}) do
      {:ok, Map.put(manifest, "ruleset", ruleset)}
    else
      false -> {:error, migration_changeset("manifest is missing required fields")}
      {:error, message} -> {:error, migration_changeset(message)}
    end
  end

  def fetch_remote_manifest(manifest_url) when is_binary(manifest_url) do
    case Req.get(manifest_url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case decode_body(body) do
          {:ok, manifest} ->
            validate_manifest(manifest)

          {:error, _reason} ->
            {:error, migration_changeset("manifest response was not valid JSON")}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, migration_changeset("manifest fetch failed with status #{status}")}

      {:error, reason} ->
        {:error, migration_changeset("manifest fetch failed: #{inspect(reason)}")}
    end
  end

  def register_remote_realm(manifest_url, access_token \\ nil) when is_binary(manifest_url) do
    with {:ok, manifest} <- fetch_remote_manifest(manifest_url) do
      attrs = %{
        slug: manifest["slug"],
        name: manifest["name"],
        status: :active,
        manifest_url: manifest_url,
        public_endpoint: manifest["public_endpoint"],
        currency_code: manifest["currency_code"],
        public_description: manifest["public_description"],
        operator_name: manifest["operator_name"],
        allow_migration: manifest["allow_migration"],
        population_hint: manifest["population_hint"],
        ruleset_version: manifest["ruleset_version"] || 1,
        ruleset: manifest["ruleset"],
        entry_location_slug: manifest["entry_location_slug"],
        access_token: access_token,
        last_synced_at: DateTime.utc_now(),
        metadata: manifest["metadata"] || %{}
      }

      case get_remote_realm_by_slug(attrs.slug) do
        nil ->
          %RemoteRealm{} |> RemoteRealm.changeset(attrs) |> Repo.insert()

        %RemoteRealm{} = remote_realm ->
          remote_realm |> RemoteRealm.changeset(attrs) |> Repo.update()
      end
    end
  end

  def sync_remote_realm(%RemoteRealm{} = remote_realm) do
    with {:ok, manifest} <- fetch_remote_manifest(remote_realm.manifest_url) do
      remote_realm
      |> RemoteRealm.changeset(%{
        name: manifest["name"],
        public_endpoint: manifest["public_endpoint"],
        currency_code: manifest["currency_code"],
        public_description: manifest["public_description"],
        operator_name: manifest["operator_name"],
        allow_migration: manifest["allow_migration"],
        population_hint: manifest["population_hint"],
        ruleset_version: manifest["ruleset_version"] || 1,
        ruleset: manifest["ruleset"],
        entry_location_slug: manifest["entry_location_slug"],
        last_synced_at: DateTime.utc_now(),
        metadata: manifest["metadata"] || %{}
      })
      |> Repo.update()
    end
  end

  def list_migrations_for_account(account_id) when is_binary(account_id) do
    Repo.all(
      from migration in Migration,
        where: migration.account_id == ^account_id,
        order_by: [desc: migration.inserted_at],
        preload: [
          :origin_realm,
          :destination_realm,
          :remote_realm,
          :origin_character,
          :destination_character
        ]
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
      :remote_realm,
      :origin_character,
      :destination_character
    ])
  end

  @doc "Returns whether a remote destination has acknowledged this migration handoff."
  def remote_import_status(%Migration{mode: :remote} = migration) do
    case Map.get(migration.metadata || %{}, "remote_import_status") do
      "accepted" ->
        :accepted

      "pending" ->
        :pending

      _other ->
        if(nonempty_string?(migration.destination_external_ref), do: :accepted, else: :pending)
    end
  end

  def remote_import_status(_migration), do: :not_applicable

  @doc "Returns whether a discovered remote has the local credentials required for import."
  def remote_migration_ready?(%RemoteRealm{} = remote_realm) do
    remote_realm.status == :active and remote_realm.allow_migration == true and
      nonempty_string?(remote_realm.access_token)
  end

  def remote_migration_ready?(_remote_realm), do: false

  def start_migration(origin_character, destination, currency_amount, opts \\ [])

  def start_migration(
        %Character{} = origin_character,
        %Realm{} = destination_realm,
        currency_amount,
        opts
      )
      when is_integer(currency_amount) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    freeze_game_days = Keyword.get(opts, :freeze_game_days, freeze_game_days())

    Repo.transaction(fn ->
      origin_character = lock_character!(origin_character.id)
      account = lock_account!(origin_character.account_id)
      origin_realm = Repo.get!(Realm, origin_character.realm_id)
      destination_realm = Repo.get!(Realm, destination_realm.id)

      validate_local_migration_start!(
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

      updated_origin_character =
        origin_character
        |> Character.changeset(%{status: :frozen})
        |> Repo.update!()

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

      migration_changeset =
        %Migration{}
        |> Migration.changeset(%{
          account_id: account.id,
          mode: :local,
          origin_realm_id: origin_realm.id,
          destination_realm_id: destination_realm.id,
          origin_character_id: origin_character.id,
          destination_character_id: destination_character.id,
          destination_character_name: destination_character.name,
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

      migration = insert_migration_or_rollback(migration_changeset)

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

  def start_migration(
        %Character{} = origin_character,
        %RemoteRealm{} = remote_realm,
        currency_amount,
        opts
      )
      when is_integer(currency_amount) do
    case stage_remote_migration(origin_character, remote_realm, currency_amount, opts) do
      {:ok, %{migration: migration} = staged_result} ->
        case retry_remote_migration_import(migration.id) do
          {:ok, %{migration: imported_migration, remote_response: remote_response}} ->
            {:ok,
             staged_result
             |> Map.put(:migration, imported_migration)
             |> Map.put(:remote_response, remote_response)}

          {:error, reason} ->
            {:ok,
             staged_result
             |> Map.put(:migration, get_migration!(migration.id))
             |> Map.put(:remote_response, nil)
             |> Map.put(:remote_import_error, reason)}
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Retries a persisted remote handoff using its server-owned idempotency reference."
  def retry_remote_migration_import(migration_id) when is_binary(migration_id) do
    with {:ok, migration} <- remote_migration_for_import(migration_id) do
      if remote_import_status(migration) == :accepted do
        {:ok, %{migration: migration, remote_response: remote_import_response(migration)}}
      else
        attempt_remote_migration_import(migration)
      end
    end
  end

  def retry_remote_migration_import(_migration_id),
    do: {:error, migration_changeset("remote migration could not be found")}

  defp stage_remote_migration(
         %Character{} = origin_character,
         %RemoteRealm{} = remote_realm,
         currency_amount,
         opts
       ) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    freeze_game_days = Keyword.get(opts, :freeze_game_days, freeze_game_days())

    Repo.transaction(fn ->
      origin_character = lock_character!(origin_character.id)
      _account = lock_account!(origin_character.account_id)
      origin_realm = Repo.get!(Realm, origin_character.realm_id)
      remote_realm = Repo.get!(RemoteRealm, remote_realm.id)

      validate_remote_migration_start!(
        origin_character,
        origin_realm,
        remote_realm,
        currency_amount
      )

      {:ok, quote} = quote_remote_exchange(origin_realm, remote_realm, currency_amount)

      destination_level = migrated_level(origin_character.level)
      destination_xp = migrated_xp(origin_character.xp)
      freeze_ends_at = Clock.arrival_at(started_at, freeze_game_days)
      migration_reference = Ecto.UUID.generate()

      {:ok, origin_account} = Economy.ensure_character_account(origin_character)
      origin_treasury = Economy.treasury_account_for_realm(origin_realm.id)

      {:ok, _origin_settlement} =
        Economy.transfer(origin_account, origin_treasury, currency_amount, %{
          entry_type: "transfer",
          source: "remote_realm_migration_out",
          origin_character_id: origin_character.id,
          remote_realm_slug: remote_realm.slug
        })

      updated_origin_character =
        origin_character
        |> Character.changeset(%{status: :frozen})
        |> Repo.update!()

      migration_changeset =
        %Migration{}
        |> Migration.changeset(%{
          account_id: origin_character.account_id,
          mode: :remote,
          origin_realm_id: origin_realm.id,
          remote_realm_id: remote_realm.id,
          origin_character_id: origin_character.id,
          destination_character_name: origin_character.name,
          status: :active,
          currency_amount: currency_amount,
          converted_currency_amount: quote.converted_amount,
          source_level: origin_character.level,
          destination_level: destination_level,
          source_xp: origin_character.xp,
          destination_xp: destination_xp,
          freeze_started_at: started_at,
          freeze_ends_at: freeze_ends_at,
          passive_xp_awarded: 0,
          metadata: %{
            "source_population" => quote.source_population,
            "destination_population" => quote.destination_population,
            "migration_reference" => migration_reference,
            "remote_import_status" => "pending",
            "remote_import_attempts" => 0
          }
        })

      migration = insert_migration_or_rollback(migration_changeset)

      _ =
        Notifications.notify_realm_migration_started(
          updated_origin_character,
          migration,
          remote_realm
        )

      %{
        migration: preload_migration(migration),
        origin_character: updated_origin_character
      }
    end)
    |> normalize_transaction_result()
  end

  def import_remote_character(payload) when is_map(payload) do
    realm = local_realm!()
    import_remote_character(realm, payload)
  end

  def import_remote_character(%Realm{} = realm, payload) when is_map(payload) do
    payload = stringify_keys(payload)

    with :ok <- validate_remote_import(realm, payload) do
      case imported_character_by_reference(payload["migration_reference"]) do
        %Character{} = destination_character ->
          {:ok, import_response(destination_character, payload["migration_reference"])}

        nil ->
          create_remote_import(realm, payload)
      end
    end
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

        migration.mode == :remote and remote_import_status(migration) != :accepted ->
          Repo.rollback(migration_changeset("destination import has not been confirmed yet"))

        not force? and DateTime.compare(now, migration.freeze_ends_at) == :lt ->
          Repo.rollback(migration_changeset("migration is not due yet"))

        true ->
          passive_xp_awarded = passive_xp_award(migration)

          origin_status =
            if migration.mode == :local and is_binary(migration.destination_character_id),
              do: :frozen,
              else: :active

          updated_origin_character =
            origin_character
            |> Character.changeset(%{status: origin_status})
            |> Repo.update!()

          {:ok, %{character: updated_origin_character}} =
            Progression.grant_xp(Repo, updated_origin_character, passive_xp_awarded, %{
              "source" => "realm_migration_completion",
              "migration_id" => migration.id,
              "granted_at" => now
            })

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

  defp remote_migration_for_import(migration_id) do
    migration =
      Migration
      |> Repo.get(migration_id)
      |> case do
        nil -> nil
        migration -> preload_migration(migration)
      end

    cond do
      is_nil(migration) ->
        {:error, migration_changeset("remote migration could not be found")}

      migration.mode != :remote ->
        {:error, migration_changeset("migration does not use a remote destination")}

      migration.status != :active ->
        {:error, migration_changeset("migration is not active")}

      remote_import_status(migration) == :accepted ->
        {:ok, migration}

      is_nil(migration.remote_realm) ->
        {:error, migration_changeset("remote destination is unavailable")}

      migration.remote_realm.status != :active or migration.remote_realm.allow_migration != true ->
        {:error, migration_changeset("remote destination is not accepting migrations")}

      true ->
        {:ok, migration}
    end
  end

  defp attempt_remote_migration_import(%Migration{} = migration) do
    result =
      with {:ok, payload} <- remote_migration_payload(migration),
           {:ok, remote_response} <- request_remote_import(migration.remote_realm, payload),
           :ok <- validate_remote_import_response(remote_response),
           {:ok, updated_migration} <-
             confirm_remote_migration_import(migration.id, remote_response) do
        {:ok, %{migration: updated_migration, remote_response: remote_response}}
      end

    case result do
      {:error, reason} = error ->
        _ = record_remote_import_failure(migration.id, reason)
        error

      success ->
        success
    end
  end

  defp remote_migration_payload(%Migration{} = migration) do
    reference = Map.get(migration.metadata || %{}, "migration_reference")
    account = Repo.get(Account, migration.account_id)

    cond do
      not nonempty_string?(reference) ->
        {:error, migration_changeset("remote migration is missing its handoff reference")}

      is_nil(account) or is_nil(migration.origin_realm) ->
        {:error, migration_changeset("remote migration has incomplete origin identity")}

      true ->
        {:ok,
         %{
           account_handle: account.handle,
           display_name: account.display_name,
           character_name: migration.destination_character_name,
           destination_level: migration.destination_level,
           destination_xp: migration.destination_xp,
           converted_currency_amount: migration.converted_currency_amount,
           origin_realm_slug: migration.origin_realm.slug,
           migration_reference: reference
         }}
    end
  end

  defp validate_remote_import_response(response) when is_map(response) do
    if Enum.all?(
         [
           Map.get(response, "destination_character_id"),
           Map.get(response, "destination_character_name"),
           Map.get(response, "destination_character_ref")
         ],
         &nonempty_string?/1
       ) do
      :ok
    else
      {:error, migration_changeset("remote import returned incomplete destination identity")}
    end
  end

  defp confirm_remote_migration_import(migration_id, remote_response) do
    Repo.transaction(fn ->
      migration = lock_migration!(migration_id)

      cond do
        migration.mode != :remote or migration.status != :active ->
          Repo.rollback(migration_changeset("migration is not active"))

        remote_import_status(migration) == :accepted ->
          preload_migration(migration)

        true ->
          metadata =
            (migration.metadata || %{})
            |> Map.put("remote_import_status", "accepted")
            |> Map.put("remote_import_accepted_at", DateTime.to_iso8601(DateTime.utc_now()))
            |> Map.put("remote_import_response", remote_response)
            |> Map.put(
              "remote_destination_character_id",
              Map.get(remote_response, "destination_character_id")
            )
            |> Map.delete("remote_import_last_error")

          migration
          |> Migration.changeset(%{
            destination_character_name: Map.get(remote_response, "destination_character_name"),
            destination_external_ref: Map.get(remote_response, "destination_character_ref"),
            metadata: metadata
          })
          |> Repo.update!()
          |> preload_migration()
      end
    end)
    |> normalize_transaction_result()
  end

  defp record_remote_import_failure(migration_id, _reason) do
    Repo.transaction(fn ->
      migration = lock_migration!(migration_id)

      if migration.mode == :remote and migration.status == :active and
           remote_import_status(migration) != :accepted do
        attempts =
          case Map.get(migration.metadata || %{}, "remote_import_attempts", 0) do
            count when is_integer(count) and count >= 0 -> count
            _other -> 0
          end

        migration
        |> Migration.changeset(%{
          metadata:
            (migration.metadata || %{})
            |> Map.put("remote_import_status", "pending")
            |> Map.put("remote_import_attempts", attempts + 1)
            |> Map.put("remote_import_last_attempt_at", DateTime.to_iso8601(DateTime.utc_now()))
            |> Map.put("remote_import_last_error", "remote import could not be confirmed")
        })
        |> Repo.update!()
      else
        migration
      end
    end)
    |> normalize_transaction_result()
  end

  defp remote_import_response(%Migration{} = migration) do
    case Map.get(migration.metadata || %{}, "remote_import_response") do
      response when is_map(response) ->
        response

      _other ->
        %{
          "destination_character_id" =>
            Map.get(migration.metadata || %{}, "remote_destination_character_id"),
          "destination_character_name" => migration.destination_character_name,
          "destination_character_ref" => migration.destination_external_ref
        }
    end
  end

  defp request_remote_import(%RemoteRealm{} = remote_realm, payload) do
    endpoint =
      String.trim_trailing(remote_realm.public_endpoint, "/") <>
        "/api/federation/import-migration"

    headers =
      if remote_realm.access_token,
        do: [{"authorization", "Bearer #{remote_realm.access_token}"}],
        else: []

    case Req.post(endpoint, json: payload, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case decode_body(body) do
          {:ok, response_body} when is_map(response_body) ->
            {:ok, response_body}

          _other ->
            {:error, migration_changeset("remote import returned an invalid response body")}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, migration_changeset("remote import failed with status #{status}")}

      {:error, reason} ->
        {:error, migration_changeset("remote import failed: #{inspect(reason)}")}
    end
  end

  defp validate_local_migration_start!(
         %Character{} = origin_character,
         %Realm{} = origin_realm,
         %Realm{} = destination_realm,
         currency_amount
       ) do
    cond do
      CharacterProfiles.sealed_spirit?(origin_character) ->
        Repo.rollback(migration_changeset("sealed spirit cannot leave its realm"))

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

      active_migration_for_account?(origin_character.account_id) ->
        Repo.rollback(migration_changeset("account already has an active migration"))

      true ->
        :ok
    end
  end

  defp validate_remote_migration_start!(
         %Character{} = origin_character,
         %Realm{} = origin_realm,
         %RemoteRealm{} = remote_realm,
         currency_amount
       ) do
    cond do
      CharacterProfiles.sealed_spirit?(origin_character) ->
        Repo.rollback(migration_changeset("sealed spirit cannot leave its realm"))

      origin_realm.slug == remote_realm.slug ->
        Repo.rollback(migration_changeset("origin and destination realms must differ"))

      remote_realm.allow_migration != true ->
        Repo.rollback(migration_changeset("remote realm is not accepting migrations"))

      not nonempty_string?(remote_realm.access_token) ->
        Repo.rollback(migration_changeset("remote realm import authorization is unavailable"))

      is_nil(remote_realm.entry_location_slug) ->
        Repo.rollback(migration_changeset("remote realm has no configured entry location"))

      origin_character.status != :active ->
        Repo.rollback(migration_changeset("origin character must be active"))

      currency_amount <= 0 ->
        Repo.rollback(migration_changeset("currency amount must be greater than zero"))

      active_migration_for_character(origin_character.id) ->
        Repo.rollback(migration_changeset("character already has an active migration"))

      active_migration_for_account?(origin_character.account_id) ->
        Repo.rollback(migration_changeset("account already has an active migration"))

      true ->
        :ok
    end
  end

  defp validate_remote_import(%Realm{} = realm, payload) do
    cond do
      realm.allow_migration != true ->
        {:error, migration_changeset("local realm is not accepting migrations")}

      is_nil(realm.entry_location_id) ->
        {:error, migration_changeset("local realm has no configured entry location")}

      not is_binary(payload["character_name"]) ->
        {:error, migration_changeset("payload is missing character_name")}

      not is_binary(payload["account_handle"]) ->
        {:error, migration_changeset("payload is missing account_handle")}

      not is_binary(payload["migration_reference"]) ->
        {:error, migration_changeset("payload is missing migration_reference")}

      not is_integer(payload["converted_currency_amount"]) or
          payload["converted_currency_amount"] < 0 ->
        {:error, migration_changeset("payload has invalid converted_currency_amount")}

      not is_integer(payload["destination_level"]) or payload["destination_level"] <= 0 ->
        {:error, migration_changeset("payload has invalid destination_level")}

      not is_integer(payload["destination_xp"]) or payload["destination_xp"] < 0 ->
        {:error, migration_changeset("payload has invalid destination_xp")}

      true ->
        :ok
    end
  end

  defp migrated_level(level), do: max(div(level * level_retention_bps(), 1000), 1)
  defp migrated_xp(xp), do: max(div(xp * xp_retention_bps(), 1000), 0)

  defp passive_xp_award(%Migration{} = migration) do
    max(div(migration.source_xp, 100), 10)
  end

  defp population_for_local_realm(realm_id) do
    Repo.aggregate(
      from(character in Character,
        where:
          character.realm_id == ^realm_id and
            fragment("COALESCE(?->>'hidden_presence', 'false') <> 'true'", character.metadata) and
            fragment("COALESCE(?->>'profile_kind', '') <> 'sealed_spirit'", character.metadata)
      ),
      :count,
      :id
    )
    |> max(1)
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

  defp unique_account_handle(base_handle) do
    candidate = base_handle

    if Repo.exists?(from account in Account, where: account.handle == ^candidate) do
      candidate <> "-" <> String.slice(Ecto.UUID.generate(), 0, 4)
    else
      candidate
    end
  end

  defp manifest_public_endpoint(%Realm{} = realm) do
    realm.public_endpoint ||
      String.trim_trailing(
        Application.get_env(:mmgo, __MODULE__, [])[:public_base_url] || "",
        "/"
      )
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    Jason.decode(body)
  end

  defp decode_body(_body), do: {:error, :invalid_body}

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_account!(account_id) do
    Account
    |> where([account], account.id == ^account_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp active_migration_for_account?(account_id) do
    Repo.exists?(
      from migration in Migration,
        where: migration.account_id == ^account_id and migration.status == :active
    )
  end

  defp insert_migration_or_rollback(%Changeset{} = changeset) do
    case Repo.insert(changeset) do
      {:ok, migration} -> migration
      {:error, changeset} -> Repo.rollback(changeset)
    end
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
      :remote_realm,
      :origin_character,
      :destination_character
    ])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp create_remote_import(%Realm{} = realm, payload) do
    Multi.new()
    |> Multi.insert(
      :account,
      Account.registration_changeset(%Account{}, %{
        display_name: payload["display_name"] || payload["character_name"],
        handle: unique_account_handle(payload["account_handle"] || payload["character_name"])
      })
    )
    |> Multi.insert(:destination_character, fn %{account: account} ->
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.import_changeset(%{
        name: unique_character_name(realm.id, payload["character_name"]),
        status: :active,
        level: payload["destination_level"],
        xp: payload["destination_xp"],
        import_reference: payload["migration_reference"],
        metadata: %{"imported_from_realm_slug" => payload["origin_realm_slug"]}
      })
    end)
    |> Multi.update(:destination_character_location, fn %{
                                                          destination_character:
                                                            destination_character
                                                        } ->
      Character.travel_changeset(destination_character, %{
        current_location_id: realm.entry_location_id
      })
    end)
    |> Multi.run(:funding, fn _repo, %{destination_character_location: destination_character} ->
      Economy.grant_from_treasury(
        realm,
        destination_character,
        payload["converted_currency_amount"],
        %{
          entry_type: "transfer",
          source: "remote_realm_migration_in",
          origin_realm_slug: payload["origin_realm_slug"],
          migration_reference: payload["migration_reference"]
        }
      )
    end)
    |> Repo.transaction()
    |> normalize_import_result(payload)
  end

  defp normalize_import_result(
         {:ok, %{destination_character_location: destination_character}},
         payload
       ) do
    {:ok, import_response(destination_character, payload["migration_reference"])}
  end

  defp normalize_import_result(
         {:error, :destination_character, %Changeset{} = changeset, _changes},
         payload
       ) do
    case import_response_from_duplicate(changeset, payload["migration_reference"]) do
      {:ok, response} -> {:ok, response}
      :error -> {:error, changeset}
    end
  end

  defp normalize_import_result({:error, _step, %Changeset{} = changeset, _changes}, _payload),
    do: {:error, changeset}

  defp normalize_import_result({:ok, result}, _payload), do: {:ok, result}

  defp normalize_import_result({:error, %Changeset{} = changeset}, _payload),
    do: {:error, changeset}

  defp import_response_from_duplicate(%Changeset{} = changeset, import_reference) do
    if import_reference_conflict?(changeset) do
      case imported_character_by_reference(import_reference) do
        %Character{} = destination_character ->
          {:ok, import_response(destination_character, import_reference)}

        nil ->
          :error
      end
    else
      :error
    end
  end

  defp import_reference_conflict?(%Changeset{constraints: constraints}) do
    Enum.any?(constraints, fn
      %{type: :unique, constraint: "characters_import_reference_index"} -> true
      _other -> false
    end)
  end

  defp imported_character_by_reference(import_reference) when is_binary(import_reference) do
    Repo.get_by(Character, import_reference: import_reference)
  end

  defp imported_character_by_reference(_import_reference), do: nil

  defp import_response(%Character{} = destination_character, import_reference) do
    %{
      destination_character_id: destination_character.id,
      destination_character_name: destination_character.name,
      destination_character_ref: import_reference || destination_character.id
    }
  end

  defp nonempty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp nonempty_string?(_value), do: false

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp migration_changeset(message) do
    %Migration{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
