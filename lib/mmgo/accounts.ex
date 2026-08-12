defmodule MMGO.Accounts do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias MMGO.Accounts.{Account, Character, CharacterProfiles, SpecialProfiles, TelegramIdentity}
  alias MMGO.Federation.Migration
  alias MMGO.Repo
  alias MMGO.Travel.Journey
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  def get_account!(id), do: Repo.get!(Account, id)
  def get_character!(id), do: Repo.get!(Character, id)

  @doc "Returns the account's persistent ordinary-world command character."
  def get_default_world_character_for_account(account_id) when is_binary(account_id) do
    from(character in Character,
      join: account in Account,
      on:
        account.id == ^account_id and account.default_character_id == character.id and
          character.account_id == account.id,
      where:
        account.status == :active and character.status in [:new, :active, :frozen] and
          fragment(
            "COALESCE(?->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')",
            character.metadata
          ),
      preload: [:account, :realm, :current_location]
    )
    |> Repo.one()
  end

  def get_default_world_character_for_account(%Account{id: account_id}),
    do: get_default_world_character_for_account(account_id)

  def get_default_world_character_for_account(_account_id), do: nil

  @doc "Persists an owned, playable, ordinary-world character as the account default."
  def set_default_world_character(account_id, character_id)
      when is_binary(account_id) and is_binary(character_id) do
    Repo.transaction(fn ->
      account = lock_account(account_id) || Repo.rollback(:not_found)

      if account.status != :active do
        Repo.rollback(:account_inactive)
      end

      character = lock_owned_character(account_id, character_id) || Repo.rollback(:not_found)

      cond do
        not ordinary_world_character?(character) ->
          Repo.rollback(:not_world_character)

        character.status not in [:new, :active, :frozen] ->
          Repo.rollback(:not_playable)

        true ->
          persist_default_world_character!(account, character)
          Repo.preload(character, [:account, :realm, :current_location])
      end
    end)
  end

  def set_default_world_character(_account_id, _character_id), do: {:error, :not_found}

  def list_characters_for_account(account_id) when is_binary(account_id) do
    Repo.all(
      from character in Character,
        where:
          character.account_id == ^account_id and
            fragment("COALESCE(?->>'profile_kind', '') <> 'arena'", character.metadata),
        order_by: [asc: character.realm_id, asc: character.inserted_at, asc: character.name],
        preload: [:realm, :current_location]
    )
  end

  def list_characters_for_account(_account_id), do: []

  @doc "Lists account-owned arena characters without mixing them into the world profile picker."
  def list_arena_characters_for_account(account_id) when is_binary(account_id) do
    Repo.all(
      from character in Character,
        where:
          character.account_id == ^account_id and
            fragment("COALESCE(?->>'profile_kind', '') = 'arena'", character.metadata),
        order_by: [asc: character.inserted_at, asc: character.name],
        preload: [:realm, :current_location]
    )
  end

  def list_arena_characters_for_account(_account_id), do: []

  def get_character_for_account(account_id, character_id)
      when is_binary(account_id) and is_binary(character_id) do
    Repo.get_by(Character, id: character_id, account_id: account_id)
  end

  def get_character_for_account(_account_id, _character_id), do: nil

  def list_active_migration_character_ids(account_id) when is_binary(account_id) do
    Repo.all(
      from migration in Migration,
        where: migration.account_id == ^account_id and migration.status == :active,
        select: {migration.origin_character_id, migration.destination_character_id}
    )
    |> Enum.flat_map(fn {origin_id, destination_id} -> [origin_id, destination_id] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def list_active_migration_character_ids(_account_id), do: []

  @doc """
  Returns the origin profile for the latest active realm migration owned by an
  active account. This is deliberately narrower than ordinary character auth:
  it exists only so a frozen remote migrant can reopen the migration ledger.
  """
  def get_active_migration_character_for_account(account_id) when is_binary(account_id) do
    character =
      from(migration in Migration,
        join: character in Character,
        on: character.id == migration.origin_character_id,
        join: account in Account,
        on: account.id == migration.account_id,
        where:
          migration.account_id == ^account_id and migration.status == :active and
            account.status == :active and character.status in [:active, :frozen],
        order_by: [desc: migration.inserted_at],
        limit: 1,
        select: character
      )
      |> Repo.one()

    case character do
      %Character{} = character ->
        {:ok, Repo.preload(character, [:account, :realm, :current_location])}

      nil ->
        {:error, :not_found}
    end
  end

  def get_active_migration_character_for_account(_account_id), do: {:error, :not_found}

  @doc "Activates one owned profile and freezes playable siblings in the same game mode."
  def switch_character(account_id, character_id)
      when is_binary(account_id) and is_binary(character_id) do
    Repo.transaction(fn ->
      account = lock_account(account_id)

      if is_nil(account) or account.status != :active do
        Repo.rollback(:account_inactive)
      end

      siblings =
        Character
        |> where([character], character.account_id == ^account_id)
        |> order_by([character], asc: character.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      target = Enum.find(siblings, &(&1.id == character_id))

      cond do
        is_nil(target) ->
          Repo.rollback(:not_found)

        target.status == :active ->
          # Keep the current profile selectable while a local migration is
          # active so its destination can leave the dossier and enter the map.
          # Also repair any stale same-mode active sibling before returning.
          freeze_mode_siblings!(siblings, target)
          maybe_persist_default_world_character!(account, target)
          Repo.preload(target, [:account, :realm, :current_location])

        active_migration_for_account?(account_id) ->
          Repo.rollback(:migration_in_progress)

        target.status not in [:active, :frozen, :new] ->
          Repo.rollback(:not_playable)

        true ->
          freeze_mode_siblings!(siblings, target)

          target =
            if target.status == :new do
              target
            else
              target
              |> Character.changeset(%{status: :active})
              |> Repo.update!()
            end

          maybe_persist_default_world_character!(account, target)
          Repo.preload(target, [:account, :realm, :current_location])
      end
    end)
  end

  def switch_character(_account_id, _character_id), do: {:error, :not_found}

  @doc """
  Returns an active character only when it belongs to the active account whose
  identifier came from the browser session.

  Keeping the ownership check here prevents web callers from authorizing a
  character merely because they know its UUID.
  """
  def get_active_character_for_account(account_id, character_id)
      when is_binary(account_id) and is_binary(character_id) do
    character =
      from(character in Character,
        join: account in Account,
        on: account.id == character.account_id,
        where: character.id == ^character_id and account.id == ^account_id
      )
      |> Repo.one()

    case character do
      nil ->
        {:error, :not_found}

      %Character{} = character ->
        character = Repo.preload(character, [:account, :current_location])

        if character.account.status == :active and character.status == :active do
          {:ok, character}
        else
          {:error, :inactive}
        end
    end
  end

  def get_active_character_for_account(_account_id, _character_id), do: {:error, :not_found}

  @doc """
  Returns an account-owned character that may view the narrowly scoped realm
  migration surface. A frozen character remains excluded from ordinary game
  actions, but can inspect and retry its own durable migration handoff.
  """
  def get_migration_character_for_account(account_id, character_id)
      when is_binary(account_id) and is_binary(character_id) do
    character =
      from(character in Character,
        join: account in Account,
        on: account.id == character.account_id,
        where: character.id == ^character_id and account.id == ^account_id
      )
      |> Repo.one()

    case character do
      nil ->
        {:error, :not_found}

      %Character{} = character ->
        character = Repo.preload(character, [:account, :current_location])

        if character.account.status == :active and character.status in [:active, :frozen] do
          {:ok, character}
        else
          {:error, :inactive}
        end
    end
  end

  def get_migration_character_for_account(_account_id, _character_id), do: {:error, :not_found}

  @doc """
  Lists other active, stationary characters at one realm location.

  This is presence data for the current player's world view, not authority to
  operate those characters.
  """
  def list_active_characters_at_location(realm_id, location_id, opts \\ [])

  def list_active_characters_at_location(realm_id, location_id, opts)
      when is_binary(realm_id) and is_binary(location_id) and is_list(opts) do
    exclude_character_id = Keyword.get(opts, :exclude_character_id)

    query =
      from(character in Character,
        join: account in Account,
        on: account.id == character.account_id,
        left_join: journey in Journey,
        on: journey.character_id == character.id and journey.status == :active,
        where:
          character.realm_id == ^realm_id and character.current_location_id == ^location_id and
            character.status == :active and account.status == :active and is_nil(journey.id) and
            fragment("COALESCE(?->>'npc', 'false') <> 'true'", account.settings) and
            fragment("COALESCE(?->>'hidden_presence', 'false') <> 'true'", character.metadata) and
            fragment(
              "COALESCE(?->>'profile_kind', '') NOT IN ('sealed_spirit', 'arena')",
              character.metadata
            ),
        order_by: [asc: character.name],
        preload: [:account, :current_location]
      )

    query =
      if is_binary(exclude_character_id) do
        from character in query, where: character.id != ^exclude_character_id
      else
        query
      end

    Repo.all(query)
  end

  def list_active_characters_at_location(_realm_id, _location_id, _opts), do: []

  @doc "Returns visible active world characters in a realm for consensual wagered duels."
  def list_active_characters_in_realm(realm_id, opts \\ [])

  def list_active_characters_in_realm(realm_id, opts)
      when is_binary(realm_id) and is_list(opts) do
    exclude_character_id = Keyword.get(opts, :exclude_character_id)

    query =
      from(character in Character,
        join: account in Account,
        on: account.id == character.account_id,
        left_join: journey in Journey,
        on: journey.character_id == character.id and journey.status == :active,
        where:
          character.realm_id == ^realm_id and character.status == :active and
            account.status == :active and is_nil(journey.id) and
            fragment("COALESCE(?->>'npc', 'false') <> 'true'", account.settings) and
            fragment("COALESCE(?->>'hidden_presence', 'false') <> 'true'", character.metadata) and
            fragment(
              "COALESCE(?->>'profile_kind', '') NOT IN ('sealed_spirit', 'arena')",
              character.metadata
            ),
        order_by: [asc: character.name],
        preload: [:account, :current_location]
      )

    query =
      if is_binary(exclude_character_id) do
        from character in query, where: character.id != ^exclude_character_id
      else
        query
      end

    Repo.all(query)
  end

  def list_active_characters_in_realm(_realm_id, _opts), do: []

  def get_character_by_handle(realm_id, handle) when is_binary(realm_id) and is_binary(handle) do
    from(character in Character,
      join: account in Account,
      on: account.id == character.account_id,
      where:
        character.realm_id == ^realm_id and account.handle == ^handle and
          character.status == :active and account.status == :active and
          fragment("COALESCE(?->>'hidden_presence', 'false') <> 'true'", character.metadata) and
          fragment(
            "COALESCE(?->>'profile_kind', '') NOT IN ('sealed_spirit', 'arena')",
            character.metadata
          ),
      select: character
    )
    |> Repo.one()
  end

  def get_account_by_telegram_user_id(telegram_user_id) when is_integer(telegram_user_id) do
    TelegramIdentity
    |> Repo.get_by(telegram_user_id: telegram_user_id)
    |> case do
      nil -> nil
      identity -> identity |> Repo.preload(:account) |> Map.fetch!(:account)
    end
  end

  def provision_from_telegram(attrs) when is_map(attrs) do
    with {:ok, telegram_attrs} <- normalize_telegram_attrs(attrs) do
      case Repo.get_by(TelegramIdentity, telegram_user_id: telegram_attrs.telegram_user_id) do
        nil -> create_telegram_account(telegram_attrs)
        identity -> refresh_telegram_account(identity, telegram_attrs)
      end
    end
  end

  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.registration_changeset(account, attrs)
  end

  defp create_telegram_account(telegram_attrs) do
    with %Realm{} = realm <- Worlds.get_default_realm() do
      display_name = display_name_from_telegram(telegram_attrs)

      Multi.new()
      |> Multi.insert(
        :account,
        Account.registration_changeset(%Account{}, account_attrs(display_name, telegram_attrs))
      )
      |> Multi.insert(:telegram_identity, fn %{account: account} ->
        account
        |> Ecto.build_assoc(:telegram_identity)
        |> TelegramIdentity.changeset(telegram_attrs)
      end)
      |> Multi.insert(:character, fn %{account: account} ->
        %Character{account_id: account.id, realm_id: realm.id}
        |> Character.changeset(%{name: unique_character_name(realm, display_name)})
      end)
      |> Repo.transaction()
      |> maybe_reconcile_special_profiles(telegram_attrs)
    else
      nil -> {:error, :default_realm_not_found}
    end
  end

  defp refresh_telegram_account(identity, telegram_attrs) do
    identity = Repo.preload(identity, :account)
    display_name = display_name_from_telegram(telegram_attrs)
    account_settings = telegram_account_settings(identity.account.settings, telegram_attrs)

    with %Realm{} = realm <- Worlds.get_default_realm() do
      Multi.new()
      |> Multi.update(
        :account,
        Account.registration_changeset(identity.account, %{
          display_name: display_name,
          settings: account_settings
        })
      )
      |> Multi.update(:telegram_identity, TelegramIdentity.changeset(identity, telegram_attrs))
      |> Multi.run(:character, fn repo, %{account: account} ->
        ensure_default_character(repo, account, realm)
      end)
      |> Repo.transaction()
      |> maybe_reconcile_special_profiles(telegram_attrs)
      |> case do
        {:ok, %{account: account, telegram_identity: telegram_identity, character: character}} ->
          {:ok,
           %{
             account: account,
             telegram_identity: telegram_identity,
             character: character
           }}

        error ->
          error
      end
    else
      nil -> {:error, :default_realm_not_found}
    end
  end

  defp ensure_default_character(
         repo,
         %Account{id: account_id} = account,
         %Realm{id: realm_id} = realm
       ) do
    playable_character =
      from(character in Character,
        where:
          character.account_id == ^account_id and character.status in [:active, :new] and
            fragment(
              "COALESCE(?->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')",
              character.metadata
            ),
        order_by: [
          asc:
            fragment(
              "CASE WHEN ? = 'active' THEN 0 ELSE 1 END",
              character.status
            ),
          asc: character.inserted_at
        ],
        limit: 1
      )
      |> repo.one()

    default_realm_character =
      from(character in Character,
        where:
          character.account_id == ^account_id and character.realm_id == ^realm_id and
            character.status in [:active, :new, :frozen] and
            fragment(
              "COALESCE(?->>'profile_kind', '') NOT IN ('arena', 'sealed_spirit')",
              character.metadata
            ),
        order_by: [
          asc:
            fragment(
              "CASE WHEN ? = 'active' THEN 0 WHEN ? = 'new' THEN 1 ELSE 2 END",
              character.status,
              character.status
            ),
          asc: character.inserted_at
        ],
        limit: 1
      )
      |> repo.one()

    case playable_character || default_realm_character do
      %Character{} = character ->
        {:ok, character}

      nil ->
        %Character{account_id: account.id, realm_id: realm.id}
        |> Character.changeset(%{name: unique_character_name(realm, account.display_name)})
        |> repo.insert()
    end
  end

  defp maybe_reconcile_special_profiles(
         {:ok, %{account: account} = result},
         %{telegram_user_id: telegram_user_id}
       ) do
    if SpecialProfiles.special_telegram_user_id?(telegram_user_id) do
      case Worlds.get_default_realm() do
        %Realm{} = realm ->
          case SpecialProfiles.reconcile(account, realm) do
            {:ok, profiles} ->
              # Preserve a legacy persisted choice when its old character was
              # converted into the sealed anchor. Fresh accounts deliberately
              # remain unset until the player chooses World mode.
              account =
                if is_binary(account.default_character_id) do
                  case set_default_world_character(account.id, profiles.character.id) do
                    {:ok, _character} -> Repo.get!(Account, account.id)
                    {:error, _reason} -> account
                  end
                else
                  account
                end

              {:ok,
               result
               |> Map.put(:account, account)
               |> Map.put(:character, profiles.character)
               |> Map.put(:characters, profiles.characters)}

            {:error, reason} ->
              {:error, reason}
          end

        nil ->
          {:error, :default_realm_not_found}
      end
    else
      {:ok, result}
    end
  end

  defp maybe_reconcile_special_profiles(result, _telegram_attrs), do: result

  defp active_migration_for_account?(account_id) do
    Repo.exists?(
      from migration in Migration,
        where: migration.account_id == ^account_id and migration.status == :active
    )
  end

  defp lock_account(account_id) do
    Account
    |> where([account], account.id == ^account_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp lock_owned_character(account_id, character_id) do
    Character
    |> where(
      [character],
      character.id == ^character_id and character.account_id == ^account_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp ordinary_world_character?(%Character{} = character) do
    not CharacterProfiles.arena?(character) and
      not CharacterProfiles.sealed_spirit?(character)
  end

  defp maybe_persist_default_world_character!(account, character) do
    if ordinary_world_character?(character) and character.status in [:new, :active, :frozen] do
      persist_default_world_character!(account, character)
    end
  end

  defp freeze_mode_siblings!(siblings, target) do
    target_mode = character_mode(target)

    Enum.each(siblings, fn sibling ->
      if sibling.id != target.id and sibling.status in [:new, :active] and
           character_mode(sibling) == target_mode do
        sibling
        |> Character.changeset(%{status: :frozen})
        |> Repo.update!()
      end
    end)
  end

  defp persist_default_world_character!(%Account{} = account, %Character{} = character) do
    if account.default_character_id == character.id do
      account
    else
      account
      |> Ecto.Changeset.change(default_character_id: character.id)
      |> Repo.update!()
    end
  end

  defp character_mode(%Character{} = character) do
    cond do
      CharacterProfiles.arena?(character) -> :arena
      CharacterProfiles.sealed_spirit?(character) -> :sealed_spirit
      true -> :world
    end
  end

  defp account_attrs(display_name, telegram_attrs) do
    %{
      display_name: display_name,
      handle: unique_handle(telegram_attrs.telegram_username || display_name),
      settings: telegram_account_settings(%{}, telegram_attrs)
    }
  end

  defp normalize_telegram_attrs(attrs) do
    with telegram_user_id when is_integer(telegram_user_id) <-
           attrs |> fetch_value("id") |> normalize_integer() do
      {:ok,
       %{
         telegram_user_id: telegram_user_id,
         telegram_username: fetch_value(attrs, "username"),
         first_name: fetch_value(attrs, "first_name"),
         last_name: fetch_value(attrs, "last_name"),
         language_code: fetch_value(attrs, "language_code"),
         is_bot: fetch_value(attrs, "is_bot") || false,
         photo_url: normalize_photo_url(fetch_value(attrs, "photo_url")),
         auth_data: stringify_keys(attrs),
         last_seen_at: DateTime.utc_now()
       }}
    else
      _ -> {:error, :invalid_update}
    end
  end

  defp display_name_from_telegram(telegram_attrs) do
    [telegram_attrs.first_name, telegram_attrs.last_name]
    |> Enum.reject(&is_nil_or_empty?/1)
    |> Enum.join(" ")
    |> case do
      "" -> telegram_attrs.telegram_username || "Безымянный маг"
      name -> name
    end
  end

  defp telegram_account_settings(existing_settings, telegram_attrs) do
    profile_settings =
      %{
        "locale" => telegram_attrs.language_code,
        "telegram_username" => telegram_attrs.telegram_username,
        "telegram_photo_url" => telegram_attrs.photo_url
      }
      |> Enum.reject(fn {_key, value} -> is_nil_or_empty?(value) end)
      |> Map.new()

    Map.merge(existing_settings || %{}, profile_settings)
  end

  defp normalize_photo_url(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> value
      _other -> nil
    end
  end

  defp normalize_photo_url(_value), do: nil

  defp unique_handle(base) do
    base
    |> slugify()
    |> case do
      "" -> "wizard"
      slug -> slug
    end
    |> Kernel.<>("-" <> random_suffix(3))
  end

  defp unique_character_name(%Realm{}, base) do
    base
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Странник"
      value -> value
    end
    |> String.slice(0, 28)
    |> Kernel.<>("-" <> random_suffix(2))
  end

  defp fetch_value(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, telegram_atom_key(key))
  end

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp stringify_keys(%_{} = struct), do: struct |> Map.from_struct() |> stringify_keys()

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp slugify(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp random_suffix(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp is_nil_or_empty?(value), do: is_nil(value) or value == ""

  defp telegram_atom_key("id"), do: :id
  defp telegram_atom_key("username"), do: :username
  defp telegram_atom_key("first_name"), do: :first_name
  defp telegram_atom_key("last_name"), do: :last_name
  defp telegram_atom_key("language_code"), do: :language_code
  defp telegram_atom_key("is_bot"), do: :is_bot
  defp telegram_atom_key(_key), do: nil
end
