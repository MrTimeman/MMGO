defmodule MMGO.Spells.Incantation do
  @max_words 6
  @word_pattern ~r/^[[:alpha:]-]+$/u

  @slot_defs [
    %{index: 1, id: "actio", label: "Actio", role: "core action"},
    %{index: 2, id: "forma", label: "Forma", role: "shape"},
    %{index: 3, id: "vis", label: "Vis", role: "intensity"},
    %{index: 4, id: "tempus", label: "Tempus", role: "duration"},
    %{index: 5, id: "mutatio", label: "Mutatio", role: "secondary effect"},
    %{index: 6, id: "pretium", label: "Pretium", role: "extra cost"}
  ]

  @known_words ~w(
    Ictus Captio Scutum Sanatio Vocatio
    Radius Sphaera Murus Conus Nexus
    Levis Mediocris Magnus Enormis
    Momentum Sustineo Tardus
    Motus Glacies Dissipatio
    Sanguis Mora Focus
    Ignis Aqua Terra Aer Vita Mors Ordo Chaos Lux Revelio Chorus
  )

  def normalize(formula) when is_binary(formula) do
    case analyze(formula) do
      {:ok, analysis} -> {:ok, analysis.normalized_formula}
      {:error, reason} -> {:error, reason}
    end
  end

  def analyze(formula) when is_binary(formula) do
    tokens =
      formula
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    cond do
      tokens == [] ->
        {:error, :empty_formula}

      length(tokens) > @max_words ->
        {:error, :too_many_words}

      Enum.any?(tokens, &(not Regex.match?(@word_pattern, &1))) ->
        {:error, :invalid_word}

      true ->
        corrected_tokens =
          Enum.map(tokens, fn token ->
            canonical = canonicalize_word(token)
            corrected = nearest_known_word(canonical)

            %{
              original: token,
              canonical: canonical,
              corrected: corrected,
              corrected?: corrected != canonical
            }
          end)

        {:ok,
         %{
           normalized_formula: Enum.map_join(corrected_tokens, " ", & &1.corrected),
           words:
             Enum.map(Enum.with_index(corrected_tokens, 1), fn {token, index} ->
               slot = Enum.at(@slot_defs, index - 1)

               %{
                 index: index,
                 slot_id: slot.id,
                 slot_label: slot.label,
                 slot_role: slot.role,
                 original: token.original,
                 canonical: token.canonical,
                 corrected: token.corrected,
                 corrected?: token.corrected?
               }
             end)
         }}
    end
  end

  def slot_definitions, do: @slot_defs

  defp canonicalize_word(word) do
    word
    |> String.downcase()
    |> String.split("-", trim: true)
    |> Enum.map_join("-", &String.capitalize/1)
  end

  defp nearest_known_word(word) do
    case Enum.find(@known_words, &(&1 == word)) do
      nil ->
        {candidate, score} =
          Enum.reduce(@known_words, {word, 0.0}, fn known, {best_word, best_score} ->
            score = String.jaro_distance(word, known)

            if score > best_score do
              {known, score}
            else
              {best_word, best_score}
            end
          end)

        if score >= 0.92, do: candidate, else: word

      known_word ->
        known_word
    end
  end
end
