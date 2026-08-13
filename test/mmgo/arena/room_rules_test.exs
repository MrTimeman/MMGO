defmodule MMGO.Arena.RoomRulesTest do
  @moduledoc """
  A friendly room is the only place the arena's constraints can be lifted, and
  only in the ways its host actually chose.
  """

  use ExUnit.Case, async: true

  alias MMGO.Arena.RoomRules
  alias MMGO.Combat.Combat

  describe "normalize/1" do
    test "an empty room is an ordinary one" do
      assert RoomRules.normalize(%{}) == RoomRules.defaults()
      assert RoomRules.normalize(nil) == RoomRules.defaults()
    end

    test "recognised rules are kept, however they were spelled" do
      assert %{"grimoire" => "free", "mana" => "unlimited", "rank_cap" => :gold} =
               RoomRules.normalize(%{
                 "mana" => "unlimited",
                 "rank_cap" => "gold",
                 grimoire: :free
               })
    end

    test "an unrecognised rule collapses to the ordinary arena, never past it" do
      assert RoomRules.normalize(%{
               "grimoire" => "everything",
               "mana" => "infinite",
               "rank_cap" => "demigod"
             }) == RoomRules.defaults()
    end
  end

  describe "for_combat/1" do
    test "a fight with nothing recorded is an ordinary fight" do
      assert RoomRules.for_combat(%Combat{metadata: %{}}) == RoomRules.defaults()
      refute RoomRules.free_grimoire?(%Combat{metadata: %{}})
      refute RoomRules.unlimited_mana?(%Combat{metadata: %{}})
      assert RoomRules.rank_cap(%Combat{metadata: %{}}) == nil
    end

    test "only what the server wrote counts" do
      combat = %Combat{
        metadata: %{
          RoomRules.metadata_key() => %{
            "grimoire" => "free",
            "mana" => "unlimited",
            "rank_cap" => "silver"
          }
        }
      }

      assert RoomRules.free_grimoire?(combat)
      assert RoomRules.unlimited_mana?(combat)
      assert RoomRules.rank_cap(combat) == :silver
    end
  end

  test "a room says what makes it unusual, and says nothing when it is ordinary" do
    assert RoomRules.summary(RoomRules.defaults()) == nil

    summary = RoomRules.summary(%{"grimoire" => "free", "rank_cap" => :gold})

    assert summary =~ "без гримуара"
    assert summary =~ "Золото"
  end
end
