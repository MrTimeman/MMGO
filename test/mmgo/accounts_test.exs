defmodule MMGO.AccountsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    {:ok, _city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Test Wizard", handle: "test-wizard"})
      |> Repo.insert!()

    character =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{name: "Test Wizard", status: :active, level: 1, xp: 0})
      |> Repo.insert!()

    %{realm: realm, account: account, character: character}
  end

  test "get_account!/1 returns account by id", %{account: account} do
    assert Accounts.get_account!(account.id).id == account.id
  end

  test "get_character!/1 returns character by id", %{character: character} do
    assert Accounts.get_character!(character.id).id == character.id
  end

  test "get_character_by_handle/2 finds character by realm and account handle", %{
    realm: realm,
    account: account,
    character: character
  } do
    result = Accounts.get_character_by_handle(realm.id, account.handle)
    assert result.id == character.id
  end

  test "get_character_by_handle/2 returns nil for unknown handle", %{realm: realm} do
    assert Accounts.get_character_by_handle(realm.id, "no-one") == nil
  end
end
