defmodule MMGO.Combat.EngineTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, RNG, Turn}
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Inventory.{InventoryItem, ItemAction, ItemTemplate}
  alias MMGO.Spells.{FailureProfile, InteractionRule, Spell, SpellEffect}

  test "resolve_turn/4 is deterministic for the same inputs" do
    spell = spell_fixture()
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    participants = participants_fixture()

    actions = [
      %Action{
        participant_id: "p1",
        action_type: :cast_spell,
        spell: spell,
        spell_id: spell.id,
        target_side: "defenders"
      }
    ]

    assert Engine.resolve_turn(combat, turn, participants, actions) ==
             Engine.resolve_turn(combat, turn, participants, actions)
  end

  property "bounded_noise/3 always stays within the requested variance" do
    check all(seed <- integer(1..1_000_000), variance <- integer(0..20)) do
      noise = RNG.bounded_noise(seed, [:spell, :impact], variance)

      assert noise >= -variance
      assert noise <= variance
    end
  end

  test "staggered blocks one spell cast and consumes the state" do
    spell = spell_fixture()
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}

    [attacker, defender] = participants_fixture()

    attacker = %{
      attacker
      | active_states: [%{"state" => "staggered", "remaining_turns" => 1, "intensity" => 1}]
    }

    actions = [
      %Action{
        participant_id: attacker.id,
        action_type: :cast_spell,
        spell: spell,
        spell_id: spell.id,
        target_side: "defenders"
      }
    ]

    resolution = Engine.resolve_turn(combat, turn, [attacker, defender], actions)

    assert Enum.any?(resolution.events, &(&1.event_type == "action_blocked"))

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, attacker.id).active_states,
             &(&1["state"] == "staggered")
           )
  end

  test "empowered multiplies the next valid spell cast and is consumed" do
    spell =
      %{
        spell_fixture()
        | effects: [
            %SpellEffect{
              applies_to: :target,
              state: "impact",
              intensity: 10,
              variance: 0,
              duration: 0
            }
          ],
          failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 100,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    attacker = %{
      attacker
      | active_states: [
          %{
            "state" => "empowered",
            "intensity" => 2,
            "remaining_turns" => 2
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    spell_event = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))

    assert spell_event.payload["empowerment"] == %{"consumed" => true, "multiplier" => 2}
    assert [%{"state" => "impact", "damage" => 20}] = spell_event.payload["effects"]
    assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 80

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, attacker.id).active_states,
             &(&1["state"] == "empowered")
           )
  end

  test "empowered is consumed by a failed valid spell cast" do
    spell =
      %{
        spell_fixture()
        | failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 0,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    attacker = %{
      attacker
      | active_states: [
          %{
            "state" => "empowered",
            "intensity" => 3,
            "remaining_turns" => 2
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    failed_event = Enum.find(resolution.events, &(&1.event_type == "spell_failed"))

    assert failed_event.payload["empowerment"] == %{"consumed" => true, "multiplier" => 3}

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, attacker.id).active_states,
             &(&1["state"] == "empowered")
           )
  end

  test "blinded applies an accuracy penalty without consuming the state" do
    spell =
      %{
        spell_fixture()
        | failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 100,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    attacker = %{
      attacker
      | active_states: [
          %{
            "state" => "blinded",
            "intensity" => 100,
            "remaining_turns" => 2
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    failed_event = Enum.find(resolution.events, &(&1.event_type == "spell_failed"))

    assert failed_event.payload["accuracy_penalty"] == 100
    assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 100

    assert Enum.any?(
             Map.fetch!(resolution.participant_updates, attacker.id).active_states,
             &(&1["state"] == "blinded")
           )
  end

  test "a fire spell breaks only matching persisted states before applying its own effects" do
    spell =
      %{
        spell_fixture()
        | effects: [
            %SpellEffect{
              applies_to: :target,
              state: "impact",
              intensity: 10,
              variance: 0,
              duration: 0
            },
            %SpellEffect{
              applies_to: :target,
              state: "burning",
              intensity: 3,
              variance: 0,
              duration: 2,
              break_conditions: ["fire_spell"]
            }
          ],
          failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 100,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    defender = %{
      defender
      | active_states: [
          %{
            "state" => "frozen",
            "intensity" => 1,
            "remaining_turns" => 2,
            "break_conditions" => ["fire_spell"]
          },
          %{
            "state" => "blinded",
            "intensity" => 1,
            "remaining_turns" => 2,
            "break_conditions" => ["water_spell"]
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    spell_event = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))

    assert spell_event.payload["state_breaks"] == [
             %{
               "participant_id" => defender.id,
               "state" => "frozen",
               "condition" => "fire_spell"
             }
           ]

    active_states = Map.fetch!(resolution.participant_updates, defender.id).active_states

    refute Enum.any?(active_states, &(&1["state"] == "frozen"))
    assert Enum.any?(active_states, &(&1["state"] == "blinded"))

    assert Enum.any?(active_states, fn state ->
             state["state"] == "burning" and state["break_conditions"] == ["fire_spell"]
           end)
  end

  test "an unsupported source leaves break-conditioned and legacy states unchanged" do
    spell =
      %{
        spell_fixture()
        | school: :earth,
          failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 100,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    defender = %{
      defender
      | active_states: [
          %{
            "state" => "frozen",
            "intensity" => 1,
            "remaining_turns" => 2,
            "break_conditions" => ["fire_spell"]
          },
          %{"state" => "silenced", "intensity" => 1, "remaining_turns" => 2}
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    spell_event = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))
    refute Map.has_key?(spell_event.payload, "state_breaks")

    active_states = Map.fetch!(resolution.participant_updates, defender.id).active_states
    assert Enum.any?(active_states, &(&1["state"] == "frozen"))
    assert Enum.any?(active_states, &(&1["state"] == "silenced"))
  end

  test "a direct weapon impact triggers physical_hit for an explicitly configured state" do
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    defender = %{
      defender
      | active_states: [
          %{
            "state" => "frozen",
            "intensity" => 1,
            "remaining_turns" => 2,
            "break_conditions" => ["physical_hit"]
          }
        ]
    }

    item_action = %ItemAction{
      key: "strike",
      action_kind: :strike,
      targeting: :enemy,
      quantity_cost: 0,
      durability_cost: 0,
      effects: [
        %SpellEffect{
          applies_to: :target,
          state: "impact",
          intensity: 10,
          variance: 0,
          duration: 0
        }
      ]
    }

    inventory_item = %InventoryItem{
      id: "weapon-1",
      character_id: attacker.character_id,
      quantity: 1,
      reserved_quantity: 0,
      durability: 1,
      item_template: %ItemTemplate{code: "practice_sword", actions: [item_action]}
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :use_item,
          inventory_item_id: inventory_item.id,
          inventory_item: inventory_item,
          target_side: "defenders",
          payload: %{"tool_action" => "strike"}
        }
      ])

    tool_event = Enum.find(resolution.events, &(&1.event_type == "tool_action"))

    assert tool_event.payload["state_breaks"] == [
             %{
               "participant_id" => defender.id,
               "state" => "frozen",
               "condition" => "physical_hit"
             }
           ]

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, defender.id).active_states,
             &(&1["state"] == "frozen")
           )
  end

  test "an explicit wait lets a channeling caster stop maintaining the effect" do
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    attacker = %{
      attacker
      | active_states: [
          %{
            "state" => "channeling",
            "intensity" => 1,
            "remaining_turns" => 2
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{participant_id: attacker.id, action_type: :wait, payload: %{}}
      ])

    assert Enum.any?(resolution.events, &(&1.event_type == "channeling_stopped"))

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, attacker.id).active_states,
             &(&1["state"] == "channeling")
           )
  end

  test "damage breaks channeling after an actual hit" do
    spell =
      %{
        spell_fixture()
        | effects: [
            %SpellEffect{
              applies_to: :target,
              state: "impact",
              intensity: 10,
              variance: 0,
              duration: 0
            }
          ],
          failure_profile: %FailureProfile{
            difficulty: 0,
            base_success_rate: 100,
            partial_success_rate: 0,
            backlash_damage: 0
          }
      }

    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    defender = %{
      defender
      | active_states: [
          %{
            "state" => "channeling",
            "intensity" => 1,
            "remaining_turns" => 2
          }
        ]
    }

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    spell_event = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))
    assert [%{"channeling_broken" => true}] = spell_event.payload["effects"]

    refute Enum.any?(
             Map.fetch!(resolution.participant_updates, defender.id).active_states,
             &(&1["state"] == "channeling")
           )
  end

  test "burning environment effects create a side-scoped hazard without replacing legacy tags" do
    combat = %{
      combat_fixture()
      | environment_tags: ["charred"],
        metadata: %{"unrelated" => "kept"}
    }

    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: burning_environment_spell(7, 2),
          spell_id: "spell-1",
          target_side: "defenders"
        }
      ])

    assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 100
    assert resolution.combat_attrs.environment_tags == ["charred"]
    assert resolution.turn_attrs.resolution["environment_tags"] == ["charred", "burning"]

    assert %{
             "unrelated" => "kept",
             "environment_hazards" => [
               %{
                 "state" => "burning",
                 "side" => "defenders",
                 "intensity" => 7,
                 "duration" => 2,
                 "remaining_turns" => 2,
                 "applied_on_turn" => 1
               }
             ]
           } = resolution.combat_attrs.metadata

    spell_event = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))
    assert [%{"hazard_created" => true, "side" => "defenders"}] = spell_event.payload["effects"]
  end

  test "environment hazards tick on later turns and expire without deleting legacy tags" do
    combat = %{
      combat_fixture()
      | turn_number: 2,
        environment_tags: ["charred"],
        metadata: %{
          "environment_hazards" => [
            %{
              "state" => "burning",
              "side" => "defenders",
              "intensity" => 6,
              "duration" => 2,
              "remaining_turns" => 2,
              "applied_on_turn" => 1
            }
          ]
        }
    }

    [attacker, defender] = participants_fixture()

    second_turn =
      Engine.resolve_turn(combat, %Turn{number: 2, status: :locked}, [attacker, defender], [])

    assert second_turn.combat_attrs.sides["defenders"]["shared_hp"] == 94
    assert second_turn.combat_attrs.environment_tags == ["charred"]
    assert second_turn.turn_attrs.resolution["environment_tags"] == ["charred", "burning"]

    assert [
             %{
               "remaining_turns" => 1,
               "duration" => 2,
               "intensity" => 6
             }
           ] = second_turn.combat_attrs.metadata["environment_hazards"]

    tick_event = Enum.find(second_turn.events, &(&1.event_type == "environment_hazard_tick"))

    assert tick_event.payload == %{
             "state" => "burning",
             "side" => "defenders",
             "damage" => 6,
             "remaining_turns" => 1,
             "expired" => false
           }

    third_combat = %{
      combat
      | turn_number: 3,
        sides: second_turn.combat_attrs.sides,
        environment_tags: second_turn.combat_attrs.environment_tags,
        metadata: second_turn.combat_attrs.metadata
    }

    third_turn =
      Engine.resolve_turn(
        third_combat,
        %Turn{number: 3, status: :locked},
        [attacker, defender],
        []
      )

    assert third_turn.combat_attrs.sides["defenders"]["shared_hp"] == 88
    assert third_turn.combat_attrs.environment_tags == ["charred"]
    assert third_turn.turn_attrs.resolution["environment_tags"] == ["charred"]
    refute Map.has_key?(third_turn.combat_attrs.metadata, "environment_hazards")

    expiry_event = Enum.find(third_turn.events, &(&1.event_type == "environment_hazard_tick"))
    assert expiry_event.payload["expired"]
    assert expiry_event.payload["remaining_turns"] == 0
  end

  test "active hazard tags take part in later spell interaction rules" do
    combat = %{
      combat_fixture()
      | turn_number: 2,
        environment_tags: ["charred"],
        metadata: %{
          "environment_hazards" => [
            %{
              "state" => "burning",
              "side" => "defenders",
              "intensity" => 4,
              "duration" => 2,
              "remaining_turns" => 2,
              "applied_on_turn" => 1
            }
          ]
        }
    }

    spell = %{
      spell_fixture()
      | interaction_rules: [
          %InteractionRule{
            trigger_type: :environment_tag,
            trigger: "burning",
            outcome: :negate
          }
        ]
    }

    [attacker, defender] = participants_fixture()

    resolution =
      Engine.resolve_turn(combat, %Turn{number: 2, status: :locked}, [attacker, defender], [
        %Action{
          participant_id: attacker.id,
          action_type: :cast_spell,
          spell: spell,
          spell_id: spell.id,
          target_side: "defenders"
        }
      ])

    negated = Enum.find(resolution.events, &(&1.event_type == "spell_negated"))
    assert negated.payload["environment_tags"] == ["charred", "burning"]
    assert resolution.combat_attrs.environment_tags == ["charred"]
  end

  test "malformed or current-turn environment hazard metadata fails closed" do
    combat = %{
      combat_fixture()
      | turn_number: 2,
        environment_tags: ["charred"],
        metadata: %{
          "environment_hazards" => [
            %{
              "state" => "burning",
              "side" => "defenders",
              "intensity" => 9,
              "duration" => 2,
              "remaining_turns" => 2,
              "applied_on_turn" => 2
            },
            %{"state" => "burning", "intensity" => 999_999}
          ]
        }
    }

    [attacker, defender] = participants_fixture()

    resolution =
      Engine.resolve_turn(combat, %Turn{number: 2, status: :locked}, [attacker, defender], [])

    assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 100
    assert resolution.combat_attrs.environment_tags == ["charred"]
    assert resolution.turn_attrs.resolution["environment_tags"] == ["charred"]
    refute Map.has_key?(resolution.combat_attrs.metadata, "environment_hazards")
    refute Enum.any?(resolution.events, &(&1.event_type == "environment_hazard_tick"))
  end

  test "a fleeing last member forfeits their side without changing shared mechanics client-side" do
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    [attacker, defender] = participants_fixture()

    resolution =
      Engine.resolve_turn(combat, turn, [attacker, defender], [
        %Action{participant_id: attacker.id, action_type: :flee}
      ])

    assert resolution.combat_attrs.status == :finished
    assert resolution.combat_attrs.winner_side == "defenders"
    assert Map.fetch!(resolution.participant_updates, attacker.id).status == :fled
    assert Enum.any?(resolution.events, &(&1.event_type == "fled"))
  end

  defp combat_fixture do
    %Combat{
      id: "combat-1",
      turn_number: 1,
      seed: 12_345,
      environment_tags: [],
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participants_fixture do
    grimoire = %Grimoire{id: "g1", entries: [%GrimoireEntry{spell_id: "spell-1", slot_index: 1}]}

    [
      %Participant{
        id: "p1",
        character_id: "c1",
        side: "attackers",
        position: 0,
        status: :ready,
        fatigue: 0,
        cooldowns: %{},
        active_states: [],
        grimoire_id: grimoire.id,
        grimoire: grimoire,
        character: %Character{id: "c1", level: 15}
      },
      %Participant{
        id: "p2",
        character_id: "c2",
        side: "defenders",
        position: 0,
        status: :ready,
        fatigue: 0,
        cooldowns: %{},
        active_states: [],
        character: %Character{id: "c2", level: 8}
      }
    ]
  end

  defp spell_fixture do
    %Spell{
      id: "spell-1",
      creator_character_id: "c1",
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      fatigue_cost: 4,
      cooldown_turns: 1,
      environment_tags: ["charred"],
      environment_mode: :add,
      effects: [
        %SpellEffect{
          applies_to: :target,
          state: "impact",
          intensity: 14,
          variance: 2,
          duration: 0
        }
      ],
      interaction_rules: [],
      failure_profile: %FailureProfile{
        difficulty: 5,
        base_success_rate: 90,
        partial_success_rate: 5,
        backlash_damage: 0
      }
    }
  end

  defp burning_environment_spell(intensity, duration) do
    %{
      spell_fixture()
      | environment_tags: [],
        environment_mode: :none,
        effects: [
          %SpellEffect{
            applies_to: :environment,
            state: "burning",
            intensity: intensity,
            variance: 0,
            duration: duration
          }
        ],
        failure_profile: %FailureProfile{
          difficulty: 1,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0
        }
    }
  end
end
