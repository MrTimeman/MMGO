defmodule MMGO.GrimoiresTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "grimoires-mage", "Grimoire Mage")

    {:ok, treasury} = Economy.ensure_treasury_account(realm, 2_000)
    {:ok, _funding} = Economy.grant_from_treasury(realm, character, 1_000)

    spell =
      spell_fixture(character, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 12, variance: 1, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
      })

    %{realm: realm, treasury: treasury, character: character, spell: spell}
  end

  test "create, inscribe, and activate a grimoire", %{character: character, spell: spell} do
    assert {:ok, grimoire} =
             Grimoires.create_grimoire(character, %{
               name: "Field Grimoire",
               capacity: 8,
               weight: 2
             })

    assert {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    assert {:ok, %{activate_grimoire: active_grimoire}} =
             Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    assert active_grimoire.status == :active
    active_grimoire = Grimoires.get_grimoire!(grimoire.id)
    assert Enum.map(active_grimoire.entries, & &1.spell_id) == [spell.id]
    assert Grimoires.active_grimoire_for_character(character.id).id == active_grimoire.id
  end

  test "grimoire purchase uses fixed capacity and weight tiers with a treasury receipt", %{
    realm: realm,
    treasury: treasury,
    character: character
  } do
    assert [
             %{key: "pocket", capacity: 5, weight: 1, price: 40},
             %{key: "traveler", capacity: 10, weight: 2, price: 120},
             %{key: "scholar", capacity: 20, weight: 4, price: 350},
             %{key: "archivist", capacity: 45, weight: 8, price: 900}
           ] = Grimoires.purchase_tiers()

    assert {:ok, %{grimoire: grimoire, tier: %{key: "scholar"}}} =
             Grimoires.purchase_grimoire(character, "scholar", %{name: "Том дальних формул"})

    assert grimoire.name == "Том дальних формул"
    assert grimoire.capacity == 20
    assert grimoire.weight == 4
    assert grimoire.metadata["purchase_tier"] == "scholar"
    assert grimoire.metadata["purchase_price"] == 350

    buyer_account = Economy.ensure_character_account(character) |> elem(1)
    assert Economy.get_account!(buyer_account.id).current_balance == 650
    assert Economy.get_account!(treasury.id).current_balance == 1_350

    assert Enum.any?(Economy.list_ledger_entries_for_realm(realm.id), fn entry ->
             entry.metadata["source"] == "grimoire_purchase" and
               entry.metadata["grimoire_tier"] == "scholar" and entry.amount == 350
           end)
  end

  test "grimoire purchase rejects a non-catalog tier without charging the character", %{
    character: character
  } do
    buyer_account = Economy.ensure_character_account(character) |> elem(1)
    starting_balance = Economy.get_account!(buyer_account.id).current_balance

    assert {:error, changeset} = Grimoires.purchase_grimoire(character, "forged-tier")
    assert %{metadata: ["grimoire tier is invalid"]} = errors_on(changeset)
    assert Economy.get_account!(buyer_account.id).current_balance == starting_balance
  end

  test "sealed grimoires cannot be modified", %{character: character, spell: spell} do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Sealed Book", capacity: 2, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: _grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    second_spell =
      spell_fixture(character, %{
        name: "Aqua Sphaera",
        formula: "Aqua Sphaera Levis",
        school: :water,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [%{applies_to: :target, state: "impact", intensity: 8, variance: 0, duration: 0}],
        failure_profile: %{difficulty: 4, base_success_rate: 92, partial_success_rate: 4}
      })

    assert {:error, changeset} =
             Grimoires.inscribe_spell(Grimoires.get_grimoire!(grimoire.id), second_spell)

    assert %{status: ["sealed grimoires cannot be modified"]} = errors_on(changeset)
  end

  test "explicit inscription rejects a foreign spell and a full grimoire", %{
    realm: realm,
    character: character,
    spell: spell
  } do
    stranger = character_fixture(realm, "foreign-scribe", "Foreign Scribe")

    foreign_spell =
      spell_fixture(stranger, %{
        name: "Alien Formula",
        formula: "Alienus Formula",
        school: :water,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [%{applies_to: :target, state: "impact", intensity: 8, variance: 0, duration: 0}],
        failure_profile: %{difficulty: 4, base_success_rate: 92, partial_success_rate: 4}
      })

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Single Leaf", capacity: 1, weight: 1})

    assert {:error, foreign_changeset} = Grimoires.inscribe_spell(grimoire, foreign_spell)

    assert %{owner_character_id: ["grimoire must belong to the same character"]} =
             errors_on(foreign_changeset)

    assert {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    second_spell =
      spell_fixture(character, %{
        name: "Second Formula",
        formula: "Ignis Secundus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [%{applies_to: :target, state: "impact", intensity: 8, variance: 0, duration: 0}],
        failure_profile: %{difficulty: 4, base_success_rate: 92, partial_success_rate: 4}
      })

    assert {:error, capacity_changeset} =
             Grimoires.inscribe_spell(Grimoires.get_grimoire!(grimoire.id), second_spell)

    assert %{capacity: ["grimoire is at capacity"]} = errors_on(capacity_changeset)
  end

  test "activating a new owned grimoire seals the previous active loadout", %{
    character: character,
    spell: spell
  } do
    {:ok, first} =
      Grimoires.create_grimoire(character, %{name: "First Loadout", capacity: 2, weight: 1})

    {:ok, second} =
      Grimoires.create_grimoire(character, %{name: "Second Loadout", capacity: 2, weight: 2})

    {:ok, _entry} = Grimoires.inscribe_spell(first, spell)
    {:ok, _entry} = Grimoires.inscribe_spell(second, spell)

    assert {:ok, %{activate_grimoire: %{id: first_id}}} =
             Grimoires.activate_grimoire(character, first)

    assert first_id == first.id

    assert {:ok, %{activate_grimoire: %{id: second_id}}} =
             Grimoires.activate_grimoire(character, second)

    assert second_id == second.id
    assert Grimoires.get_grimoire!(first.id).status == :sealed
    assert Grimoires.get_grimoire!(second.id).status == :active
    assert Grimoires.active_grimoire_for_character(character.id).id == second.id
  end

  test "invalid selected grimoire is rejected during combat setup", %{
    realm: realm,
    character: character
  } do
    stranger = character_fixture(realm, "stranger-mage", "Stranger Mage")

    {:ok, stranger_grimoire} =
      Grimoires.create_grimoire(stranger, %{name: "Stranger Book", capacity: 5, weight: 1})

    assert {:error, :participant, changeset, []} =
             MMGO.Combat.create_duel(realm, %{
               participants: [
                 %{
                   character_id: character.id,
                   side: "attackers",
                   position: 0,
                   grimoire_id: stranger_grimoire.id
                 },
                 %{character_id: stranger.id, side: "defenders", position: 0}
               ]
             })

    assert %{id: ["selected grimoire is invalid for this character"]} = errors_on(changeset)
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 18})
    |> Repo.insert!()
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end
end
