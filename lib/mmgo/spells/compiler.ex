defmodule MMGO.Spells.Compiler do
  alias MMGO.AI
  alias MMGO.AI.Prompts.SpellCompilePrompt
  alias MMGO.Accounts.Character
  alias MMGO.Spells
  alias MMGO.Spells.Spell

  def compile_and_store(%Character{} = character, attrs, opts \\ []) when is_map(attrs) do
    request = normalize_request(attrs)

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

    ai_opts = Keyword.put_new(opts, :metadata, %{character_id: character.id})

    with {:ok, %{compiled_spell: compiled_spell, ai_request: ai_request}} <-
           AI.compile_spell(prompt_payload, ai_opts),
         spell_attrs <- merge_spell_attrs(request, compiled_spell),
         {:ok, spell} <- Spells.create_spell(character, spell_attrs),
         {:ok, updated_request} <- AI.update_request(ai_request, %{spell_id: spell.id}) do
      {:ok, %{spell: spell, ai_request: updated_request, compiled_spell: compiled_spell}}
    end
  end

  defp normalize_request(attrs) do
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
end
