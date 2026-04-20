defmodule MMGO.Spells.Compiler do
  alias MMGO.AI
  alias MMGO.AI.Prompts.SpellCompilePrompt
  alias MMGO.Accounts.Character
  alias MMGO.Spells
  alias MMGO.Spells.{Incantation, Spell}

  def compile_and_store(%Character{} = character, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, request} <- normalize_request(attrs) do
      prompt_payload =
        SpellCompilePrompt.build(%{
          character: %{
            id: character.id,
            level: character.level,
            realm_id: character.realm_id
          },
          request: request,
          states: Spell.effect_states()
        })

      ai_opts =
        Keyword.put_new(opts, :metadata, %{
          character_id: character.id,
          formula: request["formula"]
        })

      with {:ok, %{compiled_spell: compiled_spell, ai_request: ai_request}} <-
             AI.compile_spell(prompt_payload, ai_opts),
           spell_attrs <- merge_spell_attrs(request, compiled_spell),
           {:ok, spell} <- Spells.create_spell(character, spell_attrs),
           {:ok, updated_request} <- AI.update_request(ai_request, %{spell_id: spell.id}) do
        {:ok, %{spell: spell, ai_request: updated_request, compiled_spell: compiled_spell}}
      end
    end
  end

  defp normalize_request(attrs) do
    request =
      attrs
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
      |> Map.take([
        "name",
        "formula",
        "school",
        "description",
        "targeting",
        "delivery_form",
        "base_spell_id"
      ])

    with {:ok, formula_analysis} <- normalize_formula(request),
         {:ok, normalized_school} <- normalize_school(request) do
      {:ok,
       request
       |> Map.put("formula", formula_analysis.normalized_formula)
       |> Map.put("incantation_analysis", formula_analysis)
       |> Map.put("school", normalized_school)}
    end
  end

  defp merge_spell_attrs(request, compiled_spell) do
    compiled_spell
    |> Map.merge(%{
      "name" => Map.get(compiled_spell, "name") || Map.get(request, "name"),
      "formula" => Map.get(compiled_spell, "formula") || Map.get(request, "formula"),
      "school" => Map.get(compiled_spell, "school") || Map.get(request, "school"),
      "description" => Map.get(compiled_spell, "description") || Map.get(request, "description"),
      "targeting" =>
        Map.get(compiled_spell, "targeting") || Map.get(request, "targeting") || "enemy",
      "delivery_form" =>
        Map.get(compiled_spell, "delivery_form") || Map.get(request, "delivery_form") || "sphere",
      "source_spell_id" => Map.get(request, "base_spell_id")
    })
  end

  defp normalize_formula(request) do
    case Map.get(request, "formula") do
      nil ->
        {:error, compiler_request_changeset(:formula, "can't be blank")}

      formula ->
        case Incantation.analyze(formula) do
          {:ok, formula_analysis} ->
            {:ok, formula_analysis}

          {:error, :empty_formula} ->
            {:error, compiler_request_changeset(:formula, "can't be blank")}

          {:error, :too_many_words} ->
            {:error, compiler_request_changeset(:formula, "must contain at most 6 words")}

          {:error, :invalid_word} ->
            {:error,
             compiler_request_changeset(
               :formula,
               "must contain only alphabetic words and hyphens"
             )}
        end
    end
  end

  defp normalize_school(request) do
    case Map.get(request, "school") do
      school
      when school in ["fire", "water", "earth", "air", "life", "death", "chaos", "order"] ->
        {:ok, school}

      nil ->
        {:error, compiler_request_changeset(:school, "can't be blank")}

      _other ->
        {:error, compiler_request_changeset(:school, "is invalid")}
    end
  end

  defp compiler_request_changeset(field, message) do
    {%{}, %{formula: :string, school: :string}}
    |> Ecto.Changeset.cast(%{}, [])
    |> Ecto.Changeset.add_error(field, message)
  end
end
