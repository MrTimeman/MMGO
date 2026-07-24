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
      "language_code" => "en",
      "photo_url" => "https://t.me/i/userpic/320/arcanist.jpg"
    }

    assert {:ok, %{account: account, telegram_identity: identity, character: character}} =
             Accounts.provision_from_telegram(telegram_user)

    assert account.display_name == "Arc Anist"
    assert account.handle =~ ~r/^arcanist-/

    assert account.settings["telegram_photo_url"] ==
             "https://t.me/i/userpic/320/arcanist.jpg"

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
               "last_name" => "Queen",
               "photo_url" => "https://t.me/i/userpic/320/emberqueen.jpg"
             })

    assert same_account.id == account.id
    assert same_account.display_name == "Ember Queen"
    assert same_account.settings["telegram_username"] == "emberqueen"

    assert same_account.settings["telegram_photo_url"] ==
             "https://t.me/i/userpic/320/emberqueen.jpg"

    assert identity.telegram_username == "emberqueen"
    assert Repo.aggregate(Account, :count, :id) == 1
    assert Repo.aggregate(TelegramIdentity, :count, :id) == 1
    assert Repo.aggregate(Character, :count, :id) == 1
  end

  test "provision_from_telegram/1 rejects invalid payloads" do
    assert {:error, :invalid_update} = Accounts.provision_from_telegram(%{"username" => "no-id"})
  end

  test "get_active_character_for_account/2 enforces ownership and active statuses", %{
    realm: realm
  } do
    owner = account_fixture("scope-owner")
    stranger = account_fixture("scope-stranger")
    inactive_owner = account_fixture("inactive-owner")
    active_character = character_fixture(owner, realm, "Scope Owner", :active)
    stranger_character = character_fixture(stranger, realm, "Scope Stranger", :active)
    inactive_character = character_fixture(inactive_owner, realm, "Sleeping Owner", :new)

    assert {:ok, scoped_character} =
             Accounts.get_active_character_for_account(owner.id, active_character.id)

    assert scoped_character.account.id == owner.id

    assert {:error, :not_found} =
             Accounts.get_active_character_for_account(owner.id, stranger_character.id)

    assert {:error, :inactive} =
             Accounts.get_active_character_for_account(inactive_owner.id, inactive_character.id)

    suspended_owner =
      owner
      |> Ecto.Changeset.change(status: :suspended)
      |> Repo.update!()

    assert {:error, :inactive} =
             Accounts.get_active_character_for_account(suspended_owner.id, active_character.id)
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
