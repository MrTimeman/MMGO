defmodule MMGO.Spells.SchoolQuirk do
  @moduledoc "Fixed, engine-owned school quirks that the AI may attach to compatible spells."

  @by_school %{
    fire: :escalation,
    water: :environment_shift,
    earth: :persistence,
    air: :tempo,
    life: :vitality,
    death: :harvest,
    chaos: :volatility,
    order: :precision
  }

  def values, do: Map.values(@by_school)
  def for_school(school), do: Map.get(@by_school, school)
  def compatible?(school, quirk), do: for_school(school) == quirk

  def prompt_mapping do
    Map.new(@by_school, fn {school, quirk} -> {to_string(school), to_string(quirk)} end)
  end
end
