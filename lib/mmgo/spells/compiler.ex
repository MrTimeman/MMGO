defmodule MMGO.Spells.Compiler do
  alias MMGO.AI
  alias MMGO.AI.Prompts.SpellCompilePrompt
  alias MMGO.Accounts.Character
  alias MMGO.Spells
  alias MMGO.Spells.{Incantation, Spell, SpellFailure}

  @library_context_limit 24
  @max_spell_name_bytes 120
  @max_spell_description_bytes 1_200
  @control_character_pattern ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u
  @cyrillic_pattern ~r/[А-Яа-яЁё]/u
  @latin_pattern ~r/[A-Za-z]/u
  @targeting_modes ~w(self ally enemy zone)
  @delivery_forms ~w(single_target beam cone sphere wall zone self link delayed_trigger)
  @novice_root_max_intensity 12
  @novice_root_max_duration 3
  @novice_root_max_variance 2
  @novice_root_max_fatigue_cost 12
  @novice_root_max_cooldown_turns 3

  def compile_and_store(%Character{} = character, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, request} <- normalize_request(attrs),
         {:ok, base_spell} <- resolve_owned_base_spell(character, request, opts) do
      schools = Keyword.get(opts, :schools, %{})
      environment_tags = Keyword.get(opts, :environment_tags, [])

      prompt_payload =
        SpellCompilePrompt.build(%{
          character: %{
            id: character.id,
            level: character.level,
            realm_id: character.realm_id,
            school_primary: schools[:primary],
            school_secondary: schools[:secondary]
          },
          environment_tags: environment_tags,
          request: prompt_request(request, opts),
          base_spell: base_spell_summary(base_spell),
          circle_tier: Keyword.get(opts, :circle_tier, :trained),
          library: owned_library_summary(character),
          states: Spell.effect_states()
        })

      ai_opts =
        Keyword.put_new(opts, :metadata, %{
          character_id: character.id,
          formula: request["formula"]
        })

      with {:ok, %{compiled_spell: compiled_spell, ai_request: ai_request}} <-
             AI.compile_spell(prompt_payload, ai_opts) do
        case compile_outcome(compiled_spell) do
          :created ->
            with :ok <- validate_created_player_facing_output(request, compiled_spell),
                 compiled_spell <- normalize_engine_vocabulary(compiled_spell),
                 compiled_spell <- enforce_circle_limits(compiled_spell, base_spell, opts),
                 spell_attrs <- merge_spell_attrs(request, base_spell, compiled_spell, opts),
                 {:ok, spell} <-
                   Spells.create_spell(character, spell_attrs,
                     creation_attempt_id: Keyword.get(opts, :creation_attempt_id)
                   ),
                 {:ok, updated_request} <- AI.update_request(ai_request, %{spell_id: spell.id}) do
              {:ok, %{spell: spell, ai_request: updated_request, compiled_spell: compiled_spell}}
            end

          :failed ->
            {:error, spell_failure(request, compiled_spell, ai_request)}

          :invalid ->
            {:error, compiler_request_changeset(:outcome, "is invalid")}
        end
      end
    end
  end

  defp compile_outcome(compiled_spell) do
    case Map.get(compiled_spell, "outcome") || Map.get(compiled_spell, :outcome) do
      "created" -> :created
      :created -> :created
      "failed" -> :failed
      :failed -> :failed
      _other -> :invalid
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

    with {:ok, request} <-
           normalize_optional_text(request, "name", :name, @max_spell_name_bytes),
         {:ok, request} <-
           normalize_optional_text(
             request,
             "description",
             :description,
             @max_spell_description_bytes
           ),
         {:ok, request} <-
           normalize_optional_enum(request, "targeting", :targeting, @targeting_modes),
         {:ok, request} <-
           normalize_optional_enum(request, "delivery_form", :delivery_form, @delivery_forms),
         {:ok, normalized_formula} <- normalize_formula(request),
         {:ok, normalized_school} <- normalize_school(request) do
      {:ok,
       request
       |> Map.put("formula", normalized_formula)
       |> Map.put("school", normalized_school)}
    end
  end

  defp prompt_request(request, opts) do
    case Keyword.get(opts, :incantation_slots) do
      slots when is_map(slots) -> Map.put(request, "incantation_slots", slots)
      _missing -> request
    end
  end

  defp merge_spell_attrs(request, base_spell, compiled_spell, opts) do
    compiled_spell
    |> Map.merge(%{
      "name" => Map.get(request, "name") || output_value(compiled_spell, "name"),
      "formula" => Map.fetch!(request, "formula"),
      "school" => Map.fetch!(request, "school"),
      "description" =>
        Map.get(request, "description") || output_value(compiled_spell, "description"),
      "targeting" =>
        Map.get(compiled_spell, "targeting") || Map.get(request, "targeting") || "enemy",
      "delivery_form" =>
        Map.get(compiled_spell, "delivery_form") || Map.get(request, "delivery_form") || "sphere",
      "source_spell_id" => base_spell && base_spell.id,
      "incantation_slots" => incantation_slots(opts)
    })
  end

  # Providers occasionally use natural-language aliases even when the intended
  # engine operation is unambiguous. Canonicalize only this deliberately small
  # vocabulary; unknown values must still fail the deterministic changeset.
  defp normalize_engine_vocabulary(compiled_spell) do
    compiled_spell
    |> Map.update("effects", [], fn effects ->
      Enum.map(effects, fn effect ->
        Map.update(effect, "applies_to", nil, &normalize_applies_to/1)
      end)
    end)
    |> Map.update("interaction_rules", [], fn rules ->
      Enum.map(rules, fn rule ->
        rule
        |> Map.update("trigger_type", nil, &normalize_trigger_type/1)
        |> Map.update("outcome", nil, &normalize_interaction_outcome/1)
      end)
    end)
  end

  defp normalize_applies_to(value) when value in ["enemy", "ally", "target"], do: "target"
  defp normalize_applies_to(value) when value in ["self", "caster"], do: "caster"
  defp normalize_applies_to(value), do: value

  defp normalize_trigger_type("environment"), do: "environment_tag"
  defp normalize_trigger_type("state"), do: "target_state"
  defp normalize_trigger_type("spell"), do: "spell_tag"
  defp normalize_trigger_type(value), do: value

  defp normalize_interaction_outcome("replace"), do: "replace_environment"
  defp normalize_interaction_outcome("bonus_state"), do: "apply_bonus_state"
  defp normalize_interaction_outcome(value), do: value

  defp validate_created_player_facing_output(request, compiled_spell) do
    with :ok <-
           validate_generated_russian_text(
             Map.get(request, "name"),
             output_value(compiled_spell, "name"),
             @max_spell_name_bytes
           ),
         :ok <-
           validate_generated_russian_text(
             Map.get(request, "description"),
             output_value(compiled_spell, "description"),
             @max_spell_description_bytes
           ) do
      :ok
    end
  end

  # Explicit, normalized caller text remains authoritative. When the compiler
  # must generate player-facing prose, however, the Russian-only contract is
  # enforced server-side rather than trusted to prompt adherence.
  defp validate_generated_russian_text(request_text, _compiled_text, _max_bytes)
       when is_binary(request_text),
       do: :ok

  defp validate_generated_russian_text(nil, compiled_text, max_bytes)
       when is_binary(compiled_text) do
    if String.valid?(compiled_text) do
      normalized_text = String.trim(compiled_text)

      if normalized_text != "" and byte_size(compiled_text) <= max_bytes and
           not Regex.match?(@control_character_pattern, compiled_text) and
           Regex.match?(@cyrillic_pattern, compiled_text) and
           not Regex.match?(@latin_pattern, compiled_text) do
        :ok
      else
        {:error, :invalid_response}
      end
    else
      {:error, :invalid_response}
    end
  end

  defp validate_generated_russian_text(nil, _compiled_text, _max_bytes),
    do: {:error, :invalid_response}

  defp output_value(map, "name"), do: Map.get(map, "name") || Map.get(map, :name)

  defp output_value(map, "description"),
    do: Map.get(map, "description") || Map.get(map, :description)

  defp incantation_slots(opts) do
    case Keyword.get(opts, :incantation_slots) do
      slots when is_map(slots) -> slots
      _missing -> %{}
    end
  end

  # The server-selected circle tier, not spell lineage, owns the mechanical
  # budget. The reduced three-seal circle may attach a known same-school spell
  # as provenance, but that must never promote a novice compilation into the
  # inherited budget of a trained circle.
  defp enforce_circle_limits(compiled_spell, _base_spell, opts) do
    if Keyword.get(opts, :circle_tier) == :novice do
      compiled_spell
      |> Map.put("level_requirement", 1)
      |> Map.put(
        "fatigue_cost",
        bounded_integer(
          Map.get(compiled_spell, "fatigue_cost"),
          @novice_root_max_fatigue_cost
        )
      )
      |> Map.put(
        "cooldown_turns",
        bounded_integer(
          Map.get(compiled_spell, "cooldown_turns"),
          @novice_root_max_cooldown_turns
        )
      )
      |> Map.put("effects", novice_root_effects(compiled_spell))
      |> Map.put("interaction_rules", [])
      |> Map.put("environment_mode", "none")
      |> Map.put("environment_tags", [])
      |> Map.put("school_quirk", nil)
    else
      compiled_spell
    end
  end

  defp novice_root_effects(compiled_spell) do
    case Map.get(compiled_spell, "effects") do
      [effect | _rest] when is_map(effect) ->
        intensity =
          effect
          |> Map.get("intensity")
          |> bounded_integer(@novice_root_max_intensity)

        variance =
          effect
          |> Map.get("variance")
          |> bounded_integer(min(@novice_root_max_variance, intensity))

        duration =
          effect
          |> Map.get("duration")
          |> bounded_integer(@novice_root_max_duration)

        [
          effect
          |> Map.update("applies_to", "target", fn
            "environment" -> "target"
            applies_to -> applies_to
          end)
          |> Map.put("intensity", intensity)
          |> Map.put("variance", variance)
          |> Map.put("duration", duration)
        ]

      _missing_or_invalid ->
        []
    end
  end

  defp bounded_integer(value, maximum) when is_integer(value) do
    value
    |> max(0)
    |> min(maximum)
  end

  defp bounded_integer(_value, _maximum), do: 0

  defp spell_failure(request, compiled_spell, ai_request) do
    %SpellFailure{
      reason:
        Map.get(compiled_spell, "rejection_reason") ||
          Map.get(compiled_spell, :rejection_reason) ||
          "Заклинание не сложилось в устойчивую формулу.",
      formula: Map.get(request, "formula"),
      school: Map.get(request, "school"),
      ai_request: ai_request,
      instability_markers:
        Map.get(compiled_spell, "instability_markers") ||
          Map.get(compiled_spell, :instability_markers) ||
          [],
      details: Map.get(compiled_spell, "details") || Map.get(compiled_spell, :details) || %{}
    }
  end

  defp normalize_formula(request) do
    case Map.get(request, "formula") do
      nil ->
        {:error, compiler_request_changeset(:formula, "can't be blank")}

      formula ->
        case Incantation.normalize(formula) do
          {:ok, normalized_formula} ->
            {:ok, normalized_formula}

          {:error, :empty_formula} ->
            {:error, compiler_request_changeset(:formula, "can't be blank")}

          {:error, :too_many_words} ->
            {:error, compiler_request_changeset(:formula, "must contain at most 6 words")}

          {:error, :formula_too_long} ->
            {:error, compiler_request_changeset(:formula, "must be at most 180 bytes")}

          {:error, :word_too_long} ->
            {:error, compiler_request_changeset(:formula, "words must be at most 32 bytes")}

          {:error, :invalid_encoding} ->
            {:error, compiler_request_changeset(:formula, "must be valid text")}

          {:error, :invalid_word} ->
            {:error,
             compiler_request_changeset(
               :formula,
               "must contain only alphabetic words and hyphens"
             )}

          {:error, :invalid_formula} ->
            {:error, compiler_request_changeset(:formula, "must be text")}
        end
    end
  end

  defp normalize_optional_text(request, field, error_field, max_bytes) do
    case Map.get(request, field) do
      nil ->
        {:ok, request}

      text when is_binary(text) ->
        cond do
          byte_size(text) > max_bytes ->
            {:error, compiler_request_changeset(error_field, "is too long")}

          not String.valid?(text) ->
            {:error, compiler_request_changeset(error_field, "must be valid text")}

          true ->
            normalized_text =
              text
              |> String.trim()
              |> String.replace(~r/\s+/u, " ")

            if Regex.match?(@control_character_pattern, normalized_text) do
              {:error,
               compiler_request_changeset(
                 error_field,
                 "contains unsupported control characters"
               )}
            else
              {:ok,
               if(normalized_text == "",
                 do: Map.delete(request, field),
                 else: Map.put(request, field, normalized_text)
               )}
            end
        end

      _other ->
        {:error, compiler_request_changeset(error_field, "must be text")}
    end
  end

  defp normalize_optional_enum(request, field, error_field, allowed_values) do
    case Map.get(request, field) do
      nil ->
        {:ok, request}

      value ->
        if value in allowed_values do
          {:ok, request}
        else
          {:error, compiler_request_changeset(error_field, "is invalid")}
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

  defp resolve_owned_base_spell(character, request, opts) do
    case Map.get(request, "base_spell_id") do
      spell_id when is_binary(spell_id) ->
        if String.trim(spell_id) == "" do
          {:error, compiler_request_changeset(:base_spell_id, "can't be blank")}
        else
          case Spells.get_owned_spell(character, spell_id) do
            nil -> {:error, compiler_request_changeset(:base_spell_id, "is invalid")}
            spell -> {:ok, spell}
          end
        end

      _missing ->
        if Keyword.get(opts, :allow_root_spell, false) do
          {:ok, nil}
        else
          {:error, compiler_request_changeset(:base_spell_id, "can't be blank")}
        end
    end
  end

  defp owned_library_summary(character) do
    character.id
    |> Spells.list_spells_for_character()
    |> Enum.take(@library_context_limit)
    |> Enum.map(&library_spell_summary/1)
  end

  defp library_spell_summary(spell) do
    %{
      id: spell.id,
      name: spell.name,
      formula: spell.formula,
      school: spell.school,
      school_quirk: spell.school_quirk,
      incantation_slots: spell.incantation_slots,
      source_spell_id: spell.source_spell_id
    }
  end

  defp base_spell_summary(nil), do: nil

  defp base_spell_summary(spell) do
    %{
      id: spell.id,
      name: spell.name,
      formula: spell.formula,
      school: spell.school,
      school_quirk: spell.school_quirk,
      incantation_slots: spell.incantation_slots,
      description: bounded_prompt_text(spell.description, @max_spell_description_bytes),
      effects: Enum.map(spell.effects, &effect_summary/1)
    }
  end

  defp effect_summary(effect) do
    %{
      applies_to: effect.applies_to,
      state: effect.state,
      intensity: effect.intensity,
      variance: effect.variance,
      duration: effect.duration,
      tags: effect.tags
    }
  end

  defp bounded_prompt_text(text, max_bytes) when is_binary(text) do
    if byte_size(text) <= max_bytes and String.valid?(text) do
      text
    else
      ""
    end
  end

  defp bounded_prompt_text(_text, _max_bytes), do: ""

  defp compiler_request_changeset(field, message) do
    {%{},
     %{
       name: :string,
       description: :string,
       formula: :string,
       school: :string,
       base_spell_id: :string,
       targeting: :string,
       delivery_form: :string
     }}
    |> Ecto.Changeset.cast(%{}, [])
    |> Ecto.Changeset.add_error(field, message)
  end
end
