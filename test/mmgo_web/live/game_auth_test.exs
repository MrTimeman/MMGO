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
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
    session = %{"current_account_id" => owner.id, "current_character_id" => character.id}

    assert {:cont, socket} = GameAuth.on_mount(:require_character, %{}, session, socket)
    assert socket.assigns.current_scope.character.id == character.id
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
