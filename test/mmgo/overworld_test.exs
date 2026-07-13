defmodule MMGO.OverworldTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.Resolution
  alias MMGO.Overworld
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
