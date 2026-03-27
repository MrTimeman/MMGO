defmodule MMGO.Spells.Incantation do
  @max_words 6
  @word_pattern ~r/^[[:alpha:]-]+$/u

  def normalize(formula) when is_binary(formula) do
    tokens =
      formula
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    cond do
      tokens == [] -> {:error, :empty_formula}
      length(tokens) > @max_words -> {:error, :too_many_words}
      Enum.any?(tokens, &(not Regex.match?(@word_pattern, &1))) -> {:error, :invalid_word}
      true -> {:ok, Enum.map_join(tokens, " ", &canonicalize_word/1)}
    end
  end

  defp canonicalize_word(word) do
    word
    |> String.downcase()
    |> String.split("-", trim: true)
    |> Enum.map_join("-", &String.capitalize/1)
  end
end
