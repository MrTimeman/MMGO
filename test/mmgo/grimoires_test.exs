defmodule MMGO.GrimoiresTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "grimoires-mage", "Grimoire Mage")

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

    %{realm: realm, character: character, spell: spell}
  end

  test "create, inscribe, and activate a grimoire", %{character: character, spell: spell} do
    assert {:ok, grimoire} =
             Grimoires.create_grimoire(character, %{
               name: "Field Grimoire",
               capacity: 8,
               weight: 2
             })

    assert {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    [entry] = Grimoires.get_grimoire!(grimoire.id).entries
    assert %DateTime{} = entry.inscribed_at

    assert {:ok, %{activate_grimoire: active_grimoire}} =
             Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    assert active_grimoire.status == :active
    active_grimoire = Grimoires.get_grimoire!(grimoire.id)
    assert Enum.map(active_grimoire.entries, & &1.spell_id) == [spell.id]
    assert Grimoires.active_grimoire_for_character(character.id).id == active_grimoire.id
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

  test "draft grimoires cannot be selected for combat", %{realm: realm, character: character} do
    stranger = character_fixture(realm, "draft-stranger", "Draft Stranger")

    {:ok, draft_grimoire} =
      Grimoires.create_grimoire(character, %{name: "Draft Book", capacity: 5, weight: 1})

    assert {:error, :participant, changeset, []} =
             MMGO.Combat.create_duel(realm, %{
               participants: [
                 %{
                   character_id: character.id,
                   side: "attackers",
                   position: 0,
                   grimoire_id: draft_grimoire.id
                 },
                 %{character_id: stranger.id, side: "defenders", position: 0}
               ]
             })

    assert %{id: ["selected grimoire must be sealed or active"]} = errors_on(changeset)
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
