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

  test "manifestations are kind-specific, Russian-named, bounded, and share the effect budget",
       %{character: character} do
    base_attrs = %{
      name: "Scutum",
      formula: "Scutum Sustineo",
      school: :earth,
      description: "A duel-local summoned shield.",
      targeting: :enemy,
      delivery_form: :self,
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
    }

    assert {:ok, spell} =
             Spells.create_spell(
               character,
               Map.put(base_attrs, :manifestation, %{
                 kind: :held_shield,
                 display_name: "Каменный щит",
                 hp: 30,
                 duration_turns: 3
               })
             )

    assert spell.manifestation.kind == :held_shield
    assert spell.manifestation.hp == 30

    assert {:error, malformed_changeset} =
             Spells.create_spell(
               character,
               Map.put(base_attrs, :manifestation, %{
                 kind: :held_shield,
                 display_name: "Stone Shield",
                 hp: 30,
                 power: 5,
                 duration_turns: 99
               })
             )

    assert %{manifestation: manifestation_errors} = errors_on(malformed_changeset)
    assert "must be a bounded Russian display name" in manifestation_errors.display_name
    assert "is not used by this manifestation kind" in manifestation_errors.power
    assert "must be less than or equal to 8" in manifestation_errors.duration_turns

    assert {:error, budget_changeset} =
             Spells.create_spell(
               character,
               base_attrs
               |> Map.put(:effects, [
                 %{
                   applies_to: :target,
                   state: "impact",
                   intensity: 180,
                   variance: 0,
                   duration: 0
                 }
               ])
               |> Map.put(:manifestation, %{
                 kind: :creature_ally,
                 display_name: "Огненный волк",
                 hp: 40,
                 power: 15,
                 duration_turns: 3
               })
             )

    assert "total spell effect and manifestation intensity exceeds the current engine budget" in errors_on(
             budget_changeset
           ).effects
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
