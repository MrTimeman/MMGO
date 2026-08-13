defmodule MMGO.Arena.Ladder do
  @moduledoc """
  The competitive ladder: divisions, the rating movement that carries a profile
  between them, and the promotion/demotion rules.

  Climbing is deliberately asymmetric. A newcomer gains far more from a win than
  they lose from a defeat, so the early divisions sort quickly and forgivingly.
  The two rates converge around the middle and invert at the top, where holding
  a division is meant to cost more than reaching it did.

  A held division is stored on the profile rather than derived from rating alone,
  so a player who dips a point below a threshold does not flicker between
  divisions. Demotion only happens once they fall a clear margin below it.
  """

  # `floor` is the rating that promotes into the division. `win`/`loss` are the
  # Elo K-factors applied to that division's holder.
  @divisions [
    %{key: :initiate, floor: 0, win: 56, loss: 16},
    %{key: :bronze, floor: 900, win: 48, loss: 20},
    %{key: :silver, floor: 1_150, win: 40, loss: 26},
    %{key: :gold, floor: 1_400, win: 34, loss: 30},
    %{key: :platinum, floor: 1_650, win: 28, loss: 28},
    %{key: :diamond, floor: 1_900, win: 22, loss: 24},
    %{key: :archmage, floor: 2_150, win: 16, loss: 20},
    %{key: :champion, floor: 2_500, win: 12, loss: 18}
  ]

  # How far below its floor a rating must fall before the division is lost.
  @demotion_buffer 40

  # How much harder a placement match moves the rating.
  @placement_multiplier 2

  @keys Enum.map(@divisions, & &1.key)

  # The craft power each division opens. A spell's rank requirement is the
  # strongest division whose gate its power clears, so the seal ceilings in
  # `MMGO.Spells.Compiler` land across the ladder: a three-seal formula (5) is a
  # Bronze spell, a four-seal one (15) a Gold spell, and only a full six-seal
  # formula or a long lineage reaches the Champion's seat.
  @power_gates [
    initiate: 0,
    bronze: 4,
    silver: 6,
    gold: 11,
    platinum: 16,
    diamond: 23,
    archmage: 31,
    champion: 43
  ]

  # Mana pools widen with the ladder, compensating for the stronger spells a
  # higher rank may wield. The Champion's seat holds the largest pool of all;
  # the Deputy's sits just below it and above every ordinary division, which is
  # the mechanical reason to want the Champion's seat rather than the Deputy's.
  @mana_by_division %{
    initiate: 100,
    bronze: 115,
    silver: 130,
    gold: 150,
    platinum: 170,
    diamond: 190,
    archmage: 215,
    champion: 260
  }

  @deputy_mana 240

  # Books grow with the ladder; 45 slots belong to the Champion and the Deputy
  # alone.
  @grimoire_capacity_by_division %{
    initiate: 15,
    bronze: 15,
    silver: 20,
    gold: 25,
    platinum: 30,
    diamond: 35,
    archmage: 40,
    champion: 45
  }

  # Regen is a share of the pool so a wider pool also refills faster, with a
  # floor that keeps the smallest pool from stalling.
  @regen_share 10
  @min_regen 8

  # Player-facing names and seals, kept beside the divisions themselves so a new
  # division cannot be added without one.
  @labels %{
    initiate: "Посвящённый",
    bronze: "Бронза",
    silver: "Серебро",
    gold: "Золото",
    platinum: "Платина",
    diamond: "Алмаз",
    archmage: "Архимаг",
    champion: "Чемпион"
  }

  @glyphs %{
    initiate: "◇",
    bronze: "◆",
    silver: "✦",
    gold: "✺",
    platinum: "✧",
    diamond: "◈",
    archmage: "✹",
    champion: "✵"
  }

  @doc "Every division, weakest first."
  def divisions, do: @divisions

  @doc "The player-facing name of a division."
  def label(key), do: Map.get(@labels, key, @labels.initiate)

  @doc "The seal a division is shown with."
  def glyph(key), do: Map.get(@glyphs, key, @glyphs.initiate)

  @doc "Every division key, weakest first."
  def keys, do: @keys

  @doc "The division a rating alone would place a profile in."
  def division_for_rating(rating) when is_integer(rating) do
    @divisions
    |> Enum.filter(&(rating >= &1.floor))
    |> List.last()
    |> Kernel.||(hd(@divisions))
    |> Map.fetch!(:key)
  end

  @doc "Where a division sits on the ladder, weakest first from zero."
  def ordinal(key) when key in @keys, do: Enum.find_index(@keys, &(&1 == key))
  def ordinal(_key), do: 0

  @doc "True when `held` is at least as high as `required`."
  def at_least?(held, required), do: ordinal(held) >= ordinal(required)

  @doc "The rating that promotes into a division."
  def floor_for(key) do
    @divisions |> Enum.find(&(&1.key == key)) |> Kernel.||(hd(@divisions)) |> Map.fetch!(:floor)
  end

  @doc """
  The division a spell of this craft power demands of its caster.

  Power is earned by the formula alone; this is where that earned number turns
  into the rank that may wield it.
  """
  def division_for_power(power) when is_integer(power) do
    @power_gates
    |> Enum.filter(fn {_key, gate} -> power >= gate end)
    |> List.last()
    |> case do
      {key, _gate} -> key
      nil -> hd(@keys)
    end
  end

  def division_for_power(_power), do: hd(@keys)

  @doc "The craft power a division opens."
  def power_gate(key) do
    Keyword.get(@power_gates, key, 0)
  end

  @doc "The strongest power a spell may reach at all."
  def max_power, do: 60

  @doc """
  The power band a division may forge within.

  The caster's rank is the limit of the art they have mastered: a spell's power
  must stay inside this band no matter how the incantation is written. Word
  count is deliberately absent — coherence and intent decide where in the band a
  spell lands, the band itself decides how far that can go.
  """
  def power_band(division) when division in @keys do
    ordinal_division = ordinal(division)
    minimum = Keyword.get(@power_gates, division, 0)

    maximum =
      if ordinal_division < length(@keys) - 1 do
        power_gate(Enum.at(@keys, ordinal_division + 1)) - 1
      else
        max_power()
      end

    {minimum, maximum}
  end

  def power_band(_division), do: power_band(hd(@keys))

  @doc """
  The division a world character's level stands in for.

  World characters have no arena division; their level is the honest
  approximation of the same ladder for the spell compiler's guardrails.
  """
  def division_for_level(level) when is_integer(level) do
    cond do
      level >= 80 -> :champion
      level >= 60 -> :archmage
      level >= 50 -> :diamond
      level >= 40 -> :platinum
      level >= 30 -> :gold
      level >= 20 -> :silver
      level >= 10 -> :bronze
      true -> :initiate
    end
  end

  def division_for_level(_level), do: :initiate

  @doc """
  The grimoire slot count a division may keep.
  """
  def grimoire_capacity(division),
    do: Map.get(@grimoire_capacity_by_division, division, 15)

  @doc "The Deputy's book matches the Champion's."
  def deputy_grimoire_capacity, do: 45

  @doc """
  The mana pool a division carries.

  The Champion's division is the Champion's seat, so it carries the seat's pool.
  """
  def max_mana_for(division), do: Map.get(@mana_by_division, division, @mana_by_division.initiate)

  @doc "The Deputy's pool: above every ordinary division, below the Champion's."
  def deputy_mana, do: @deputy_mana

  @doc "How much of a pool returns at the start of a turn."
  def regen_for(max_mana) when is_integer(max_mana),
    do: max(div(max_mana, @regen_share), @min_regen)

  @doc """
  Settles one result into a new rating and held division.

  `expected` is the Elo expectation against the opponent, `score` the realised
  result (1.0 win, 0.5 draw, 0.0 loss).

  Pass `placement?: true` while a profile is still playing its placement
  matches: the ladder moves faster because it knows less, so a returning player
  reaches where they belong in a handful of games rather than a hundred.
  """
  def settle(rating, held, expected, score, opts \\ [])

  def settle(rating, held, expected, score, opts)
      when is_integer(rating) and is_float(expected) and is_float(score) do
    held = if held in @keys, do: held, else: division_for_rating(rating)
    swing = k_factor(held, score) * (score - expected)

    swing =
      if Keyword.get(opts, :placement?, false), do: swing * @placement_multiplier, else: swing

    new_rating = max(rating + round(swing), 0)

    %{rating: new_rating, division: resolve_division(new_rating, held)}
  end

  # Winning uses the division's win rate, anything else its loss rate, so the
  # early ladder can be generous about defeats without also inflating wins.
  defp k_factor(held, score) do
    division = Enum.find(@divisions, &(&1.key == held)) || hd(@divisions)
    if score > 0.5, do: division.win, else: division.loss
  end

  # Promotion is immediate on reaching a floor; demotion waits until the rating
  # is a clear margin below the held division.
  defp resolve_division(rating, held) do
    earned = division_for_rating(rating)

    cond do
      ordinal(earned) > ordinal(held) -> earned
      rating < floor_for(held) - @demotion_buffer -> earned
      true -> held
    end
  end
end
