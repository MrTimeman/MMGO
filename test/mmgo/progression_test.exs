defmodule MMGO.ProgressionTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Progression
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

    character = character_fixture(realm, city, "leveler", "Leveler")

    {:ok, _milestone} =
      Progression.create_milestone(%{
        level: 2,
        code: "carry-boost",
        title: "Carry Boost",
        effects: %{"carry_capacity_bonus" => 5}
      })

    %{character: character}
  end

  test "grant_xp/4 updates level and grants milestone effects", %{character: character} do
    amount = Progression.xp_for_level(2)

    assert {:ok, %{character: updated_character, grants: grants}} =
             Progression.grant_xp(character, amount, %{"source" => "test"})

    assert updated_character.level == 2
    assert updated_character.metadata["carry_capacity_bonus"] == 5
    assert length(grants) == 1
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 1, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
