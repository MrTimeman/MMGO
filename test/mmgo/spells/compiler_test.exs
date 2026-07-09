defmodule MMGO.Spells.CompilerTest do
  use MMGO.DataCase, async: true

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
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

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "compiler-mage", "Compiler Mage")

    %{character: character}
  end

  test "compile_and_store/3 persists a compiled spell and AI request", %{character: character} do
    assert {:ok, %{spell: spell, ai_request: ai_request}} =
             Compiler.compile_and_store(character, %{
               name: "Ignis Lancea",
               formula: "Ignis Radius Magnus",
               school: "fire",
               targeting: "enemy",
               delivery_form: "beam"
             })

    assert spell.name == "Ignis Lancea"
    assert spell.creator_character_id == character.id
    assert ai_request.kind == :spell_compile
    assert ai_request.status == :succeeded
    assert ai_request.spell_id == spell.id
    assert Repo.aggregate(Request, :count, :id) == 1
  end

  test "compile_and_store/3 can fail spell creation without storing a spell", %{
    character: character
  } do
    assert {:error, %SpellFailure{} = failure} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Sanatio Incendium",
                 formula: "Sanatio Incendium",
                 school: "fire"
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
    assert Repo.aggregate(Spell, :count, :id) == 0
  end

  test "compile_and_store/3 returns a changeset error for invalid compiled output", %{
    character: character
  } do
    assert {:error, changeset} =
             Compiler.compile_and_store(
               character,
               %{
                 name: "Maledictum",
                 formula: "Maledictum Magnus",
                 school: "fire"
               },
               provider: InvalidSpellProvider,
               model: "invalid-test-model"
             )

    assert %{effects: [%{state: ["is invalid"]}]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 1
  end

  test "compile_and_store/3 rejects malformed incantations before AI execution", %{
    character: character
  } do
    assert {:error, changeset} =
             Compiler.compile_and_store(character, %{
               name: "Bad Formula",
               formula: "ignis 123",
               school: "fire"
             })

    assert %{formula: ["must contain only alphabetic words and hyphens"]} = errors_on(changeset)
    assert Repo.aggregate(Request, :count, :id) == 0
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
end
