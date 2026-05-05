defmodule Mix.Tasks.Ai.Test do
  @moduledoc """
  Smoke-tests the configured AI provider against all prompt surfaces.

  Usage:
      GEMINI_API_KEY=xxx mix ai.test
      GEMINI_API_KEY=xxx mix ai.test spell
      GEMINI_API_KEY=xxx mix ai.test narrate
      GEMINI_API_KEY=xxx mix ai.test orchestrate
      GEMINI_API_KEY=xxx mix ai.test dungeon

      DEEPSEEK_API_KEY=xxx MMGO_AI_PROVIDER=deepseek mix ai.test
      DEEPSEEK_API_KEY=xxx DEEPSEEK_MODEL=deepseek-v4-flash mix ai.test
  """

  use Mix.Task

  @shortdoc "Smoke-test AI provider (spell compile + narration + orchestration + dungeon tick)"

  @sample_character %{
    "name" => "Aelthar",
    "level" => 5,
    "class" => "mage",
    "school_affinities" => ["fire", "arcane"]
  }

  @sample_spell_request %{
    "formula" => "Ignis Serpentis",
    "school" => "fire",
    "name" => "Serpent Flame",
    "targeting" => "enemy",
    "delivery_form" => "beam",
    "intent" => "A twisting fire beam that lingers as burning"
  }

  @sample_states %{
    "impact" => %{"description" => "direct hit damage", "max_intensity" => 30},
    "burning" => %{"description" => "damage over time, fire", "max_intensity" => 10},
    "frozen" => %{"description" => "movement impaired, cold", "max_intensity" => 8},
    "stunned" => %{"description" => "turn skipped", "max_intensity" => 3},
    "shielded" => %{"description" => "damage reduction", "max_intensity" => 15},
    "revealed" => %{"description" => "dungeon area revealed on map", "max_intensity" => 1},
    "warded" => %{"description" => "dungeon area protected from monsters", "max_intensity" => 5},
    "illuminated" => %{"description" => "dungeon area lit", "max_intensity" => 3},
    "detected" => %{"description" => "nearby monsters revealed", "max_intensity" => 5},
    "transmuted" => %{"description" => "object or terrain changed", "max_intensity" => 1}
  }

  @sample_combat %{
    "id" => "combat-001",
    "dungeon" => "Ashveil Catacombs",
    "floor" => 3
  }

  @sample_turn %{
    "number" => 4,
    "actor" => "Aelthar",
    "spell_used" => "Serpent Flame"
  }

  @sample_events [
    %{
      "type" => "spell_cast",
      "caster" => "Aelthar",
      "target" => "Crypt Wraith",
      "spell" => "Serpent Flame",
      "success" => true
    },
    %{
      "type" => "state_applied",
      "target" => "Crypt Wraith",
      "state" => "burning",
      "intensity" => 6,
      "duration" => 2
    },
    %{
      "type" => "state_applied",
      "target" => "Crypt Wraith",
      "state" => "impact",
      "intensity" => 14
    }
  ]

  @sample_resolutions [
    %{
      "resolution_id" => "r-1",
      "actor" => "Aelthar",
      "spell" => "Serpent Flame",
      "target_side" => "encounter",
      "outcome_windows" => %{
        "success_max" => 78,
        "partial_max" => 91,
        "failure_max" => 100
      },
      "outcomes" => %{
        "success" => %{
          "event_type" => "spell_cast",
          "effect_ranges" => [
            %{"effect_index" => 0, "state" => "impact", "min" => 12, "max" => 16},
            %{"effect_index" => 1, "state" => "burning", "min" => 4, "max" => 7}
          ]
        },
        "partial" => %{
          "event_type" => "partial_spell_cast",
          "effect_ranges" => [
            %{"effect_index" => 0, "state" => "impact", "min" => 6, "max" => 8},
            %{"effect_index" => 1, "state" => "burning", "min" => 2, "max" => 3}
          ]
        },
        "failure" => %{
          "event_type" => "spell_failed",
          "backlash_damage" => 2
        }
      }
    }
  ]

  @sample_dungeon %{
    "id" => "dungeon-001",
    "name" => "Ashveil Catacombs",
    "status" => "active"
  }

  @sample_dungeon_state %{
    "cycle_number" => 5,
    "pressure_level" => 54,
    "anomaly_level" => 41
  }

  @sample_floors [
    %{"id" => "floor-1", "number" => 1, "name" => "Upper Galleries", "resource_saturation" => 35},
    %{"id" => "floor-2", "number" => 2, "name" => "Lower Galleries", "resource_saturation" => 62}
  ]

  @sample_activity_window %{
    "recent_moves" => 9,
    "recent_combats" => 3,
    "recent_extractions" => 1
  }

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    mode = List.first(args) || "all"

    provider = Application.get_env(:mmgo, MMGO.AI)[:default_provider]
    models = Application.get_env(:mmgo, MMGO.AI)[:models]

    IO.puts("\n=== MMGO AI Smoke Test ===")
    IO.puts("Provider : #{inspect(provider)}")

    IO.puts(
      "Models   : spell_compile=#{models[:spell_compile]}  narration=#{models[:turn_narration]}  " <>
        "orchestrator=#{models[:combat_orchestrator]}  dungeon_tick=#{models[:dungeon_tick]}"
    )

    IO.puts("")

    if mode in ["all", "spell"], do: run_spell_compile(provider, models[:spell_compile])
    if mode in ["all", "narrate"], do: run_turn_narration(provider, models[:turn_narration])

    if mode in ["all", "orchestrate"],
      do: run_combat_orchestrator(provider, models[:combat_orchestrator])

    if mode in ["all", "dungeon"], do: run_dungeon_tick(provider, models[:dungeon_tick])
  end

  defp run_spell_compile(provider, model) do
    IO.puts("--- [1/4] Spell Compile ---")
    IO.puts("Input formula : \"#{@sample_spell_request["formula"]}\"")
    IO.puts("Model         : #{model}")

    alias MMGO.AI.Prompts.SpellCompilePrompt

    payload =
      SpellCompilePrompt.build(%{
        character: @sample_character,
        request: @sample_spell_request,
        states: @sample_states
      })

    start = System.monotonic_time(:millisecond)

    case provider.compile_spell(payload, model: model) do
      {:ok, result} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status  : OK (#{ms}ms)")
        IO.puts("Result  :")
        IO.puts(Jason.encode!(result, pretty: true))

      {:error, reason} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status  : ERROR (#{ms}ms)")
        IO.puts("Reason  : #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp run_turn_narration(provider, model) do
    IO.puts("--- [2/4] Turn Narration ---")
    IO.puts("Model : #{model}")

    alias MMGO.AI.Prompts.TurnNarrationPrompt

    payload =
      TurnNarrationPrompt.build(%{
        combat: @sample_combat,
        turn: @sample_turn,
        events: @sample_events
      })

    start = System.monotonic_time(:millisecond)

    case provider.narrate_turn(payload, model: model) do
      {:ok, text} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : OK (#{ms}ms)")
        IO.puts("Result :")
        IO.puts(text)

      {:error, reason} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : ERROR (#{ms}ms)")
        IO.puts("Reason : #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp run_combat_orchestrator(provider, model) do
    IO.puts("--- [3/4] Combat Orchestrator ---")
    IO.puts("Model : #{model}")

    alias MMGO.AI.Prompts.CombatOrchestratorPrompt

    payload =
      CombatOrchestratorPrompt.build(%{
        combat: @sample_combat,
        turn: @sample_turn,
        resolutions: @sample_resolutions
      })

    start = System.monotonic_time(:millisecond)

    case provider.orchestrate_combat(payload, model: model) do
      {:ok, result} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : OK (#{ms}ms)")
        IO.puts("Result :")
        IO.puts(Jason.encode!(result, pretty: true))

      {:error, reason} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : ERROR (#{ms}ms)")
        IO.puts("Reason : #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp run_dungeon_tick(provider, model) do
    IO.puts("--- [4/4] Dungeon Tick ---")
    IO.puts("Model : #{model}")

    alias MMGO.AI.Prompts.DungeonTickPrompt

    payload =
      DungeonTickPrompt.build(%{
        dungeon: @sample_dungeon,
        state: @sample_dungeon_state,
        floors: @sample_floors,
        activity_window: @sample_activity_window
      })

    start = System.monotonic_time(:millisecond)

    case provider.tick_dungeon(payload, model: model) do
      {:ok, result} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : OK (#{ms}ms)")
        IO.puts("Result :")
        IO.puts(Jason.encode!(result, pretty: true))

      {:error, reason} ->
        ms = System.monotonic_time(:millisecond) - start
        IO.puts("Status : ERROR (#{ms}ms)")
        IO.puts("Reason : #{inspect(reason)}")
    end

    IO.puts("")
  end
end
