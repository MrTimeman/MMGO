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
         "name" => "Broken Spell",
         "formula" => "Maledictum",
         "school" => "fire",
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
    assert [%{"id" => base_id} | _rest] = prompt["library"]
    assert base_id == base_spell.id
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
                 name: "Player Intent",
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

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 18})
    |> Repo.insert!()
  end

  defp spell_fixture(character, name) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: name,
        formula: "Ignis Minima",
        school: :fire,
        description: "A durable spell fixture for compiler ownership tests.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 8, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 4, base_success_rate: 90, partial_success_rate: 5}
      })

    spell
  end
end
