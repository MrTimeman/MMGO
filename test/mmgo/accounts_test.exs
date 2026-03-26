defmodule MMGO.AccountsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    %{realm: realm}
  end

  test "provision_from_telegram/1 creates account, identity, and starter character", %{
    realm: realm
  } do
    telegram_user = %{
      "id" => 1001,
      "username" => "arcanist",
      "first_name" => "Arc",
      "last_name" => "Anist",
      "language_code" => "en"
    }

    assert {:ok, %{account: account, telegram_identity: identity, character: character}} =
             Accounts.provision_from_telegram(telegram_user)

    assert account.display_name == "Arc Anist"
    assert account.handle =~ ~r/^arcanist-/
    assert identity.telegram_user_id == 1001
    assert character.realm_id == realm.id
    assert character.level == 1
    assert Repo.aggregate(Account, :count, :id) == 1
    assert Repo.aggregate(TelegramIdentity, :count, :id) == 1
    assert Repo.aggregate(Character, :count, :id) == 1
  end

  test "provision_from_telegram/1 updates an existing identity without duplicating records" do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 2002,
               "username" => "embermage",
               "first_name" => "Ember"
             })

    assert {:ok, %{account: same_account, telegram_identity: identity}} =
             Accounts.provision_from_telegram(%{
               "id" => 2002,
               "username" => "emberqueen",
               "first_name" => "Ember",
               "last_name" => "Queen"
             })

    assert same_account.id == account.id
    assert identity.telegram_username == "emberqueen"
    assert Repo.aggregate(Account, :count, :id) == 1
    assert Repo.aggregate(TelegramIdentity, :count, :id) == 1
    assert Repo.aggregate(Character, :count, :id) == 1
  end

  test "provision_from_telegram/1 rejects invalid payloads" do
    assert {:error, :invalid_update} = Accounts.provision_from_telegram(%{"username" => "no-id"})
  end
end
