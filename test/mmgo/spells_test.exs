defmodule MMGO.SpellsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.SpellEffect
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    account = account_fixture("spellcrafter")
    character = character_fixture(account, realm, "Spellcrafter")

    %{realm: realm, account: account, character: character}
  end

  test "create_spell/2 stores a compiled spell", %{character: character} do
    attrs = %{
      name: "Ignis Sphaera",
      formula: "Ignis Sphaera Magnus",
      school: :fire,
      description: "A compiled fire sphere for deterministic combat.",
      targeting: :enemy,
      delivery_form: :sphere,
      tags: ["fire", "projectile"],
      effects: [
        %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0},
        %{applies_to: :target, state: "burning", intensity: 6, variance: 1, duration: 2}
      ],
      failure_profile: %{difficulty: 20, base_success_rate: 86, partial_success_rate: 8}
    }

    assert {:ok, spell} = Spells.create_spell(character, attrs)

    assert spell.school == :fire
    assert spell.creator_character_id == character.id
    assert Enum.map(spell.effects, & &1.state) == ["impact", "burning"]
    assert spell.failure_profile.difficulty == 20
  end

  test "spell effects accept only the bounded break-condition vocabulary" do
    valid_changeset =
      SpellEffect.changeset(%SpellEffect{}, %{
        applies_to: :target,
        state: "frozen",
        intensity: 3,
        variance: 0,
        duration: 2,
        break_conditions: ["fire_spell", "physical_hit"]
      })

    assert valid_changeset.valid?

    invalid_changeset =
      SpellEffect.changeset(%SpellEffect{}, %{
        applies_to: :target,
        state: "frozen",
        intensity: 3,
        variance: 0,
        duration: 2,
        break_conditions: ["unknown_break"]
      })

    refute invalid_changeset.valid?
    assert Keyword.has_key?(invalid_changeset.errors, :break_conditions)
  end

  defp account_fixture(handle) do
    %Account{}
    |> Account.registration_changeset(%{display_name: handle, handle: handle})
    |> Repo.insert!()
  end

  defp character_fixture(account, realm, name) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active})
    |> Repo.insert!()
  end
end
