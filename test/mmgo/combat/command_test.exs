defmodule MMGO.Combat.CommandTest do
  use ExUnit.Case, async: true

  alias MMGO.Combat.Command
  alias MMGO.Combat.Participant

  defp state(overrides \\ %{}) do
    base = %{
      participant: %Participant{
        id: "me",
        side: "a",
        active_states: [],
        mana: 100,
        max_mana: 100
      },
      combat: %{
        participants: [
          %{id: "me", side: "a", status: :ready, display_name: "Аврелий"},
          %{id: "foe", side: "b", status: :ready, display_name: "Бранд"},
          %{id: "ally", side: "a", status: :ready, display_name: "Аглая"}
        ]
      },
      prepared_spells: [
        %{id: "s1", name: "Уголь под кожей", formula: "Ignis Prima"},
        %{id: "s2", name: "Жатва", formula: "Exhaurio Messis"}
      ],
      items: [],
      flee_available?: true
    }

    Map.merge(base, overrides)
  end

  defp with_weapon(state) do
    put_in(state.participant.active_states, [%{"state" => "summoned_weapon"}])
  end

  test "a bare formula is a cast, aimed at the other side by default" do
    assert {:ok, attrs} = Command.parse("Ignis Prima", state())

    assert attrs["action_type"] == "cast_spell"
    assert attrs["spell_id"] == "s1"
    assert attrs["target_side"] == "b"
    assert attrs["incantation"] == "Ignis Prima"
  end

  test "a spell answers to its name as readily as to its formula" do
    assert {:ok, %{"spell_id" => "s2"}} = Command.parse("Жатва", state())
    assert {:ok, %{"spell_id" => "s2"}} = Command.parse("exhaurio", state())
  end

  test "case and stray spacing do not decide a duel" do
    assert {:ok, %{"spell_id" => "s1"}} = Command.parse("  iGnIs   pRiMa  ", state())
  end

  # Guessing between two spells would spend the turn on a coin flip.
  test "an ambiguous prefix is refused, not guessed" do
    state =
      state(%{
        prepared_spells: [
          %{id: "s1", name: "Первое", formula: "Ignis Prima"},
          %{id: "s2", name: "Второе", formula: "Ignis Nova"}
        ]
      })

    assert {:error, {:ambiguous_spell, "ignis", names}} = Command.parse("Ignis", state)
    assert length(names) == 2
  end

  test "an exact formula wins over a longer one that also starts with it" do
    state =
      state(%{
        prepared_spells: [
          %{id: "short", name: "Короткое", formula: "Ignis"},
          %{id: "long", name: "Длинное", formula: "Ignis Nova"}
        ]
      })

    assert {:ok, %{"spell_id" => "short"}} = Command.parse("Ignis", state)
  end

  test "a formula the book does not hold is refused by name" do
    assert {:error, {:unknown_spell, "vocatio gladius"}} =
             Command.parse("Vocatio Gladius", state())
  end

  test "a target marker aims at one participant" do
    assert {:ok, attrs} = Command.parse("Ignis Prima по Бранд", state())

    assert attrs["target_participant_id"] == "foe"
    assert attrs["target_side"] == "b"
  end

  test "an arrow aims as well as a preposition, and an ally can be chosen" do
    assert {:ok, attrs} = Command.parse("Жатва -> Аглая", state())

    assert attrs["target_participant_id"] == "ally"
    assert attrs["target_side"] == "a"
  end

  test "waiting and fleeing need no object" do
    assert {:ok, %{"action_type" => "wait"}} = Command.parse("ждать", state())
    assert {:ok, %{"action_type" => "flee"}} = Command.parse("бежать", state())
  end

  test "fleeing is refused where the fight does not allow it" do
    assert {:error, :flee_unavailable} =
             Command.parse("бежать", state(%{flee_available?: false}))
  end

  test "a strike needs a summoned weapon in hand" do
    assert {:error, :no_summoned_weapon} = Command.parse("удар", state())

    assert {:ok, %{"action_type" => "manifestation_strike", "target_side" => "b"}} =
             Command.parse("удар", with_weapon(state()))
  end

  test "a bare guard takes the strongest thing available" do
    assert {:ok, attrs} = Command.parse("блок", state())

    assert attrs["action_type"] == "block"
    assert is_binary(attrs["guard_source"])
  end

  test "a guard can be told what to raise" do
    assert {:ok, attrs} = Command.parse("парировать оружие", with_weapon(state()))

    # The typed verb is Russian; the action is stored under the engine's name.
    assert attrs["action_type"] == "parry"
    assert attrs["guard_source"] == "summoned_weapon"
  end

  test "an empty line is not a decision" do
    assert {:error, :empty_command} = Command.parse("   ", state())
    assert {:error, :empty_command} = Command.parse(nil, state())
  end

  test "using an item names it and picks its only action" do
    state =
      state(%{
        items: [
          %{id: "i1", name: "Зелье бодрости", actions: [%{key: "drink", kind: :consume}]}
        ]
      })

    assert {:ok, attrs} = Command.parse("предмет Зелье", state)

    assert attrs["action_type"] == "use_item"
    assert attrs["inventory_item_id"] == "i1"
    assert attrs["tool_action"] == "drink"
  end

  test "an item the bag does not hold is refused" do
    assert {:error, {:unknown_item, "верёвка"}} = Command.parse("предмет верёвка", state())
  end
end
