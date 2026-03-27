defmodule MMGO.NotificationWorkerHooksTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Academy
  alias MMGO.Academy.CompleteEnrollmentWorker
  alias MMGO.Inventory
  alias MMGO.Notifications.Notification
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Scavenging.CompleteAttemptWorker
  alias MMGO.Travel
  alias MMGO.Travel.CompleteJourneyWorker
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 50,
        y: 50,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 1,
        risk_level: 10,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "notify_ration",
        name: "Notify Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "worker", "Worker Mage", 999_001)
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 5})

    %{realm: realm, city: city, tower: tower, route: route, character: character}
  end

  test "journey completion worker queues a notification", %{character: character, route: route} do
    {:ok, %{journey: journey}} =
      Travel.start_journey(character, route, started_at: ~U[2026-03-27 12:00:00Z])

    assert :ok = CompleteJourneyWorker.perform(%Oban.Job{args: %{"journey_id" => journey.id}})
    notification = Repo.get_by!(Notification, character_id: character.id, kind: "journey_arrived")
    assert notification.status == :pending
  end

  test "academy completion worker queues a notification", %{character: character} do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    assert :ok =
             CompleteEnrollmentWorker.perform(%Oban.Job{
               args: %{"enrollment_id" => enrollment.id}
             })

    notification =
      Repo.get_by!(Notification, character_id: character.id, kind: "academy_completed")

    assert notification.status == :pending
  end

  test "scavenging completion worker queues a notification", %{character: character, tower: tower} do
    {:ok, resource_cache} =
      Scavenging.ensure_resource_cache(tower, %{
        resource_code: "arcane_debris",
        quantity_total: 1,
        quantity_remaining: 1,
        respawn_game_days: 7
      })

    character =
      character |> Character.travel_changeset(%{current_location_id: tower.id}) |> Repo.update!()

    {:ok, %{attempt: attempt}} = Scavenging.start_attempt(character, resource_cache, 1)

    assert :ok = CompleteAttemptWorker.perform(%Oban.Job{args: %{"attempt_id" => attempt.id}})

    notification =
      Repo.get_by!(Notification, character_id: character.id, kind: "scavenge_completed")

    assert notification.status == :pending
  end

  defp character_fixture(realm, location, handle, name, telegram_user_id) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %TelegramIdentity{account_id: account.id}
    |> TelegramIdentity.changeset(%{
      telegram_user_id: telegram_user_id,
      telegram_username: handle,
      first_name: name,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
