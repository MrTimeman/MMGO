defmodule MMGO.Spells.IncantationTest do
  use ExUnit.Case, async: true

  alias MMGO.Spells.Incantation

  test "normalize/1 canonicalizes formula words" do
    assert {:ok, "Ignis-Radius Magnus"} = Incantation.normalize("  ignis-radius   magnus ")
  end

  test "normalize/1 resolves one-edit near-misses of documented parameter words" do
    assert {:ok, "Ictus Sphaera Magnus"} = Incantation.normalize("ictus sphera magnuz")
  end

  test "normalize/1 keeps an unknown but valid Latin word for AI interpretation" do
    assert {:ok, "Aeternitas"} = Incantation.normalize("aeternitas")
  end

  test "normalize/1 rejects formulas with too many words" do
    assert {:error, :too_many_words} =
             Incantation.normalize("unus duo tres quattuor quinque sex septem")
  end

  test "normalize/1 rejects invalid characters" do
    assert {:error, :invalid_word} = Incantation.normalize("ignis 123")
  end

  test "normalize/1 bounds formula bytes and individual words before canonicalizing" do
    assert {:error, :formula_too_long} = Incantation.normalize(String.duplicate("a", 181))
    assert {:error, :word_too_long} = Incantation.normalize(String.duplicate("a", 33))
  end

  test "normalize/1 safely rejects non-text input" do
    assert {:error, :invalid_formula} = Incantation.normalize(42)
    assert {:error, :invalid_encoding} = Incantation.normalize(<<255>>)
  end
end
