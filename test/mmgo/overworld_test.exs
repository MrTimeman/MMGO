defmodule MMGO.OverworldTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.Resolution
  alias MMGO.Overworld
  alias MMGO.Overworld.Response
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, wilderness} =
      Worlds.create_location(realm, %{
        slug: "wilds",
        name: "Wilds",
        kind: :wilderness,
        x: 20,
        y: 20,
        safe_zone: false
      })

    initiator = character_fixture(realm, wilderness, "initiator", "Initiator")
    target = character_fixture(realm, wilderness, "target", "Target")
    city_target = character_fixture(realm, city, "citytarget", "City Target")

    %{
      realm: realm,
      city: city,
      wilderness: wilderness,
      initiator: initiator,
      target: target,
      city_target: city_target
    }
  end

  test "create_encounter/3 creates a pending overworld encounter", %{
    initiator: initiator,
    target: target
  } do
    assert {:ok, encounter} = Overworld.create_encounter(initiator, target)
    assert encounter.status == :pending
    assert encounter.location_id == initiator.current_location_id
  end

  test "greet and trade can resolve a social encounter", %{initiator: initiator, target: target} do
    {:ok, encounter} = Overworld.create_encounter(initiator, target)

    assert {:ok, %{encounter: pending_encounter}} =
             Overworld.respond(encounter, initiator, :greet)

    assert pending_encounter.status == :pending

    assert {:ok, %{encounter: resolved_encounter}} = Overworld.respond(encounter, target, :trade)
    assert resolved_encounter.status == :trading
  end

  test "contact request records implicit initiator consent without contact details", %{
    initiator: initiator,
    target: target
  } do
    Phoenix.PubSub.subscribe(MMGO.PubSub, Overworld.character_topic(target.id))

    assert {:ok, encounter} =
             Overworld.request_contact(initiator, target, %{
               metadata: %{
                 source: "road",
                 telegram_username: "must-not-leak",
                 nested: %{telegram_user_id: 123}
               }
             })

    assert encounter.status == :pending
    assert Overworld.contact_request?(encounter)
    assert encounter.metadata["source"] == "road"
    refute Map.has_key?(encounter.metadata, "telegram_username")
    refute Map.has_key?(encounter.metadata["nested"], "telegram_user_id")
    assert Repo.aggregate(Response, :count, :id) == 0
    assert_receive {:overworld_contact_updated, encounter_id}
    assert encounter_id == encounter.id
  end

  test "only the target can accept a contact request and legacy responses cannot bypass consent",
       %{
         initiator: initiator,
         target: target
       } do
    {:ok, encounter} = Overworld.request_contact(initiator, target)

    assert {:error, legacy_changeset} = Overworld.respond(encounter, initiator, :greet)

    assert %{status: ["contact requests require an explicit consent decision"]} =
             errors_on(legacy_changeset)

    assert {:error, role_changeset} =
             Overworld.respond_to_contact(encounter, initiator, :accept)

    assert %{status: ["only the requested traveler may answer"]} = errors_on(role_changeset)

    assert {:ok, %{encounter: accepted, response: response, decision: :accept}} =
             Overworld.respond_to_contact(encounter, target, "accept")

    assert accepted.status == :greeted
    assert accepted.metadata["contact_decision"] == "accept"
    assert accepted.metadata["contact_responder_character_id"] == target.id
    refute Map.has_key?(accepted.metadata, "telegram_username")
    assert response.action == :accept_contact

    assert {:error, finished_changeset} =
             Overworld.respond_to_contact(accepted, initiator, :cancel)

    assert %{status: ["contact request is not pending"]} = errors_on(finished_changeset)
  end

  test "target may decline and only the initiator may cancel", %{
    initiator: initiator,
    target: target
  } do
    {:ok, declined_request} = Overworld.request_contact(initiator, target)

    assert {:error, cancel_changeset} =
             Overworld.respond_to_contact(declined_request, target, :cancel)

    assert %{status: ["only the requesting traveler may cancel"]} =
             errors_on(cancel_changeset)

    assert {:ok, %{encounter: declined, decision: :decline}} =
             Overworld.respond_to_contact(declined_request, target, :decline)

    assert declined.status == :avoided
    assert declined.metadata["contact_decision"] == "decline"

    {:ok, cancelled_request} = Overworld.request_contact(initiator, target)

    assert {:ok, %{encounter: cancelled, decision: :cancel}} =
             Overworld.respond_to_contact(cancelled_request, initiator, "cancel")

    assert cancelled.status == :avoided
    assert cancelled.metadata["contact_decision"] == "cancel"
  end

  test "a reverse duplicate contact request is rejected", %{
    initiator: initiator,
    target: target
  } do
    assert {:ok, _encounter} = Overworld.request_contact(initiator, target)
    assert {:error, changeset} = Overworld.request_contact(target, initiator)

    assert %{status: ["an active encounter already exists between these characters"]} =
             errors_on(changeset)
  end

  test "attack escalates to overworld combat in unsafe zones", %{
    initiator: initiator,
    target: target
  } do
    {:ok, encounter} = Overworld.create_encounter(initiator, target)

    assert {:ok, %{encounter: escalated_encounter, combat: combat}} =
             Overworld.respond(encounter, initiator, :attack)

    assert escalated_encounter.status == :escalated
    assert combat.kind == :overworld_encounter
    assert (combat.metadata["location_kind"] || combat.metadata[:location_kind]) == "wilderness"

    loaded_combat = Combat.get_combat!(combat.id)
    assert length(loaded_combat.participants) == 2
  end

  test "a finished overworld combat closes its escalated encounter idempotently", %{
    initiator: initiator,
    target: target
  } do
    {:ok, encounter} = Overworld.create_encounter(initiator, target)

    assert {:ok, %{encounter: escalated, combat: combat}} =
             Overworld.respond(encounter, initiator, :attack)

    finished_combat =
      combat
      |> CombatSchema.changeset(%{
        status: :finished,
        winner_side: "attackers",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, resolved_encounter} = Resolution.finalize(finished_combat)
    assert resolved_encounter.id == escalated.id
    assert resolved_encounter.status == :resolved
    assert resolved_encounter.metadata["winner_side"] == "attackers"

    assert {:ok, repeated_encounter} = Resolution.finalize(finished_combat)
    assert repeated_encounter.status == :resolved
  end

  test "attack is blocked in safe zones", %{
    initiator: initiator,
    city_target: city_target,
    city: city
  } do
    initiator =
      initiator
      |> Character.travel_changeset(%{current_location_id: city.id})
      |> Repo.update!()

    {:ok, encounter} = Overworld.create_encounter(initiator, city_target)

    assert {:error, changeset} = Overworld.respond(encounter, initiator, :attack)
    assert %{status: ["attacks are not allowed in safe zones"]} = errors_on(changeset)
  end

  test "attack is blocked when the realm disables overworld PvP", %{
    realm: realm,
    initiator: initiator,
    target: target
  } do
    assert {:ok, _realm} =
             realm
             |> Worlds.change_realm(%{ruleset: %{"overworld_pvp_enabled" => false}})
             |> Repo.update()

    {:ok, encounter} = Overworld.create_encounter(initiator, target)

    assert {:error, changeset} = Overworld.respond(encounter, initiator, :attack)
    assert %{status: ["overworld PvP is disabled for this realm"]} = errors_on(changeset)
    assert Combat.active_combat_for_character(initiator.id) == nil

    encounter = Overworld.get_encounter!(encounter.id)
    assert encounter.status == :pending
    assert is_nil(encounter.combat_id)
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
