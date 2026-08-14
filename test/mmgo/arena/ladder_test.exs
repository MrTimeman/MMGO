defmodule MMGO.Arena.LadderTest do
  use ExUnit.Case, async: true

  alias MMGO.Arena.Ladder

  # An even matchup: expectation is exactly one half.
  @even 0.5
  @win 1.0
  @loss 0.0

  test "the early ladder rewards a win far more than it punishes a defeat" do
    gained = Ladder.settle(950, :bronze, @even, @win).rating - 950
    lost = 950 - Ladder.settle(950, :bronze, @even, @loss).rating

    assert gained > lost * 2
  end

  test "the top of the ladder costs more to hold than to reach" do
    gained = Ladder.settle(2_600, :champion, @even, @win).rating - 2_600
    lost = 2_600 - Ladder.settle(2_600, :champion, @even, @loss).rating

    assert lost > gained
  end

  test "climbing slows as the divisions rise" do
    early = Ladder.settle(950, :bronze, @even, @win).rating - 950
    middle = Ladder.settle(1_450, :gold, @even, @win).rating - 1_450
    late = Ladder.settle(2_200, :archmage, @even, @win).rating - 2_200

    assert early > middle
    assert middle > late
  end

  test "promotion is immediate once the floor is reached" do
    # A bronze profile one win away from silver's 1150 floor.
    assert %{division: :silver} = Ladder.settle(1_140, :bronze, @even, @win)
  end

  test "a dip below the floor does not demote, a clear fall does" do
    # Silver's floor is 1150 and the buffer is 40.
    assert %{division: :silver} = Ladder.settle(1_155, :silver, @even, @loss)
    assert %{division: :bronze} = Ladder.settle(1_120, :silver, @even, @loss)
  end

  test "rating never falls below zero" do
    assert %{rating: 0} = Ladder.settle(3, :initiate, 0.9, @loss)
  end

  test "divisions order from initiate to champion" do
    assert Ladder.at_least?(:champion, :initiate)
    assert Ladder.at_least?(:gold, :gold)
    refute Ladder.at_least?(:bronze, :diamond)
  end

  test "an unknown held division falls back to what the rating earned" do
    assert %{division: division} = Ladder.settle(1_500, nil, @even, @loss)
    assert division in Ladder.keys()
  end

  test "craft power reads across the whole ladder" do
    # The seal ceilings from MMGO.Spells.Compiler, division by division.
    assert Ladder.division_for_power(3) == :initiate
    assert Ladder.division_for_power(4) == :bronze
    assert Ladder.division_for_power(5) == :bronze
    assert Ladder.division_for_power(15) == :gold
    assert Ladder.division_for_power(30) == :diamond
    assert Ladder.division_for_power(50) == :champion
  end

  test "power below the first gate still lands on the foot of the ladder" do
    assert Ladder.division_for_power(0) == :initiate
    assert Ladder.division_for_power(-5) == :initiate
    assert Ladder.division_for_power(nil) == :initiate
  end

  test "the seats hold the widest mana pools" do
    ordinary =
      Enum.map([:initiate, :bronze, :silver, :gold, :platinum, :diamond], &Ladder.max_mana_for/1)

    assert Ladder.max_mana_for(:champion) > Ladder.deputy_mana()
    assert Ladder.deputy_mana() > Ladder.max_mana_for(:archmage)
    assert Enum.all?(ordinary, &(&1 < Ladder.max_mana_for(:archmage)))
    assert ordinary == Enum.sort(ordinary)
  end

  test "regen is a share of the pool with a floor" do
    assert Ladder.regen_for(260) == 26
    assert Ladder.regen_for(100) == 10
    assert Ladder.regen_for(40) == 8
  end
end

defmodule MMGO.Arena.LadderCapacityTest do
  use ExUnit.Case, async: true

  alias MMGO.Arena.Ladder

  test "books grow with the ladder and the seats sit above it" do
    assert Ladder.grimoire_capacity(:initiate) == 15
    assert Ladder.grimoire_capacity(:bronze) == 15
    assert Ladder.grimoire_capacity(:silver) == 20
    assert Ladder.grimoire_capacity(:gold) == 25
    assert Ladder.grimoire_capacity(:platinum) == 30
    assert Ladder.grimoire_capacity(:diamond) == 35
    assert Ladder.grimoire_capacity(:archmage) == 40
    assert Ladder.grimoire_capacity(:champion) == 45
    assert Ladder.deputy_grimoire_capacity() == 45
  end

  test "rank bands top out at the strongest power" do
    assert Ladder.power_band(:bronze) == {4, 5}
    assert Ladder.power_band(:champion) == {43, 60}
    assert Ladder.power_band(:initiate) == {0, 3}
  end

  test "a world character's level stands in for the ladder" do
    assert Ladder.division_for_level(1) == :initiate
    assert Ladder.division_for_level(18) == :bronze
    assert Ladder.division_for_level(35) == :gold

    # No level reaches the Champion's band: that rank is a seat, and a world
    # character does not sit in it.
    assert Ladder.division_for_level(85) == :archmage
    assert Ladder.division_for_level(100) == :archmage
  end

  test "rating tops out at Archmage and the seat sits above it" do
    assert Ladder.ladder_ceiling() == :archmage
    assert Ladder.seat_division() == :champion

    # Ratings far past the old Champion floor still settle at Archmage.
    assert Ladder.division_for_rating(2_150) == :archmage
    assert Ladder.division_for_rating(2_500) == :archmage
    assert Ladder.division_for_rating(9_000) == :archmage

    # Settling can never promote into the seat either.
    assert %{division: :archmage} = Ladder.settle(2_600, :archmage, 0.1, 1.0)
  end
end
