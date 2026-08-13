defmodule MMGO.Combat.ArenaEvents do
  @moduledoc """
  Server-owned environmental events for Arena combats.

  Arena matches persist only a policy, an allowlisted deck of event codes, and
  a seed. The executable event definition is always resolved here, so a room
  host can never submit an arbitrary effect map to the combat engine.
  """

  @event_duration_turns 2

  @events [
    %{
      "code" => "emberfall",
      "name" => "Искропад",
      "description" => "Раскалённые искры обжигают обе команды и наполняют арену огнём.",
      "accent" => "amber",
      "tags" => ["fire", "embers", "burning"],
      "effect" => %{"kind" => "side_hp_delta", "amount" => -4}
    },
    %{
      "code" => "healing_rain",
      "name" => "Целительный ливень",
      "description" => "Вода возвращает силы обеим сторонам и оставляет всё промокшим.",
      "accent" => "cyan",
      "tags" => ["water", "rain", "wet"],
      "effect" => %{"kind" => "side_hp_delta", "amount" => 3}
    },
    %{
      "code" => "verdant_upheaval",
      "name" => "Зелёный разлом",
      "description" => "Корни и камень поднимаются из пола, укрывая каждого бойца.",
      "accent" => "emerald",
      "tags" => ["earth", "life", "overgrown"],
      "effect" => %{
        "kind" => "participant_state",
        "state" => "shielded",
        "intensity" => 5,
        "duration_turns" => 1
      }
    },
    %{
      "code" => "grave_eclipse",
      "name" => "Мёртвое затмение",
      "description" => "Холодная тень утяжеляет каждое заклинание и истощает всех магов.",
      "accent" => "violet",
      "tags" => ["death", "eclipse", "necrotic"],
      "effect" => %{"kind" => "mana_delta", "amount" => -12}
    },
    %{
      "code" => "wind_shear",
      "name" => "Режущий шквал",
      "description" => "Пыльный вихрь мешает прицелиться, но одинаково слепит обе стороны.",
      "accent" => "sky",
      "tags" => ["air", "storm", "gale"],
      "effect" => %{
        "kind" => "participant_state",
        "state" => "blinded",
        "intensity" => 8,
        "duration_turns" => 1
      }
    },
    %{
      "code" => "chaos_surge",
      "name" => "Всплеск хаоса",
      "description" => "Нестабильная мана усиливает следующее заклинание каждого участника.",
      "accent" => "fuchsia",
      "tags" => ["chaos", "unstable", "wild-magic"],
      "effect" => %{
        "kind" => "participant_state",
        "state" => "empowered",
        "intensity" => 2,
        "duration_turns" => 1
      }
    },
    %{
      "code" => "order_convergence",
      "name" => "Схождение порядка",
      "description" => "Кристаллическая решётка выстраивает вокруг каждого мага краткий оберег.",
      "accent" => "indigo",
      "tags" => ["order", "crystal", "warded"],
      "effect" => %{
        "kind" => "participant_state",
        "state" => "shielded",
        "intensity" => 8,
        "duration_turns" => 1
      }
    }
  ]

  @events_by_code Map.new(@events, &{&1["code"], &1})
  @event_codes Enum.map(@events, & &1["code"])
  @policies ~w(random fixed none)

  @doc "Returns the complete allowlist accepted by Arena room settings."
  def event_codes, do: @event_codes

  @doc "Returns presentation-safe definitions without exposing executable effects."
  def catalog do
    Enum.map(@events, &Map.drop(&1, ["effect"]))
  end

  @doc "Builds the compact, persisted schedule snapshot for an Arena combat."
  def schedule(policy, requested_codes, seed) do
    with {:ok, policy} <- normalize_policy(policy),
         {:ok, seed} <- normalize_seed(seed),
         {:ok, codes} <- normalize_codes(policy, requested_codes) do
      {:ok, %{"policy" => policy, "codes" => codes, "seed" => seed}}
    end
  end

  @doc "Resolves the active server-owned event for a combat turn."
  def event_for_turn(schedule, turn_number)

  def event_for_turn(schedule, turn_number) when is_map(schedule) and is_integer(turn_number) do
    policy = schedule["policy"] || schedule[:policy]
    codes = schedule["codes"] || schedule[:codes] || []
    seed = schedule["seed"] || schedule[:seed]

    with true <- turn_number > 0,
         true <- policy in ["random", "fixed"],
         true <- is_integer(seed) and seed > 0,
         true <- is_list(codes) and codes != [],
         true <- Enum.all?(codes, &Map.has_key?(@events_by_code, &1)) do
      event_index = div(turn_number - 1, @event_duration_turns)
      cycle = div(event_index, length(codes))
      position = rem(event_index, length(codes))

      ordered_codes =
        case policy do
          "random" -> deterministic_order(codes, seed, cycle)
          "fixed" -> codes
        end

      code = Enum.at(ordered_codes, position)
      turns_elapsed = rem(turn_number - 1, @event_duration_turns)

      @events_by_code
      |> Map.fetch!(code)
      |> Map.merge(%{
        "duration_turns" => @event_duration_turns,
        "remaining_turns" => @event_duration_turns - turns_elapsed,
        "cycle" => cycle
      })
    else
      _invalid_or_disabled -> nil
    end
  end

  def event_for_turn(_schedule, _turn_number), do: nil

  @doc "Returns the tags currently available to spell interaction rules."
  def active_tags(schedule, turn_number) do
    case event_for_turn(schedule, turn_number) do
      %{"tags" => tags} -> tags
      _none -> []
    end
  end

  defp normalize_policy(policy) when is_atom(policy), do: normalize_policy(Atom.to_string(policy))

  defp normalize_policy(policy) when policy in @policies, do: {:ok, policy}
  defp normalize_policy(_policy), do: {:error, :invalid_event_policy}

  defp normalize_seed(seed) when is_integer(seed) and seed > 0, do: {:ok, seed}
  defp normalize_seed(_seed), do: {:error, :invalid_seed}

  defp normalize_codes("none", _requested_codes), do: {:ok, []}

  defp normalize_codes(policy, requested_codes) when policy in ["random", "fixed"] do
    codes =
      requested_codes
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    codes = if codes == [], do: @event_codes, else: codes

    if Enum.all?(codes, &Map.has_key?(@events_by_code, &1)) do
      {:ok, codes}
    else
      {:error, :invalid_event_code}
    end
  end

  defp deterministic_order(codes, seed, cycle) do
    Enum.sort_by(codes, fn code ->
      {:erlang.phash2({seed, cycle, code}), code}
    end)
  end
end
