defmodule MMGO.Spells.RuntimeTest do
  use ExUnit.Case, async: true

  alias MMGO.Spells.{FailureProfile, Runtime, Spell}

  test "an explicitly certain spell remains certain at runtime" do
    spell = %Spell{
      failure_profile: %FailureProfile{base_success_rate: 100, difficulty: 12}
    }

    assert Runtime.success_rate(spell, 12) == 100
  end

  test "runtime success remains bounded after level and fatigue modifiers" do
    spell = %Spell{
      failure_profile: %FailureProfile{base_success_rate: 90, difficulty: 1}
    }

    assert Runtime.success_rate(spell, 99) == 100
    assert Runtime.success_rate(spell, 1, 500) == 5
  end
end
