defmodule MMGOWeb.BulletinBoardLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.{Enrollment}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "bulletin-realm", name: "Bulletin Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "bulletin-city",
        name: "Bulletin City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    %{realm: realm, city: city}
  end

  test "shows a current valedictorian in the public year-long hall of fame", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city)
    enrollment = valedictorian_enrollment_fixture(character)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy/bulletin-board")

    assert has_element?(view, "#bulletin-hall-of-fame")
    assert has_element?(view, "#bulletin-valedictorian-#{enrollment.id}")
    assert has_element?(view, "#bulletin-courses .bb-table-wrap")
    assert has_element?(view, "#bulletin-back-to-academy")
    assert has_element?(view, "#bulletin-study-desk-link")
  end

  defp character_fixture(realm, location) do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Board Laureate",
        handle: "board-laureate"
      })
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: "Board Laureate", status: :active, level: 1, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp valedictorian_enrollment_fixture(character) do
    completed_at = ~U[2026-07-12 12:00:00Z]

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      program_type: :academy_core,
      track: :alchemy,
      status: :completed,
      started_at: DateTime.add(completed_at, -3600, :second),
      expected_completion_at: completed_at,
      completed_at: completed_at,
      metadata: %{
        "cohort_key" => "academy_core:2026",
        "honors" => true,
        "outcome_tier" => "distinction",
        "valedictorian" => true
      }
    })
    |> Repo.insert!()
  end

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
