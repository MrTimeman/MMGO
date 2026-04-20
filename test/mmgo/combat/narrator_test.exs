defmodule MMGO.Combat.NarratorTest do
  use MMGO.DataCase, async: true

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Narrator
  alias MMGO.Grimoires
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  defmodule NonRussianNarrationProvider do
    @behaviour MMGO.AI.Provider

    def compile_spell(_prompt_payload, _opts), do: {:error, :unused}
    def orchestrate_combat(_prompt_payload, _opts), do: {:error, :unused}
    def tick_dungeon(_prompt_payload, _opts), do: {:error, :unused}
    def narrate_turn(_prompt_payload, _opts), do: {:ok, "Turn 1 resolved cleanly."}
  end

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    attacker = character_fixture(realm, "narrator-attacker", "Narrator Attacker")
    defender = character_fixture(realm, "narrator-defender", "Narrator Defender")

    spell =
      spell_fixture(attacker, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        tags: ["fire"],
        effects: [
          %{applies_to: :target, state: "impact", intensity: 14, variance: 1, duration: 0}
        ],
        failure_profile: %{difficulty: 6, base_success_rate: 95, partial_success_rate: 3}
      })

    _grimoire = grimoire_fixture(attacker, spell, "Narrator Tome")

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    {:ok, _action} =
      Combat.submit_action(combat, attacker_participant.id, %{
        action_type: :cast_spell,
        spell_id: spell.id,
        target_side: "defenders"
      })

    {:ok, _resolved_combat} =
      Combat.resolve_turn(combat, orchestrate: false, auto_narrate?: false)

    %{combat: combat}
  end

  test "narrate_turn/3 stores AI narration on the turn", %{combat: combat} do
    assert {:ok, turn} = Narrator.narrate_turn(combat.id, 1)

    assert turn.narration =~ "Ход 1"
    assert Repo.aggregate(Request, :count, :id) == 1

    ai_request = Repo.one!(Request)
    assert ai_request.kind == :turn_narration
    assert ai_request.combat_id == combat.id
  end

  test "narrate_turn/3 falls back when narration is not Russian", %{combat: combat} do
    assert {:ok, turn} =
             Narrator.narrate_turn(combat.id, 1, provider: NonRussianNarrationProvider)

    assert turn.narration =~ "Ход 1"
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 16})
    |> Repo.insert!()
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp grimoire_fixture(character, spell, name) do
    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 5, weight: 1})
    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: activated_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    activated_grimoire
  end
end
