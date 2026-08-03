defmodule MMGO.Telegram.RoadCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Notifications
  alias MMGO.Overworld
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, wilderness} =
      Worlds.create_location(realm, %{
        slug: "wilds",
        name: "Wilds",
        kind: :wilderness,
        x: 20,
        y: 20,
        safe_zone: false
      })

    initiator = character_fixture(realm, wilderness, "roadstarter", "Road Starter")
    target = character_fixture(realm, wilderness, "roadtarget", "Road Target")

    %{initiator: initiator, target: target}
  end

  test "/road commands create, inspect, and attack an overworld encounter", %{
    initiator: initiator
  } do
    assert {:ok, encounter_text} =
             Commands.process_message(initiator, %{"text" => "/road encounter roadtarget"})

    assert encounter_text =~ "Дорожная встреча создана"

    [encounter] = Overworld.list_open_encounters_for_character(initiator.id)

    assert {:ok, status_text} = Commands.process_message(initiator, %{"text" => "/road status"})
    assert status_text =~ encounter.id

    assert {:ok, attack_text} =
             Commands.process_message(initiator, %{"text" => "/road attack #{encounter.id}"})

    assert attack_text =~ "Дорожный бой начат"

    loaded_encounter = Overworld.get_encounter!(encounter.id)
    assert loaded_encounter.status == :escalated
    assert Combat.get_combat!(loaded_encounter.combat_id).kind == :overworld_encounter
  end

  test "/road accept and reject are command fallbacks for contact consent", %{
    initiator: initiator,
    target: target
  } do
    assert {:ok, request_text} =
             Commands.process_message(initiator, %{"text" => "/road talk roadtarget"})

    assert request_text =~ "Запрос на обмен Telegram-контактами отправлен"
    [rejected_encounter] = Overworld.list_open_encounters_for_character(initiator.id)

    assert {:ok, reject_text} =
             Commands.process_message(target, %{
               "text" => "/road reject #{rejected_encounter.id}"
             })

    assert reject_text =~ "Запрос отклонён"
    assert Overworld.get_encounter!(rejected_encounter.id).status == :avoided

    rejected_notification =
      initiator.id
      |> Notifications.list_notifications()
      |> Enum.find(&(&1.kind == "overworld_contact_rejected"))

    refute Map.has_key?(rejected_notification.payload, "telegram_username")

    assert {:ok, _request_text} =
             Commands.process_message(initiator, %{"text" => "/road talk roadtarget"})

    [accepted_encounter] = Overworld.list_open_encounters_for_character(initiator.id)

    assert {:ok, accept_text} =
             Commands.process_message(target, %{
               "text" => "/road accept #{accepted_encounter.id}"
             })

    assert accept_text =~ "Запрос принят"
    assert Overworld.get_encounter!(accepted_encounter.id).status == :greeted
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
