defmodule MMGO.Telegram.EventCommandsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Telegram.Commands
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

    character = character_fixture(realm, city, "eventcmd", "Event Cmd")
    %{character: character}
  end

  test "/event current and /event choose work", %{character: character} do
    assert {:ok, current_text} =
             Commands.process_message(character, %{"text" => "/event current"})

    assert current_text =~ "City Arrival"
    assert current_text =~ "shops"

    assert {:ok, choose_text} =
             Commands.process_message(character, %{"text" => "/event choose shops"})

    assert choose_text =~ "/npc shops"
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
