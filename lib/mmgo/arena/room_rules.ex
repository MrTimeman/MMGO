defmodule MMGO.Arena.RoomRules do
  @moduledoc """
  The special rules a friendly room may be played under.

  A custom room is where the arena's constraints can be lifted deliberately: no
  grimoire, no mana, or a ceiling on what rank of spell may be brought. Ranked
  play never sees any of this — the rules are read only from a `:custom` match,
  and the resolved set is copied into combat metadata when the fight starts so
  the engine never has to reach back for a host-supplied map.

  Everything here is normalised from untrusted host input: an unrecognised rule
  or value collapses to the ordinary arena, never to something more permissive
  than the host could have chosen deliberately.
  """

  alias MMGO.Arena.Ladder

  @metadata_key "arena_rules"

  # Which book a caster fights out of.
  #   prepared — the ordinary rule: only spells bound into the active grimoire
  #   free     — cast anything you own, the book set aside
  @grimoire_rules ~w(prepared free)

  # What the mana economy does in this room.
  #   standard  — the ordinary pool, regen and costs
  #   unlimited — no depletion at all, which is also the no-mana mode
  @mana_rules ~w(standard unlimited)

  # Whether a caster is held to their own rank.
  #   own  — as in ranked play and the world: your division gates your spells
  #   free — no restraint at all, which is what an ordinary friendly room is for
  # A `rank_cap` narrows either of these to a ceiling everyone shares.
  @rank_rules ~w(own free)

  @defaults %{
    "grimoire" => "prepared",
    "mana" => "standard",
    "rank" => "own",
    "rank_cap" => nil
  }

  @doc "The rules an ordinary arena fight is played under."
  def defaults, do: @defaults

  @doc "The key these rules live under in combat metadata."
  def metadata_key, do: @metadata_key

  @doc """
  Normalises a host-supplied rule set.

  Anything unrecognised falls back to the ordinary arena rule rather than being
  rejected, so a stale client cannot lock a host out of making a room.
  """
  def normalize(settings) when is_map(settings) do
    settings = Map.new(settings, fn {key, value} -> {to_string(key), value} end)

    %{
      "grimoire" => one_of(settings["grimoire"], @grimoire_rules, "prepared"),
      "mana" => one_of(settings["mana"], @mana_rules, "standard"),
      "rank" => one_of(settings["rank"], @rank_rules, "own"),
      "rank_cap" => normalize_rank_cap(settings["rank_cap"])
    }
  end

  def normalize(_settings), do: @defaults

  @doc """
  The rules in force for a combat.

  Only what the server wrote into the combat's metadata counts; a fight with
  nothing recorded is an ordinary one.
  """
  def for_combat(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, @metadata_key) do
      rules when is_map(rules) -> Map.merge(@defaults, normalize(rules))
      _absent -> @defaults
    end
  end

  def for_combat(_combat), do: @defaults

  @doc "Whether this room lets a caster reach past their grimoire."
  def free_grimoire?(combat), do: for_combat(combat)["grimoire"] == "free"

  @doc "Whether mana never depletes in this room."
  def unlimited_mana?(combat), do: for_combat(combat)["mana"] == "unlimited"

  @doc "The highest spell rank this room admits, or nil when it admits any."
  def rank_cap(combat), do: for_combat(combat)["rank_cap"]

  @doc "Whether this room lets a caster reach past their own rank."
  def free_rank?(combat), do: for_combat(combat)["rank"] == "free"

  @doc "A one-line summary of what makes this room unusual, or nil when nothing does."
  def summary(rules) when is_map(rules) do
    rules = Map.merge(@defaults, rules)

    [
      rules["grimoire"] == "free" && "без гримуара",
      rules["mana"] == "unlimited" && "без маны",
      rules["rank"] == "free" && "без ограничения ранга",
      rules["rank_cap"] && "ранг не выше «#{Ladder.label(normalize_rank_cap(rules["rank_cap"]))}»"
    ]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      notes -> Enum.join(notes, " · ")
    end
  end

  defp one_of(value, allowed, fallback) when is_binary(value) do
    if value in allowed, do: value, else: fallback
  end

  defp one_of(value, allowed, fallback) when is_atom(value) and not is_nil(value) do
    one_of(Atom.to_string(value), allowed, fallback)
  end

  defp one_of(_value, _allowed, fallback), do: fallback

  # A cap is a division, and an unrecognised one is no cap rather than a
  # silently harsher or looser one.
  defp normalize_rank_cap(value) when is_atom(value) and not is_nil(value) do
    if value in Ladder.keys(), do: value, else: nil
  end

  defp normalize_rank_cap(value) when is_binary(value) do
    Enum.find(Ladder.keys(), &(Atom.to_string(&1) == value))
  end

  defp normalize_rank_cap(_value), do: nil
end
