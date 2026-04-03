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

  test "restore_telegram_entry/2 provisions a first-open entry for a new Telegram player", %{
    realm: realm
  } do
    assert {:ok, result} =
             Accounts.restore_telegram_entry(%{
               "telegram_user" => %{
                 "id" => 3003,
                 "username" => "moonrunner",
                 "first_name" => "Moon",
                 "last_name" => "Runner",
                 "language_code" => "en"
               }
             })

    assert result.state == :first_open
    assert result.account.display_name == "Moon Runner"
    assert result.character.realm_id == realm.id
    assert result.realm.id == realm.id
    assert result.session["telegram_user_id"] == "3003"
  end

  test "restore_telegram_entry/2 resumes an existing Telegram player and repairs the default character" do
    assert {:ok, %{character: original_character}} =
             Accounts.provision_from_telegram(%{
               "id" => 4004,
               "username" => "starlit",
               "first_name" => "Star"
             })

    Repo.delete!(original_character)

    assert {:ok, result} =
             Accounts.restore_telegram_entry(%{}, session: %{"telegram_user_id" => "4004"})

    assert result.state == :resume
    assert result.character.id != original_character.id
    assert result.character.level == 1
    assert result.session["telegram_user_id"] == "4004"
    assert Repo.aggregate(Character, :count, :id) == 1
  end
end
