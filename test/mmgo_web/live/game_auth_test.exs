defmodule MMGOWeb.GameAuthTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGOWeb.GameAuth

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    owner = account_fixture("scope-owner")
    stranger = account_fixture("scope-stranger")
    inactive_owner = account_fixture("inactive-owner")
    character = character_fixture(owner, realm, "Scope Owner", :active)
    stranger_character = character_fixture(stranger, realm, "Scope Stranger", :active)
    inactive_character = character_fixture(inactive_owner, realm, "Sleeping Owner", :new)

    %{
      owner: owner,
      character: character,
      stranger_character: stranger_character,
      inactive_owner: inactive_owner,
      inactive_character: inactive_character
    }
  end

  test "builds scope only for the account-owned active character", %{
    owner: owner,
    character: character
  } do
    session = %{"current_account_id" => owner.id, "current_character_id" => character.id}

    assert {:ok, scope} = GameAuth.current_scope(session)
    assert scope.account.id == owner.id
    assert scope.character.id == character.id
    assert scope.game_mode == :world
  end

  test "rejects missing, cross-account, and inactive session state", %{
    owner: owner,
    inactive_owner: inactive_owner,
    stranger_character: stranger_character,
    inactive_character: inactive_character
  } do
    assert {:error, :not_found} = GameAuth.current_scope(%{})

    assert {:error, :not_found} =
             GameAuth.current_scope(%{
               "current_account_id" => owner.id,
               "current_character_id" => stranger_character.id
             })

    assert {:error, :inactive} =
             GameAuth.current_scope(%{
               "current_account_id" => inactive_owner.id,
               "current_character_id" => inactive_character.id
             })
  end

  test "on_mount assigns current scope for a valid session", %{owner: owner, character: character} do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }

    session = %{"current_account_id" => owner.id, "current_character_id" => character.id}

    assert {:cont, socket} = GameAuth.on_mount(:require_character, %{}, session, socket)
    assert socket.assigns.current_scope.character.id == character.id
  end

  test "on_mount sends unsigned visitors to login and signed accounts to mode choice", %{
    owner: owner
  } do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }

    assert {:halt, unsigned_socket} =
             GameAuth.on_mount(:require_world_character, %{}, %{}, socket)

    assert unsigned_socket.redirected == {:live, :redirect, %{kind: :push, to: "/play"}}

    assert {:halt, account_socket} =
             GameAuth.on_mount(
               :require_world_character,
               %{},
               %{"current_account_id" => owner.id},
               socket
             )

    assert account_socket.redirected == {:live, :redirect, %{kind: :push, to: "/mode"}}
  end

  test "the migration-only scope admits a frozen owned character without broadening game scope",
       %{
         owner: owner,
         character: character
       } do
    frozen_character =
      character
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()

    session = %{"current_account_id" => owner.id, "current_character_id" => frozen_character.id}

    assert {:error, :inactive} = GameAuth.current_scope(session)
    assert {:ok, scope} = GameAuth.migration_scope(session)
    assert scope.character.status == :frozen
  end

  test "arena and world scopes reject a character from the other selected mode", %{
    owner: owner,
    character: character
  } do
    world_session = %{
      "current_account_id" => owner.id,
      "current_character_id" => character.id,
      "game_mode" => "world"
    }

    assert {:ok, _scope} = GameAuth.world_scope(world_session)
    assert {:error, :not_found} = GameAuth.arena_scope(world_session)

    arena_character =
      character
      |> Character.changeset(%{metadata: %{"profile_kind" => "arena"}})
      |> Repo.update!()

    arena_session = %{
      world_session
      | "current_character_id" => arena_character.id,
        "game_mode" => "arena"
    }

    assert {:ok, scope} = GameAuth.arena_scope(arena_session)
    assert scope.game_mode == :arena
    assert {:error, :not_found} = GameAuth.world_scope(arena_session)
  end

  defp account_fixture(handle) do
    %Account{}
    |> Account.registration_changeset(%{display_name: handle, handle: handle})
    |> Repo.insert!()
  end

  defp character_fixture(account, realm, name, status) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: status})
    |> Repo.insert!()
  end
end
