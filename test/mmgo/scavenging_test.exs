defmodule MMGO.ScavengingTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Scavenging.{Attempt, CompleteAttemptWorker}
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, wilderness} =
      Worlds.create_location(realm, %{
        slug: "wild-grove",
        name: "Wild Grove",
        kind: :wilderness,
        x: 120,
        y: 80,
        safe_zone: false
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 30,
        y: 40,
        safe_zone: true
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Grove Path",
        origin_location_id: wilderness.id,
        destination_location_id: city.id,
        travel_days: 4,
        risk_level: 10,
        bidirectional: true
      })

    {:ok, herb_template} =
      Inventory.create_item_template(%{
        code: "wild_herb",
        name: "Wild Herb",
        item_type: :tool,
        stackable: true,
        weight: 1,
        max_durability: 0,
        actions: [
          %{
            key: "use",
            action_kind: :repair,
            targeting: :self,
            effects: [
              %{
                applies_to: :caster,
                state: "regenerating",
                intensity: 1,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      })

    character = character_fixture(realm, wilderness, "forager", "Forager")
    outsider = character_fixture(realm, city, "outsider", "Outsider")

    {:ok, resource_cache} =
      Scavenging.ensure_resource_cache(wilderness, %{
        resource_code: "herbs",
        quantity_total: 3,
        quantity_remaining: 3,
        respawn_game_days: 7,
        item_template_id: herb_template.id
      })

    %{
      realm: realm,
      wilderness: wilderness,
      city: city,
      route: route,
      herb_template: herb_template,
      character: character,
      outsider: outsider,
      resource_cache: resource_cache
    }
  end

  test "start_attempt/4 creates an active attempt, reserves resources, and schedules completion",
       %{character: character, resource_cache: resource_cache} do
    started_at = ~U[2026-03-27 12:00:00Z]

    assert {:ok, %{attempt: attempt, resource_cache: updated_cache, job: job}} =
             Scavenging.start_attempt(character, resource_cache, 2, started_at: started_at)

    assert attempt.status == :active
    assert attempt.quantity_requested == 2
    assert DateTime.compare(attempt.completes_at, Clock.arrival_at(started_at, 2)) == :eq
    assert updated_cache.quantity_remaining == 1
    assert updated_cache.status == :available

    oban_job = Repo.get!(Oban.Job, job.id)
    assert oban_job.worker == "MMGO.Scavenging.CompleteAttemptWorker"
  end

  test "complete_attempt_by_id/2 grants items and XP", %{
    character: character,
    resource_cache: resource_cache,
    herb_template: herb_template
  } do
    {:ok, %{attempt: attempt}} = Scavenging.start_attempt(character, resource_cache, 2)

    assert {:ok, %{attempt: completed_attempt, character: updated_character}} =
             Scavenging.complete_attempt_by_id(attempt.id, force: true)

    assert completed_attempt.status == :completed
    assert completed_attempt.quantity_yielded == 2
    assert updated_character.xp == 6

    inventory_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: herb_template.id
      )

    assert inventory_item.quantity == 2
  end

  test "refresh_due_resource_caches/1 restores respawning caches", %{
    character: character,
    resource_cache: resource_cache
  } do
    {:ok, %{resource_cache: depleted_cache}} =
      Scavenging.start_attempt(character, resource_cache, 3, started_at: ~U[2026-03-27 12:00:00Z])

    assert depleted_cache.status == :respawning

    [refreshed_cache] = Scavenging.refresh_due_resource_caches(~U[2026-03-27 12:27:42Z])
    assert refreshed_cache.status == :available
    assert refreshed_cache.quantity_remaining == 3
  end

  test "start_attempt/4 rejects characters outside the resource location", %{
    outsider: outsider,
    resource_cache: resource_cache
  } do
    assert {:error, changeset} = Scavenging.start_attempt(outsider, resource_cache, 1)

    assert %{status: ["character must be at the resource location to scavenge"]} =
             errors_on(changeset)
  end

  test "start_attempt/4 rejects characters who are travelling", %{
    character: character,
    route: route,
    resource_cache: resource_cache
  } do
    assert {:ok, _journey_result} = Travel.start_journey(character, route)

    assert {:error, changeset} = Scavenging.start_attempt(character, resource_cache, 1)
    assert %{status: ["character cannot scavenge while travelling"]} = errors_on(changeset)
  end

  test "start_attempt/4 rejects characters on an active expedition", %{
    character: character,
    resource_cache: resource_cache
  } do
    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Foragers"})
    {:ok, %{expedition: _expedition}} = Parties.start_expedition(party)

    assert {:error, changeset} = Scavenging.start_attempt(character, resource_cache, 1)
    assert %{status: ["character cannot scavenge while on an expedition"]} = errors_on(changeset)
  end

  test "worker completes due attempts", %{character: character, resource_cache: resource_cache} do
    {:ok, %{attempt: attempt}} = Scavenging.start_attempt(character, resource_cache, 1)

    assert :ok = CompleteAttemptWorker.perform(%Oban.Job{args: %{"attempt_id" => attempt.id}})

    updated_attempt = Repo.get!(Attempt, attempt.id)
    assert updated_attempt.status == :completed
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
