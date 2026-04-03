defmodule MMGO.Accounts do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  def get_account!(id), do: Repo.get!(Account, id)
  def get_character!(id), do: Repo.get!(Character, id)

  def get_character_by_handle(realm_id, handle) when is_binary(realm_id) and is_binary(handle) do
    from(character in Character,
      join: account in Account,
      on: account.id == character.account_id,
      where: character.realm_id == ^realm_id and account.handle == ^handle,
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

  def restore_telegram_entry(attrs, opts \\ []) when is_map(attrs) do
    session =
      opts
      |> Keyword.get(:session, %{})
      |> stringify_keys()

    entry_attrs = stringify_keys(attrs)
    target = resolve_entry_target(entry_attrs)

    with {:ok, bootstrap} <- normalize_entry_bootstrap(entry_attrs, session),
         {:ok, restore} <- restore_telegram_player(bootstrap) do
      {:ok, build_entry_result(restore, target)}
    else
      {:error, reason} ->
        {:ok, recovery_entry_result(reason, target)}
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
    else
      nil -> {:error, :default_realm_not_found}
    end
  end

  defp refresh_telegram_account(identity, telegram_attrs) do
    identity = Repo.preload(identity, :account)

    with %Realm{} = realm <- Worlds.get_default_realm() do
      Multi.new()
      |> Multi.update(:telegram_identity, TelegramIdentity.changeset(identity, telegram_attrs))
      |> Multi.run(:character, fn repo, _changes ->
        ensure_default_character(repo, identity.account, realm)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{telegram_identity: telegram_identity, character: character}} ->
          {:ok,
           %{
             account: identity.account,
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

  defp restore_telegram_player(%{telegram_user: telegram_user}) do
    with {:ok, %{account: account, telegram_identity: identity, character: character}} <-
           provision_from_telegram(telegram_user) do
      {:ok,
       %{
         state: :first_open,
         account: account,
         telegram_identity: identity,
         character: Repo.preload(character, :realm)
       }}
    end
  end

  defp restore_telegram_player(%{telegram_user_id: telegram_user_id}) do
    case Repo.get_by(TelegramIdentity, telegram_user_id: telegram_user_id) do
      nil ->
        {:error, :telegram_identity_missing}

      identity ->
        identity = Repo.preload(identity, :account)

        with %Realm{} = realm <- Worlds.get_default_realm(),
             {:ok, character} <- ensure_default_character(Repo, identity.account, realm) do
          {:ok,
           %{
             state: :resume,
             account: identity.account,
             telegram_identity: identity,
             character: Repo.preload(character, :realm)
           }}
        else
          nil -> {:error, :default_realm_not_found}
          error -> error
        end
    end
  end

  defp ensure_default_character(
         repo,
         %Account{id: account_id} = account,
         %Realm{id: realm_id} = realm
       ) do
    case repo.get_by(Character, account_id: account_id, realm_id: realm_id) do
      %Character{} = character ->
        {:ok, character}

      nil ->
        %Character{account_id: account.id, realm_id: realm.id}
        |> Character.changeset(%{name: unique_character_name(realm, account.display_name)})
        |> repo.insert()
    end
  end

  defp account_attrs(display_name, telegram_attrs) do
    %{
      display_name: display_name,
      handle: unique_handle(telegram_attrs.telegram_username || display_name),
      settings: %{"locale" => telegram_attrs.language_code}
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
         auth_data: stringify_keys(attrs),
         last_seen_at: DateTime.utc_now()
       }}
    else
      _ -> {:error, :invalid_update}
    end
  end

  defp normalize_entry_bootstrap(entry_attrs, session) do
    session_user_id = session["telegram_user_id"] |> normalize_integer()
    telegram_user = extract_entry_telegram_user(entry_attrs)
    entry_user_id = telegram_user && fetch_value(telegram_user, "id") |> normalize_integer()

    {telegram_user_id, trusted_telegram_user} =
      cond do
        is_integer(session_user_id) and is_integer(entry_user_id) and session_user_id != entry_user_id ->
          {session_user_id, nil}

        is_integer(session_user_id) ->
          {session_user_id, telegram_user}

        is_integer(entry_user_id) ->
          {entry_user_id, telegram_user}

        true ->
          {nil, nil}
      end

    cond do
      is_map(trusted_telegram_user) and is_integer(telegram_user_id) ->
        {:ok, %{telegram_user: trusted_telegram_user, telegram_user_id: telegram_user_id}}

      is_integer(telegram_user_id) ->
        {:ok, %{telegram_user_id: telegram_user_id}}

      true ->
        {:error, :telegram_identity_missing}
    end
  end

  defp extract_entry_telegram_user(entry_attrs) do
    cond do
      is_map(entry_attrs["telegram_user"]) ->
        stringify_keys(entry_attrs["telegram_user"])

      Enum.any?(
        ["telegram_user_id", "id", "telegram_username", "username", "first_name", "last_name"],
        &Map.has_key?(entry_attrs, &1)
      ) ->
        %{}
        |> maybe_put("id", entry_attrs["telegram_user_id"] || entry_attrs["id"])
        |> maybe_put("username", entry_attrs["telegram_username"] || entry_attrs["username"])
        |> maybe_put("first_name", entry_attrs["first_name"])
        |> maybe_put("last_name", entry_attrs["last_name"])
        |> maybe_put("language_code", entry_attrs["language_code"])
        |> maybe_put("is_bot", entry_attrs["is_bot"])

      true ->
        nil
    end
  end

  defp build_entry_result(restore, target) do
    state =
      cond do
        is_map(target) -> :deep_link
        true -> restore.state
      end

    notice =
      case target do
        %{valid?: false} -> invalid_target_notice()
        _ -> nil
      end

    %{
      state: state,
      account: restore.account,
      telegram_identity: restore.telegram_identity,
      character: restore.character,
      realm: restore.character.realm,
      target: target,
      notice: notice,
      recovery: nil,
      session: build_entry_session(restore.telegram_identity.telegram_user_id, target)
    }
  end

  defp recovery_entry_result(reason, target) do
    %{
      state: :recovery,
      account: nil,
      telegram_identity: nil,
      character: nil,
      realm: Worlds.get_default_realm(),
      target: target,
      notice: nil,
      session: build_entry_session(nil, target),
      recovery: %{
        reason: reason,
        title: "We couldn't restore your traveler seal.",
        body:
          "Try again from Telegram, or reopen MMGO from the bot to refresh your link."
      }
    }
  end

  defp build_entry_session(telegram_user_id, target) do
    %{}
    |> maybe_put("telegram_user_id", telegram_user_id && Integer.to_string(telegram_user_id))
    |> maybe_put("target", target && target.id)
  end

  defp resolve_entry_target(entry_attrs) do
    case entry_attrs["target"] do
      nil ->
        nil

      target ->
        case entry_target_label(target) do
          nil ->
            %{id: "map", label: "World Map", valid?: false, requested: target}

          label ->
            %{id: target, label: label, valid?: true, requested: target}
        end
    end
  end

  defp entry_target_label("map"), do: "World Map"
  defp entry_target_label("journey"), do: "Journey Log"
  defp entry_target_label("notifications"), do: "Notifications"
  defp entry_target_label("shell"), do: "Player Shell"
  defp entry_target_label(_target), do: nil

  defp invalid_target_notice,
    do: "That destination has already changed. We brought you to the nearest valid view."

  defp display_name_from_telegram(telegram_attrs) do
    [telegram_attrs.first_name, telegram_attrs.last_name]
    |> Enum.reject(&is_nil_or_empty?/1)
    |> Enum.join(" ")
    |> case do
      "" -> telegram_attrs.telegram_username || "Unnamed Wizard"
      name -> name
    end
  end

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
      "" -> "Wanderer"
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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
