defmodule MMGO.Spells.Incantation do
  @max_words 6
  @max_formula_bytes 180
  @max_word_bytes 32
  @word_pattern ~r/^\p{Latin}+(?:-\p{Latin}+)*$/u
  @known_words ~w(
    Ictus Captio Scutum Sanatio Vocatio
    Radius Sphaera Murus Conus Nexus
    Levis Mediocris Magnus Enormis
    Momentum Sustineo Tardus
    Motus Glacies Dissipatio
    Sanguis Mora Focus
  )

  def normalize(formula) when is_binary(formula) do
    cond do
      byte_size(formula) > @max_formula_bytes ->
        {:error, :formula_too_long}

      not String.valid?(formula) ->
        {:error, :invalid_encoding}

      true ->
        normalize_valid_formula(formula)
    end
  end

  def normalize(_formula), do: {:error, :invalid_formula}

  defp normalize_valid_formula(formula) do
    tokens =
      formula
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    cond do
      tokens == [] -> {:error, :empty_formula}
      length(tokens) > @max_words -> {:error, :too_many_words}
      Enum.any?(tokens, &(byte_size(&1) > @max_word_bytes)) -> {:error, :word_too_long}
      Enum.any?(tokens, &(not Regex.match?(@word_pattern, &1))) -> {:error, :invalid_word}
      true -> {:ok, Enum.map_join(tokens, " ", &canonicalize_word/1)}
    end
  end

  defp canonicalize_word(word) do
    canonical_word =
      word
      |> String.downcase()
      |> String.split("-", trim: true)
      |> Enum.map_join("-", &String.capitalize/1)

    correct_obvious_typo(canonical_word)
  end

  # The vocabulary stays open-ended: only a one-edit near-miss of one of the
  # documented parameter examples is corrected. Everything else reaches the AI
  # unchanged, so players can still invent expressive Latin terms.
  defp correct_obvious_typo(word) do
    if String.contains?(word, "-") do
      word
    else
      case closest_known_word(word) do
        {known_word, distance} when distance <= 1 -> known_word
        _ -> word
      end
    end
  end

  defp closest_known_word(word) do
    word_folded = String.downcase(word)

    @known_words
    |> Enum.map(fn known_word ->
      {known_word, levenshtein_distance(word_folded, String.downcase(known_word))}
    end)
    |> Enum.min_by(fn {known_word, distance} -> {distance, known_word} end)
  end

  defp levenshtein_distance(left, right) do
    right_graphemes = String.graphemes(right)
    initial_row = Enum.to_list(0..length(right_graphemes))

    left
    |> String.graphemes()
    |> Enum.with_index(1)
    |> Enum.reduce(initial_row, fn {left_grapheme, row_index}, previous_row ->
      {row_reversed, _above_left} =
        right_graphemes
        |> Enum.with_index(1)
        |> Enum.reduce({[row_index], hd(previous_row)}, fn {right_grapheme, column_index},
                                                           {row, above_left} ->
          left_cost = hd(row)
          above = Enum.at(previous_row, column_index)
          substitution_cost = if left_grapheme == right_grapheme, do: 0, else: 1

          current = min(min(left_cost + 1, above + 1), above_left + substitution_cost)
          {[current | row], above}
        end)

      Enum.reverse(row_reversed)
    end)
    |> List.last()
  end
end
