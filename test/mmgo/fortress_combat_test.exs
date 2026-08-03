defmodule MMGO.FortressCombatTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Bases
  alias MMGO.Bases.Base
  alias MMGO.Combat
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "fortress-realm", name: "Fortress Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "fortress-tower",
        name: "Fortress Tower",
        kind: :tower,
        x: 40,
        y: 40,
        safe_zone: false
      })

    {:ok, field} =
      Worlds.create_location(realm, %{
        slug: "open-field",
        name: "Open Field",
        kind: :wilderness,
        x: 90,
        y: 90,
        safe_zone: false
      })

    owner_account = account_fixture("fortress-owner")
    opponent_account = account_fixture("fortress-opponent")

    owner =
      owner_account
      |> character_fixture(realm, tower, "Fortress Owner", :active)
      |> Character.changeset(%{
        metadata: %{
          "profile_kind" => "sealed_spirit",
          "sealed_anchor_location_id" => tower.id
        }
      })
      |> Repo.update!()

    sibling = character_fixture(owner_account, realm, tower, "Ordinary Sibling", :frozen)
    opponent = character_fixture(opponent_account, realm, tower, "Fortress Opponent", :active)

    fortress =
      base_fixture(owner, tower, %{
        "fortress" => %{"tier" => 5, "ward_intensity" => 100}
      })

    %{
      realm: realm,
      tower: tower,
      field: field,
      owner: owner,
      sibling: sibling,
      opponent: opponent,
      fortress: fortress
    }
  end

  test "the direct owner starts a battle at their active fortress with its bounded ward", %{
    realm: realm,
    tower: tower,
    owner: owner,
    opponent: opponent,
    fortress: fortress
  } do
    combat = duel_at(realm, tower.id, owner, opponent)
    participant = participant_for(combat, owner)

    assert [ward] = participant.active_states
    assert ward["state"] == "shielded"
    assert ward["intensity"] == 100
    assert ward["remaining_turns"] == 3
    assert ward["source"] == "owned_fortress"
    assert ward["base_id"] == fortress.id
  end

  test "the same server-side ward is applied to an overworld encounter at the fortress", %{
    realm: realm,
    tower: tower,
    owner: owner,
    opponent: opponent
  } do
    assert {:ok, %{combat: combat}} =
             Combat.create_overworld_encounter(realm, %{
               participants: [
                 %{character_id: owner.id, side: "attackers", position: 0},
                 %{character_id: opponent.id, side: "defenders", position: 0}
               ],
               metadata: %{"location_id" => tower.id}
             })

    combat = Combat.get_combat!(combat.id)

    assert Enum.any?(participant_for(combat, owner).active_states, fn state ->
             state["state"] == "shielded" and state["source"] == "owned_fortress"
           end)

    assert participant_for(combat, opponent).active_states == []
  end

  test "a same-account sibling and another character receive no ownership benefit", %{
    realm: realm,
    tower: tower,
    sibling: sibling,
    opponent: opponent
  } do
    combat = duel_at(realm, tower.id, sibling, opponent)

    assert participant_for(combat, sibling).active_states == []
    assert participant_for(combat, opponent).active_states == []
  end

  test "legacy fortress metadata on an ordinary base grants no ward", %{
    realm: realm,
    tower: tower,
    opponent: opponent
  } do
    _forged_base =
      base_fixture(opponent, tower, %{
        "fortress" => %{"tier" => 5, "ward_intensity" => 100}
      })

    assert Bases.initial_combat_states(opponent.id, realm.id, %{"location_id" => tower.id}) == []
  end

  test "the owner receives no fortress ward in a fight elsewhere", %{
    realm: realm,
    field: field,
    owner: owner,
    opponent: opponent
  } do
    combat = duel_at(realm, field.id, owner, opponent)

    assert participant_for(combat, owner).active_states == []
  end

  test "tower metadata cannot grant a ward after the owner has moved elsewhere", %{
    realm: realm,
    tower: tower,
    field: field,
    owner: owner,
    opponent: opponent
  } do
    owner
    |> Character.travel_changeset(%{current_location_id: field.id})
    |> Repo.update!()

    combat = duel_at(realm, tower.id, owner, opponent)

    assert participant_for(combat, owner).active_states == []
  end

  test "malformed and out-of-bounds fortress metadata fails closed", %{
    realm: realm,
    tower: tower,
    owner: owner,
    opponent: opponent,
    fortress: fortress
  } do
    invalid_configs = [
      %{"tier" => "5", "ward_intensity" => 100},
      %{"tier" => 0, "ward_intensity" => 100},
      %{"tier" => 5, "ward_intensity" => 101},
      %{"tier" => 5},
      "fortress"
    ]

    Enum.each(invalid_configs, fn config ->
      fortress
      |> Base.changeset(%{metadata: %{"fortress" => config}})
      |> Repo.update!()

      combat = duel_at(realm, tower.id, owner, opponent)
      assert participant_for(combat, owner).active_states == []
    end)

    assert Bases.initial_combat_states(owner.id, realm.id, %{"location_id" => "not-a-uuid"}) ==
             []
  end

  defp duel_at(realm, location_id, first_character, second_character) do
    assert {:ok, %{combat: combat}} =
             Combat.create_duel(realm, %{
               participants: [
                 %{character_id: first_character.id, side: "attackers", position: 0},
                 %{character_id: second_character.id, side: "defenders", position: 0}
               ],
               metadata: %{"location_id" => location_id}
             })

    Combat.get_combat!(combat.id)
  end

  defp participant_for(combat, character) do
    Enum.find(combat.participants, &(&1.character_id == character.id))
  end

  defp account_fixture(handle) do
    %Account{}
    |> Account.registration_changeset(%{
      display_name: String.replace(handle, "-", " "),
      handle: handle
    })
    |> Repo.insert!()
  end

  defp character_fixture(account, realm, location, name, status) do
    %Character{
      account_id: account.id,
      realm_id: realm.id,
      current_location_id: location.id
    }
    |> Character.changeset(%{name: name, status: status, level: 10})
    |> Repo.insert!()
  end

  defp base_fixture(owner, location, metadata) do
    %Base{
      owner_character_id: owner.id,
      realm_id: owner.realm_id,
      location_id: location.id
    }
    |> Base.changeset(%{
      name: "Server-owned Fortress",
      kind: :custom_build,
      status: :active,
      storage_weight_capacity: 350,
      built_at: DateTime.utc_now(),
      metadata: metadata
    })
    |> Repo.insert!()
  end
end
