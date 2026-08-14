defmodule MMGO.Spells.CompilerTest do
  use MMGO.DataCase, async: true

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.{Compiler, Spell, SpellFailure}
  alias MMGO.Worlds

  defmodule InvalidSpellProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "outcome" => "created",
         "name" => "Сломанное заклинание",
         "formula" => "Maledictum",
         "school" => "fire",
         "description" => "Намеренно некорректный результат для проверки валидации.",
         "targeting" => "enemy",
         "delivery_form" => "sphere",
         "effects" => [
           %{
             "applies_to" => "target",
             "state" => "invented_state",
             "intensity" => 10,
             "duration" => 0
           }
         ],
         "failure_profile" => %{
           "difficulty" => 10,
           "base_success_rate" => 80,
           "partial_success_rate" => 10,
           "backlash_damage" => 0
         }
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  # A provider that summons a construct but says nothing about what it does
  # beyond existing — the exact case the server has to fill in.
  defmodule TraitlessManifestationProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(prompt_payload, schema, opts) do
      {:ok, compiled_spell} =
        MMGO.AI.Providers.Mock.structured_completion(prompt_payload, schema, opts)

      manifestation =
        compiled_spell
        |> Map.get("manifestation", %{})
        |> Map.merge(%{"kind" => "summoned_weapon", "power" => 4, "duration_turns" => 3})
        |> Map.delete("trait")
        |> Map.delete("hp")

      {:ok, Map.put(compiled_spell, "manifestation", manifestation)}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  # A provider that hands a blade a shield's trait, which the engine would read
  # from the wrong list and silently ignore.
  defmodule MismatchedTraitProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(prompt_payload, schema, opts) do
      {:ok, compiled_spell} =
        MMGO.AI.Providers.Mock.structured_completion(prompt_payload, schema, opts)

      manifestation = %{
        "kind" => "summoned_weapon",
        "display_name" => "Клинок праха",
        "power" => 4,
        "duration_turns" => 3,
        "trait" => "bastion"
      }

      {:ok, Map.put(compiled_spell, "manifestation", manifestation)}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  defmodule MissingOutcomeProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(prompt_payload, schema, opts) do
      {:ok, compiled_spell} =
        MMGO.AI.Providers.Mock.structured_completion(prompt_payload, schema, opts)

      {:ok, Map.delete(compiled_spell, "outcome")}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  defmodule FailedSpellProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "outcome" => "failed",
         "rejection_reason" =>
           "The words pull the fire school toward healing and collapse before a stable circle forms.",
         "instability_markers" => ["school_mismatch", "unstable_lineage"],
         "details" => %{"severity" => "ordinary_failure"}
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  defmodule DriftedSpellProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "outcome" => "created",
         "name" => "Provider Drift",
         "formula" => "Alien Formula",
         "school" => "water",
         "source_spell_id" => "provider-authority",
         "description" => "A valid provider result with intentionally untrusted identity fields.",
         "targeting" => "enemy",
         "delivery_form" => "sphere",
         "effects" => [
           %{
             "applies_to" => "target",
             "state" => "impact",
             "intensity" => 10,
             "duration" => 0
           }
         ],
         "failure_profile" => %{
           "difficulty" => 10,
           "base_success_rate" => 80,
           "partial_success_rate" => 10,
           "backlash_damage" => 0
         }
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  defmodule OverpoweredRootProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "outcome" => "created",
         "name" => "Неограниченный корень",
         "formula" => "Provider Formula",
         "school" => "chaos",
         "description" => "Намеренно чрезмерный результат толкователя.",
         "power" => 80,
         "fatigue_cost" => 90,
         "cooldown_turns" => 30,
         "targeting" => "zone",
         "delivery_form" => "zone",
         "tags" => ["chaos", "root"],
         "narrative_tags" => ["cataclysmic"],
         "environment_tags" => ["world-fire", "collapsed-reality"],
         "environment_mode" => "replace",
         "effects" => [
           %{
             "applies_to" => "environment",
             "state" => "burning",
             "intensity" => 200,
             "variance" => 80,
             "duration" => 40,
             "tags" => ["unbounded"]
           },
           %{
             "applies_to" => "target",
             "state" => "trapped",
             "intensity" => 30,
             "variance" => 20,
             "duration" => 20
           }
         ],
         "interaction_rules" => [
           %{
             "trigger_type" => "spell_tag",
             "trigger" => "water",
             "outcome" => "replace_environment",
             "replacement_tags" => ["void"]
           }
         ],
         "failure_profile" => %{
           "difficulty" => 80,
           "base_success_rate" => 25,
           "partial_success_rate" => 20,
           "backlash_damage" => 50,
           "volatility" => 90
         }
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  defmodule NaturalVocabularyProvider do
    @behaviour MMGO.AI.Provider

    def structured_completion(_prompt_payload, _schema, _opts) do
      {:ok,
       %{
         "outcome" => "created",
         "name" => "Гнилостные оковы",
         "description" => "Призрачные цепи удерживают цель и оставляют гниющую рану.",
         "school_quirk" => "harvest",
         "targeting" => "enemy",
         "delivery_form" => "single_target",
         "effects" => [
           %{
             "applies_to" => "enemy",
             "state" => "trapped",
             "intensity" => 3,
             "variance" => 1,
             "duration" => 3
           }
         ],
         "interaction_rules" => [
           %{
             "trigger_type" => "environment",
             "trigger" => "fire",
             "outcome" => "replace",
             "replacement_tags" => ["necrotic"]
           }
         ],
         "failure_profile" => %{
           "difficulty" => 4,
           "base_success_rate" => 70,
           "partial_success_rate" => 20,
           "backlash_damage" => 2
         }
       }}
    end

    def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
  end

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "compiler-mage", "Compiler Mage")

    %{character: character, realm: realm, base_spell: spell_fixture(character, "Starter Spark")}
  end

  test "compile_and_store/3 persists a compiled spell and bounded owned context", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:ok, %{spell: spell, ai_request: ai_request}} =
             Compiler.compile_and_store(character, %{
               name: "Ignis Lancea",
               formula: "Ignis Radius Magnus",
               school: "fire",
               base_spell_id: base_spell.id,
               targeting: "enemy",
               delivery_form: "beam"
             })

    assert spell.name == "Ignis Lancea"
    assert spell.formula == "Ignis Radius Magnus"
    assert spell.school == :fire
    assert spell.source_spell_id == base_spell.id
    assert spell.creator_character_id == character.id
    assert ai_request.kind == :spell_compile
    assert ai_request.status == :succeeded
    assert ai_request.spell_id == spell.id
    assert Repo.aggregate(Request, :count, :id) == 1

    persisted_request = Repo.get!(Request, ai_request.id)
    prompt = Jason.decode!(persisted_request.request_payload["user_prompt"])
    assert prompt["base_spell"]["id"] == base_spell.id
    assert prompt["base_spell"]["effects"] != []

    assert prompt["engine_constraints"]["manifestation"]["kinds"] == [
             "held_shield",
             "summoned_weapon",
             "creature_ally"
           ]

    assert persisted_request.request_payload["schema"]["properties"]["manifestation"]
    assert [%{"id" => base_id} | _rest] = prompt["library"]
    assert base_id == base_spell.id
  end

  test "mock compiler deterministically recognizes shield, weapon, and creature formulas" do
    for {formula, kind} <- [
          {"Scutum Sustineo", "held_shield"},
          {"Gladius Magnus", "summoned_weapon"},
          {"Vocatio Sustineo", "creature_ally"},
          {"Evocatio Minima", "creature_ally"}
        ] do
      assert {:ok, compiled_spell} =
               MMGO.AI.Providers.Mock.structured_completion(
                 %{
                   "task" => "compile_spell",
                   "character" => %{"level" => 10},
                   "request" => %{"formula" => formula, "school" => "life"}
                 },
                 %{},
                 []
               )

      assert compiled_spell["manifestation"]["kind"] == kind
    end
  end

  test "a summoned blade always carries its school's trait", %{character: character} do
    assert {:ok, %{spell: spell}} =
             Compiler.compile_and_store(
               character,
               %{formula: "Vocatio Gladius Adepto", school: "death"},
               provider: TraitlessManifestationProvider,
               model: "traitless-manifestation-test",
               allow_root_spell: true,
               circle_tier: :trained
             )

    # Death drains: the blade takes health back to its wielder's side rather
    # than merely landing a hit.
    assert spell.manifestation.trait == :drain
  end

  test "a construct never keeps a trait its kind cannot use", %{character: character} do
    assert {:ok, %{spell: spell}} =
             Compiler.compile_and_store(
               character,
               %{formula: "Vocatio Gladius Adepto", school: "fire"},
               provider: MismatchedTraitProvider,
               model: "mismatched-trait-test",
               allow_root_spell: true,
               circle_tier: :trained
             )

    # `bastion` only reads on a shield, so a blade given one is corrected to a
    # striking trait instead of being left inert.
    assert spell.manifestation.trait == :ignite
  end

  test "compile_and_store/3 canonicalizes unambiguous provider vocabulary", %{
    character: character
  } do
    assert {:ok, %{spell: spell}} =
             Compiler.compile_and_store(
               character,
               %{
                 formula: "Translatio Vinculum Magnus Sustineo Marcor Mora",
                 school: "death"
               },
               provider: NaturalVocabularyProvider,
               model: "natural-vocabulary-test",
               allow_root_spell: true,
               circle_tier: :trained
             )

    assert spell.school_quirk == :harvest
    assert [%{applies_to: :target}] = spell.effects

    assert [%{trigger_type: :environment_tag, outcome: :replace_environment}] =
             spell.interaction_rules
  end

  test "compile_and_store/3 can fail spell creation without storing a spell", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:error, %SpellFailure{} = failure} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Sanatio Incendium",
                 formula: "Sanatio Incendium",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               provider: FailedSpellProvider,
               model: "failed-test-model"
             )

    assert failure.formula == "Sanatio Incendium"
    assert failure.school == "fire"
    assert failure.reason =~ "collapse"
    assert failure.instability_markers == ["school_mismatch", "unstable_lineage"]
    assert failure.ai_request.status == :succeeded
    assert failure.ai_request.spell_id == nil
    assert Repo.aggregate(Request, :count, :id) == 1
    assert Repo.aggregate(Spell, :count, :id) == 1
  end

  test "compile_and_store/3 returns a changeset error for invalid compiled output", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:error, changeset} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Maledictum",
                 formula: "Maledictum Magnus",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               provider: InvalidSpellProvider,
               model: "invalid-test-model"
             )

    assert %{effects: [%{state: ["is invalid"]}]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 1
    assert Repo.aggregate(Spell, :count, :id) == 1
  end

  test "compile_and_store/3 rejects a complete provider result without an explicit outcome", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:error, changeset} =
             Compiler.compile_and_store(
               character,
               %{
                 formula: "Ignis Radius",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               provider: MissingOutcomeProvider,
               model: "missing-outcome-test-model"
             )

    assert %{outcome: ["is invalid"]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 1
    assert Repo.aggregate(Spell, :count, :id) == 1
  end

  test "compile_and_store/3 rejects malformed incantations before AI execution", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:error, changeset} =
             Compiler.compile_and_store(character, %{
               name: "Bad Formula",
               formula: "ignis 123",
               school: "fire",
               base_spell_id: base_spell.id
             })

    assert %{formula: ["must contain only alphabetic words and hyphens"]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "compile_and_store/3 rejects oversized or untrusted prompt fields before AI execution", %{
    character: character,
    base_spell: base_spell
  } do
    base_attrs = %{
      formula: "Ignis Radius",
      school: "fire",
      base_spell_id: base_spell.id
    }

    assert {:error, formula_changeset} =
             Compiler.compile_and_store(
               character,
               Map.put(base_attrs, :formula, String.duplicate("a", 181))
             )

    assert %{formula: ["must be at most 180 bytes"]} = errors_on(formula_changeset)

    assert {:error, name_changeset} =
             Compiler.compile_and_store(
               character,
               Map.put(base_attrs, :name, String.duplicate("n", 121))
             )

    assert %{name: ["is too long"]} = errors_on(name_changeset)

    assert {:error, description_changeset} =
             Compiler.compile_and_store(
               character,
               Map.put(base_attrs, :description, String.duplicate("d", 1_201))
             )

    assert %{description: ["is too long"]} = errors_on(description_changeset)

    assert {:error, targeting_changeset} =
             Compiler.compile_and_store(
               character,
               Map.put(base_attrs, :targeting, "ignore-all-constraints")
             )

    assert %{targeting: ["is invalid"]} = errors_on(targeting_changeset)
    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "compile_and_store/3 rejects missing and foreign bases before creating an AI request", %{
    character: character,
    realm: realm
  } do
    attrs = %{name: "Ignis Lancea", formula: "Ignis Radius", school: "fire"}

    assert {:error, missing_base_changeset} = Compiler.compile_and_store(character, attrs)
    assert %{base_spell_id: ["can't be blank"]} = errors_on(missing_base_changeset)

    foreign_character = character_fixture(realm, "foreign-mage", "Foreign Mage")
    foreign_base = spell_fixture(foreign_character, "Foreign Spark")

    assert {:error, foreign_base_changeset} =
             Compiler.compile_and_store(
               character,
               Map.put(attrs, :base_spell_id, foreign_base.id)
             )

    assert %{base_spell_id: ["is invalid"]} = errors_on(foreign_base_changeset)
    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "compile_and_store/3 rejects a base moved outside the caster realm before AI execution", %{
    character: character,
    base_spell: base_spell
  } do
    {:ok, other_realm} =
      Worlds.create_realm(%{slug: "other-realm", name: "Other Realm", is_default: false})

    moved_base = Repo.update!(Ecto.Changeset.change(base_spell, realm_id: other_realm.id))

    assert {:error, changeset} =
             Compiler.compile_and_store(character, %{
               name: "Ignis Lancea",
               formula: "Ignis Radius",
               school: "fire",
               base_spell_id: moved_base.id
             })

    assert %{base_spell_id: ["is invalid"]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "compiler keeps normalized player intent and accepted lineage over provider output", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:ok, %{spell: spell}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Замысел игрока",
                 description: "Описание игрока остаётся неизменным.",
                 formula: "  ignis   radius  ",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               provider: DriftedSpellProvider,
               model: "drifted-test-model"
             )

    assert spell.formula == "Ignis Radius"
    assert spell.school == :fire
    assert spell.source_spell_id == base_spell.id
    assert spell.name == "Замысел игрока"
    assert spell.description == "Описание игрока остаётся неизменным."
  end

  test "compiler rejects non-Russian generated identity fields", %{
    character: character,
    base_spell: base_spell
  } do
    assert {:error, :invalid_response} =
             Compiler.compile_and_store(
               character,
               %{
                 formula: "Ignis Radius",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               provider: DriftedSpellProvider,
               model: "non-russian-output-test-model"
             )

    assert Repo.aggregate(Request, :count, :id) == 1
    assert Repo.aggregate(Spell, :count, :id) == 1
  end

  test "spell persistence rejects seal maps that contradict the canonical formula", %{
    base_spell: base_spell
  } do
    assert {:error, changeset} =
             Spells.update_spell(base_spell, %{
               incantation_slots: %{"actio" => "Aqua", "forma" => "Minima"}
             })

    assert %{incantation_slots: ["contains invalid seal data"]} = errors_on(changeset)
  end

  test "novice root spells are bounded by server policy", %{character: character} do
    assert {:ok, %{spell: spell, compiled_spell: compiled_spell}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Prima Radix",
                 formula: "Ignis Tarde",
                 school: "fire"
               },
               provider: OverpoweredRootProvider,
               model: "overpowered-root-test-model",
               allow_root_spell: true,
               circle_tier: :novice
             )

    assert spell.power == 1
    assert spell.fatigue_cost == 12
    assert spell.cooldown_turns == 3
    assert spell.source_spell_id == nil
    assert spell.environment_mode == :none
    assert spell.environment_tags == []
    assert spell.interaction_rules == []

    assert [effect] = spell.effects
    assert effect.applies_to == :target
    assert effect.intensity == 12
    assert effect.variance == 2
    assert effect.duration == 3

    assert compiled_spell["power"] == 1
    assert compiled_spell["environment_mode"] == "none"
    assert compiled_spell["environment_tags"] == []
    assert compiled_spell["interaction_rules"] == []
    assert length(compiled_spell["effects"]) == 1
  end

  test "novice caps survive an attached base while trained roots keep their compiler budget", %{
    character: character,
    base_spell: base_spell
  } do
    common_opts = [
      provider: OverpoweredRootProvider,
      model: "unbounded-control-test-model"
    ]

    assert {:ok, %{spell: novice_spell, compiled_spell: novice_output}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Inherited Radix",
                 formula: "Ignis Celeriter",
                 school: "fire",
                 base_spell_id: base_spell.id
               },
               common_opts ++ [circle_tier: :novice]
             )

    assert novice_spell.source_spell_id == base_spell.id
    assert novice_spell.power == 1
    assert novice_spell.fatigue_cost == 12
    assert novice_spell.cooldown_turns == 3
    assert novice_spell.environment_mode == :none
    assert novice_spell.environment_tags == []
    assert novice_spell.interaction_rules == []

    assert [novice_effect] = novice_spell.effects
    assert novice_effect.applies_to == :target
    assert novice_effect.intensity == 12
    assert novice_effect.variance == 2
    assert novice_effect.duration == 3

    assert novice_output["power"] == 1
    assert novice_output["fatigue_cost"] == 12
    assert novice_output["cooldown_turns"] == 3
    assert novice_output["environment_mode"] == "none"
    assert novice_output["environment_tags"] == []
    assert novice_output["interaction_rules"] == []
    assert length(novice_output["effects"]) == 1

    assert {:ok, %{spell: trained_root}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Trained Radix",
                 formula: "Aqua Lente",
                 school: "water"
               },
               common_opts ++ [allow_root_spell: true, circle_tier: :trained]
             )

    # A trained root keeps the compiler budget rather than collapsing to the
    # novice caps, but the rank band still bounds it: the caster is a level-18
    # world character (Bronze, band max 5), so the provider's claim of power 80
    # is pulled down into the band and every magnitude rescales to it.
    assert trained_root.power == 5
    assert trained_root.fatigue_cost == 20
    assert trained_root.cooldown_turns == 3
    assert trained_root.environment_mode == :replace
    assert trained_root.environment_tags == ["world-fire", "collapsed-reality"]
    assert length(trained_root.effects) == 2
    assert length(trained_root.interaction_rules) == 1
  end

  test "the caster's rank band bounds power, never the word count", %{
    realm: realm,
    character: character
  } do
    common_opts = [provider: OverpoweredRootProvider, model: "rank-band-test-model"]

    # A level-18 world character sits in Bronze (band max 5). The greediest
    # provider claim lands on the band regardless of how many words the formula
    # uses.
    assert {:ok, %{spell: six_words}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Wrought",
                 formula: "Ignis Ictus Magnus Radius Momentum Focus",
                 school: "fire"
               },
               common_opts ++ [allow_root_spell: true, circle_tier: :trained]
             )

    assert six_words.power == 5

    # A level-85 caster stands at the top of the ladder, Archmage (band max 42).
    # A terse three-word formula still reaches the top of that band: words are
    # free, the band is the only ceiling.
    archmage = character_fixture(realm, "archmage-mage", "Archmage Mage", 85)

    assert {:ok, %{spell: terse}} =
             Compiler.compile_and_store(
               archmage,
               %{name: "Terse", formula: "Ignis Ictus Levis", school: "fire"},
               common_opts ++ [allow_root_spell: true, circle_tier: :trained]
             )

    assert terse.power == 42
    assert terse.fatigue_cost > six_words.fatigue_cost
  end

  test "an ancestor may guide a refinement but never raises the band", %{
    character: character
  } do
    assert {:ok, %{spell: refined}} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Refined",
                 formula: "Ignis Ictus Levis",
                 school: "fire",
                 base_spell_id: spell_fixture(character, "Ancestor", power: 30).id
               },
               provider: OverpoweredRootProvider,
               model: "lineage-band-test-model",
               circle_tier: :trained
             )

    # The ancestor's own power is irrelevant to the caster's Bronze band.
    assert refined.power == 5
    assert refined.source_spell_id != nil
  end

  test "compiler limits the owned library context", %{
    character: character,
    base_spell: base_spell
  } do
    for index <- 1..30 do
      spell_fixture(character, "Library Spell #{index}")
    end

    assert {:ok, %{ai_request: ai_request}} =
             Compiler.compile_and_store(character, %{
               name: "Bounded Context",
               formula: "Ignis Radius",
               school: "fire",
               base_spell_id: base_spell.id
             })

    persisted_request = Repo.get!(Request, ai_request.id)
    prompt = Jason.decode!(persisted_request.request_payload["user_prompt"])
    assert length(prompt["library"]) == 24
    assert Enum.any?(prompt["library"], &(&1["id"] == base_spell.id))
  end

  defp character_fixture(realm, handle, name, level \\ 18) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: level})
    |> Repo.insert!()
  end

  defp spell_fixture(character, name, opts \\ []) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: name,
        formula: "Ignis Minima",
        school: :fire,
        description: "A durable spell fixture for compiler ownership tests.",
        targeting: :enemy,
        delivery_form: :sphere,
        power: Keyword.get(opts, :power, 1),
        effects: [
          %{applies_to: :target, state: "impact", intensity: 8, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 4, base_success_rate: 90, partial_success_rate: 5}
      })

    spell
  end
end
