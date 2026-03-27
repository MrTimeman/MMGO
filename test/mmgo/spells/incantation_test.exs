defmodule MMGO.Spells.IncantationTest do
  use ExUnit.Case, async: true

  alias MMGO.Spells.Incantation

  test "normalize/1 canonicalizes formula words" do
    assert {:ok, "Ignis-Radius Magnus"} = Incantation.normalize("  ignis-radius   magnus ")
  end

  test "normalize/1 rejects formulas with too many words" do
    assert {:error, :too_many_words} =
             Incantation.normalize("unus duo tres quattuor quinque sex septem")
  end

  test "normalize/1 rejects invalid characters" do
    assert {:error, :invalid_word} = Incantation.normalize("ignis 123")
  end
end
