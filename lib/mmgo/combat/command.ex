defmodule MMGO.Combat.Command do
  @moduledoc """
  Turns a line the player typed into the action the engine executes.

  The duel is fought by writing, not by filling in a form. One line is one
  decision: the verb chooses the action, and whatever follows names the thing it
  acts on. Everything the parser resolves — a spell, an item, a guard, a target
  — is looked up in the state the server already holds, so a typed name is only
  ever a way of pointing at something the player genuinely has.

  Ambiguity is refused rather than guessed. Writing `ign` when the book holds
  both `Ignis Prima` and `Ignis Nova` is a question, not a command, and the
  parser says so instead of picking one and spending the turn.
  """

  alias MMGO.Combat.ActionSnapshot

  # The verbs, and every spelling of them the player might reasonably reach for.
  # Russian first because the game is Russian; the Latin and English forms are
  # here because the formulas are Latin and muscle memory is English.
  @verbs %{
    "удар" => :manifestation_strike,
    "ударить" => :manifestation_strike,
    "бей" => :manifestation_strike,
    "strike" => :manifestation_strike,
    "парировать" => :parry,
    "парирую" => :parry,
    "парри" => :parry,
    "parry" => :parry,
    "блок" => :block,
    "блокировать" => :block,
    "защита" => :block,
    "block" => :block,
    "ждать" => :wait,
    "жду" => :wait,
    "выждать" => :wait,
    "wait" => :wait,
    "предмет" => :use_item,
    "использовать" => :use_item,
    "use" => :use_item,
    "бежать" => :flee,
    "бегу" => :flee,
    "flee" => :flee,
    "run" => :flee
  }

  @target_markers ~w(по в на -> → at)

  @doc "Every verb the parser knows, for the reference sheet."
  def verbs, do: @verbs

  @doc """
  Parses one line against the combat state the player is looking at.

  Returns `{:ok, attrs}` ready for `MMGO.Play.submit_combat_action/3`, or
  `{:error, reason}` naming what could not be resolved. A refusal never costs
  the turn: the player is told what went wrong and writes again.
  """
  def parse(line, state) when is_binary(line) do
    case normalize(line) do
      "" -> {:error, :empty_command}
      normalized -> parse_words(String.split(normalized, " ", trim: true), state)
    end
  end

  def parse(_line, _state), do: {:error, :empty_command}

  defp parse_words([head | rest], state) do
    case Map.fetch(@verbs, head) do
      {:ok, verb} -> build(verb, rest, state)
      # No verb means the line is a formula: casting is the default act of a
      # duel, so it needs no word spent announcing itself.
      :error -> build(:cast_spell, [head | rest], state)
    end
  end

  defp parse_words([], _state), do: {:error, :empty_command}

  defp build(:wait, _rest, _state), do: {:ok, %{"action_type" => "wait"}}

  defp build(:flee, _rest, state) do
    if Map.get(state, :flee_available?, false) do
      {:ok, %{"action_type" => "flee"}}
    else
      {:error, :flee_unavailable}
    end
  end

  defp build(:cast_spell, words, state) do
    {name_words, target} = split_target(words)

    with {:ok, spell} <- resolve_spell(name_words, state) do
      {:ok,
       %{"action_type" => "cast_spell", "spell_id" => spell.id}
       |> put_incantation(spell)
       |> put_target(target, state)}
    end
  end

  defp build(:manifestation_strike, words, state) do
    {_ignored, target} = split_target(words)

    if summoned_weapon?(state) do
      {:ok, put_target(%{"action_type" => "manifestation_strike"}, target, state)}
    else
      {:error, :no_summoned_weapon}
    end
  end

  defp build(mode, words, state) when mode in [:parry, :block] do
    with {:ok, source} <- resolve_guard(mode, words, state) do
      {:ok, %{"action_type" => to_string(mode), "guard_source" => source}}
    end
  end

  defp build(:use_item, words, state) do
    {name_words, target} = split_target(words)

    with {:ok, item, action_key} <- resolve_item(name_words, state) do
      {:ok,
       %{
         "action_type" => "use_item",
         "inventory_item_id" => item.id,
         "tool_action" => action_key
       }
       |> put_target(target, state)}
    end
  end

  # ------------------------------------------------------------------
  # Resolving what the words point at
  # ------------------------------------------------------------------

  defp resolve_spell([], _state), do: {:error, :empty_command}

  defp resolve_spell(words, state) do
    written = Enum.join(words, " ")
    spells = Map.get(state, :prepared_spells, [])

    spells
    |> Enum.filter(&spell_matches?(&1, written))
    |> case do
      [spell] ->
        {:ok, spell}

      [] ->
        {:error, {:unknown_spell, written}}

      several ->
        # An exact hit beats every prefix that also matched, so a book holding
        # both `Ignis` and `Ignis Nova` can still cast the shorter one.
        case Enum.filter(several, &spell_exact?(&1, written)) do
          [spell] -> {:ok, spell}
          _still_ambiguous -> {:error, {:ambiguous_spell, written, Enum.map(several, & &1.name)}}
        end
    end
  end

  defp spell_matches?(spell, written) do
    spell_exact?(spell, written) or
      String.starts_with?(normalize(spell.formula || ""), written) or
      String.starts_with?(normalize(spell.name || ""), written)
  end

  defp spell_exact?(spell, written) do
    normalize(spell.formula || "") == written or normalize(spell.name || "") == written
  end

  # An unqualified guard takes the strongest thing available, because that is
  # what a player reaching for a shield in a hurry means.
  defp resolve_guard(mode, words, state) do
    available = guard_sources(mode, state)
    {name_words, _target} = split_target(words)
    written = Enum.join(name_words, " ")

    cond do
      available == [] ->
        {:error, {:no_guard, mode}}

      written == "" ->
        {:ok, hd(available)}

      true ->
        available
        |> Enum.filter(&String.starts_with?(guard_alias(&1), written))
        |> case do
          [source | _rest] -> {:ok, source}
          [] -> {:error, {:unknown_guard, written}}
        end
    end
  end

  defp guard_sources(mode, state) do
    ActionSnapshot.guard_sources(mode, Map.get(state, :participant),
      holding_item?: Map.get(state, :items, []) != []
    )
  end

  # What a player would type to mean each guard, in the language of the screen.
  defp guard_alias("summoned_shield"), do: "щит"
  defp guard_alias("summoned_creature"), do: "союзник"
  defp guard_alias("summoned_weapon"), do: "оружие"
  defp guard_alias("item"), do: "предмет"
  defp guard_alias("bare"), do: "руки"
  defp guard_alias(source), do: normalize(source)

  defp resolve_item([], _state), do: {:error, :item_not_named}

  defp resolve_item(words, state) do
    written = Enum.join(words, " ")
    items = Map.get(state, :items, [])

    items
    |> Enum.filter(&String.starts_with?(normalize(&1.name || ""), written))
    |> case do
      [item] -> first_item_action(item)
      [] -> {:error, {:unknown_item, written}}
      several -> {:error, {:ambiguous_item, written, Enum.map(several, & &1.name)}}
    end
  end

  defp first_item_action(item) do
    case List.wrap(Map.get(item, :actions)) do
      [action | _rest] -> {:ok, item, action.key}
      [] -> {:error, {:item_has_no_action, item.name}}
    end
  end

  # ------------------------------------------------------------------
  # Targets
  # ------------------------------------------------------------------

  # `по имени`, `-> имени`, and friends split the line into what is being done
  # and who it is being done to. Without a marker the whole tail is the name of
  # the thing being acted on, and the target is left to the default.
  defp split_target(words) do
    case Enum.find_index(words, &(&1 in @target_markers)) do
      nil ->
        {words, nil}

      index ->
        {Enum.take(words, index), words |> Enum.drop(index + 1) |> Enum.join(" ")}
    end
  end

  defp put_target(attrs, nil, state), do: Map.put(attrs, "target_side", opposing_side(state))

  defp put_target(attrs, written, state) do
    state
    |> Map.get(:combat)
    |> case do
      %{participants: participants} when is_list(participants) -> participants
      _no_combat -> []
    end
    |> Enum.filter(&(&1.status == :ready))
    |> Enum.filter(&String.starts_with?(normalize(&1.display_name || ""), written))
    |> case do
      [participant | _rest] ->
        attrs
        |> Map.put("target_participant_id", participant.id)
        |> Map.put("target_side", participant.side)

      [] ->
        Map.put(attrs, "target_side", opposing_side(state))
    end
  end

  defp opposing_side(state) do
    own = state |> Map.get(:participant) |> then(&(&1 && &1.side))

    state
    |> Map.get(:combat)
    |> case do
      %{participants: participants} when is_list(participants) -> participants
      _no_combat -> []
    end
    |> Enum.map(& &1.side)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == own))
    |> List.first()
    |> Kernel.||(own)
  end

  # The formula is carried for the engine's record of what was spoken; the spell
  # itself is identified by id, never by the text.
  defp put_incantation(attrs, spell), do: Map.put(attrs, "incantation", spell.formula || "")

  defp summoned_weapon?(state) do
    state
    |> Map.get(:participant)
    |> case do
      %{active_states: active_states} ->
        active_states
        |> List.wrap()
        |> Enum.any?(&(Map.get(&1, "state") == "summoned_weapon"))

      _no_participant ->
        false
    end
  end

  defp normalize(text) do
    text
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
  end
end
