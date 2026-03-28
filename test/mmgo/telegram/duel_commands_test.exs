defmodule MMGO.Telegram.DuelCommandsTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Telegram.Commands
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "duel-yard",
        name: "Duel Yard",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    challenger = character_fixture(realm, location, "challenger", "Challenger")
    opponent = character_fixture(realm, location, "opponent", "Opponent")
    {:ok, _challenger_funds} = Economy.grant_from_treasury(realm, challenger, 100)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 100)

    %{challenger: challenger, opponent: opponent}
  end

  test "/duel challenge and /duel accept create an active duel combat", %{
    challenger: challenger,
    opponent: opponent
  } do
    assert {:ok, challenge_text} =
             Commands.process_message(challenger, %{"text" => "/duel challenge opponent 25"})

    assert challenge_text =~ "Duel challenge sent"

    [duel] = PVP.pending_duels_for_character(opponent.id)

    assert {:ok, accept_text} =
             Commands.process_message(opponent, %{"text" => "/duel accept #{duel.id}"})

    assert accept_text =~ "Duel accepted"

    active_duel = PVP.active_duel_for_character(challenger.id)
    assert active_duel.combat_id

    assert {:ok, status_text} = Commands.process_message(challenger, %{"text" => "/duel status"})
    assert status_text =~ active_duel.id
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
