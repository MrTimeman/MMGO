defmodule MMGOWeb.GameAuth do
  @moduledoc """
  Shared current-player scope for game LiveViews.

  Browser code provides no authority beyond the signed session. This module
  verifies that the session account owns the requested active character before
  assigning the scope used by every protected game route.
  """

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, CharacterProfiles}
  alias MMGO.Repo

  @type game_mode :: :world | :arena
  @type scope :: %{
          account: MMGO.Accounts.Account.t(),
          character: MMGO.Accounts.Character.t() | nil,
          game_mode: game_mode() | nil
        }

  @spec current_scope(map()) :: {:ok, scope()} | {:error, :not_found | :inactive}
  def current_scope(session) when is_map(session) do
    world_scope(session)
  end

  @spec current_scope(term()) :: {:error, :not_found}
  def current_scope(_session), do: {:error, :not_found}

  @doc "Builds an account-only scope for choosing a game mode or creating an Arena profile."
  @spec account_scope(map()) :: {:ok, scope()} | {:error, :not_found | :inactive}
  def account_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         %Account{status: :active} = account <- Repo.get(Account, account_id) do
      {:ok, %{account: account, character: nil, game_mode: nil}}
    else
      %Account{} -> {:error, :inactive}
      _other -> {:error, :not_found}
    end
  end

  def account_scope(_session), do: {:error, :not_found}

  @doc "Builds the ordinary-world scope. A missing legacy mode defaults to the world."
  @spec world_scope(map()) :: {:ok, scope()} | {:error, :not_found | :inactive}
  def world_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         character_id when is_binary(character_id) <- Map.get(session, "current_character_id"),
         true <- world_mode?(Map.get(session, "game_mode")),
         {:ok, character} <- Accounts.get_active_character_for_account(account_id, character_id) do
      if CharacterProfiles.arena?(character) do
        {:error, :not_found}
      else
        {:ok, %{account: character.account, character: character, game_mode: :world}}
      end
    else
      {:error, reason} when reason in [:not_found, :inactive] -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  def world_scope(_session), do: {:error, :not_found}

  @doc "Builds a scope only for an explicitly selected Arena character."
  @spec arena_scope(map()) :: {:ok, scope()} | {:error, :not_found | :inactive}
  def arena_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         character_id when is_binary(character_id) <- Map.get(session, "current_character_id"),
         true <- Map.get(session, "game_mode") == "arena",
         {:ok, character} <- Accounts.get_active_character_for_account(account_id, character_id),
         true <- CharacterProfiles.arena?(character) do
      {:ok, %{account: character.account, character: character, game_mode: :arena}}
    else
      {:error, reason} when reason in [:not_found, :inactive] -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  def arena_scope(_session), do: {:error, :not_found}

  @doc false
  def migration_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         character_id when is_binary(character_id) <- Map.get(session, "current_character_id"),
         {:ok, character} <-
           Accounts.get_migration_character_for_account(account_id, character_id) do
      {:ok, %{account: character.account, character: character, game_mode: :world}}
    else
      {:error, reason} when reason in [:not_found, :inactive] -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  def migration_scope(_session), do: {:error, :not_found}

  def on_mount(:require_account, _params, session, socket) do
    case account_scope(session) do
      {:ok, scope} ->
        {:cont, Phoenix.Component.assign(socket, :current_scope, scope)}

      {:error, _reason} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Нужно подтвердить вход через Telegram.")
         |> Phoenix.LiveView.push_navigate(to: "/play")}
    end
  end

  def on_mount(:require_character, params, session, socket) do
    on_mount(:require_world_character, params, session, socket)
  end

  def on_mount(:require_world_character, _params, session, socket) do
    mount_game_scope(world_scope(session), :world, session, socket)
  end

  def on_mount(:require_arena_character, _params, session, socket) do
    mount_game_scope(arena_scope(session), :arena, session, socket)
  end

  def on_mount(:require_migration_character, _params, session, socket) do
    case migration_scope(session) do
      {:ok, scope} ->
        {:cont, Phoenix.Component.assign(socket, :current_scope, scope)}

      {:error, _reason} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Нужно подтвердить вход через Telegram.")
         |> Phoenix.LiveView.push_navigate(to: "/play")}
    end
  end

  defp mount_game_scope(scope_result, mode, session, socket) do
    case scope_result do
      {:ok, scope} ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_scope, scope)
          |> Phoenix.LiveView.attach_hook(
            :active_character_event_guard,
            :handle_event,
            fn _event, _params, socket -> active_character_guard(scope, mode, socket) end
          )
          |> Phoenix.LiveView.attach_hook(
            :active_character_info_guard,
            :handle_info,
            fn _message, socket -> active_character_guard(scope, mode, socket) end
          )

        {:cont, socket}

      {:error, _reason} ->
        case account_scope(session) do
          {:ok, _account_scope} -> invalid_game_scope(socket)
          {:error, _reason} -> unauthenticated_scope(socket)
        end
    end
  end

  defp active_character_guard(scope, mode, socket) do
    session = %{
      "current_account_id" => scope.account.id,
      "current_character_id" => scope.character.id,
      "game_mode" => Atom.to_string(mode)
    }

    result = if mode == :arena, do: arena_scope(session), else: world_scope(session)

    case result do
      {:ok, _scope} ->
        {:cont, socket}

      {:error, _reason} ->
        redirect_path = if mode == :world, do: "/characters", else: "/mode"

        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           unavailable_profile_message(mode)
         )
         |> Phoenix.LiveView.redirect(to: redirect_path)}
    end
  end

  defp unavailable_profile_message(:world),
    do: "Этот персонаж больше недоступен. Выберите активного персонажа."

  defp unavailable_profile_message(:arena),
    do: "Профиль Арены больше недоступен. Выберите режим ещё раз."

  defp invalid_game_scope(socket) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(:error, "Сначала выберите режим игры.")
     |> Phoenix.LiveView.push_navigate(to: "/mode")}
  end

  defp unauthenticated_scope(socket) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(:error, "Нужно подтвердить вход через Telegram.")
     |> Phoenix.LiveView.push_navigate(to: "/play")}
  end

  defp world_mode?(nil), do: true
  defp world_mode?("world"), do: true
  defp world_mode?(_mode), do: false
end
