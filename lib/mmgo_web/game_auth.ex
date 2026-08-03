defmodule MMGOWeb.GameAuth do
  @moduledoc """
  Shared current-player scope for game LiveViews.

  Browser code provides no authority beyond the signed session. This module
  verifies that the session account owns the requested active character before
  assigning the scope used by every protected game route.
  """

  alias MMGO.Accounts

  @type scope :: %{account: MMGO.Accounts.Account.t(), character: MMGO.Accounts.Character.t()}

  @spec current_scope(map()) :: {:ok, scope()} | {:error, :not_found | :inactive}
  def current_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         character_id when is_binary(character_id) <- Map.get(session, "current_character_id"),
         {:ok, character} <- Accounts.get_active_character_for_account(account_id, character_id) do
      {:ok, %{account: character.account, character: character}}
    else
      {:error, reason} when reason in [:not_found, :inactive] -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  @spec current_scope(term()) :: {:error, :not_found}
  def current_scope(_session), do: {:error, :not_found}

  @doc false
  def migration_scope(session) when is_map(session) do
    with account_id when is_binary(account_id) <- Map.get(session, "current_account_id"),
         character_id when is_binary(character_id) <- Map.get(session, "current_character_id"),
         {:ok, character} <-
           Accounts.get_migration_character_for_account(account_id, character_id) do
      {:ok, %{account: character.account, character: character}}
    else
      {:error, reason} when reason in [:not_found, :inactive] -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  def migration_scope(_session), do: {:error, :not_found}

  def on_mount(:require_character, _params, session, socket) do
    case current_scope(session) do
      {:ok, scope} ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_scope, scope)
          |> Phoenix.LiveView.attach_hook(
            :active_character_event_guard,
            :handle_event,
            fn _event, _params, socket -> active_character_guard(scope, socket) end
          )
          |> Phoenix.LiveView.attach_hook(
            :active_character_info_guard,
            :handle_info,
            fn _message, socket -> active_character_guard(scope, socket) end
          )

        {:cont, socket}

      {:error, _reason} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Нужно подтвердить вход через Telegram.")
         |> Phoenix.LiveView.push_navigate(to: "/play")}
    end
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

  defp active_character_guard(scope, socket) do
    case Accounts.get_active_character_for_account(scope.account.id, scope.character.id) do
      {:ok, _character} ->
        {:cont, socket}

      {:error, _reason} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "Этот персонаж уже заморожен. Выберите действующий профиль."
         )
         |> Phoenix.LiveView.redirect(to: "/characters")}
    end
  end
end
