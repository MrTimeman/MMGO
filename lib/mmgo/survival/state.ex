defmodule MMGO.Survival.State do
  @moduledoc """
  Typed, metadata-backed survival consequences for a character.

  Character metadata is already durable and account-owned, so this state can
  evolve without introducing an ungenerated database migration. It records
  non-lethal starvation consequences after a journey and clears them when the
  character receives food again.
  """
  alias MMGO.Accounts.Character

  @metadata_key "survival_state"

  defstruct starvation_days: 0,
            health_drain: 0,
            movement_penalty_days: 0,
            recovered?: false

  @type t :: %__MODULE__{
          starvation_days: non_neg_integer(),
          health_drain: non_neg_integer(),
          movement_penalty_days: non_neg_integer(),
          recovered?: boolean()
        }

  @doc """
  Loads the durable typed state from a character without trusting metadata
  values to have the expected type.
  """
  def load(%Character{metadata: metadata}) do
    metadata
    |> Map.get(@metadata_key, %{})
    |> from_metadata()
  end

  @doc """
  Persists starvation after a completed journey. The first foodless day is a
  movement delay; every subsequent consecutive foodless day adds one unit of
  non-lethal health drain.
  """
  def apply_journey_outcome(repo, %Character{} = character, attrs) when is_map(attrs) do
    shortage_days = non_negative_value(attrs, "food_shortage_days")
    movement_penalty_days = non_negative_value(attrs, "movement_penalty_days")

    if shortage_days == 0 do
      {:ok, character}
    else
      state = load(character)
      previous_drain_days = max(state.starvation_days - 1, 0)
      updated_starvation_days = state.starvation_days + shortage_days
      updated_drain_days = max(updated_starvation_days - 1, 0)

      updated_state = %__MODULE__{
        starvation_days: updated_starvation_days,
        health_drain: state.health_drain + updated_drain_days - previous_drain_days,
        movement_penalty_days: max(state.movement_penalty_days, movement_penalty_days),
        recovered?: false
      }

      persist(repo, character, updated_state)
    end
  end

  @doc """
  Clears recoverable hunger consequences when food reaches the character.
  Returns the supplied character unchanged when there is nothing to recover.
  """
  def recover_after_food(repo, %Character{} = character) do
    state = load(character)

    if state.starvation_days > 0 or state.health_drain > 0 do
      persist(repo, character, %__MODULE__{recovered?: true})
    else
      {:ok, character}
    end
  end

  @doc """
  Converts the state into a browser-safe survival summary.
  """
  def summary(%__MODULE__{} = state) do
    %{
      starvation_days: state.starvation_days,
      health_drain: state.health_drain,
      movement_penalty_days: state.movement_penalty_days,
      recovered?: state.recovered?,
      starving?: state.starvation_days > 0
    }
  end

  defp persist(repo, %Character{} = character, %__MODULE__{} = state) do
    metadata = Map.put(character.metadata || %{}, @metadata_key, to_metadata(state))

    character
    |> Character.changeset(%{metadata: metadata})
    |> repo.update()
  end

  defp from_metadata(metadata) when is_map(metadata) do
    %__MODULE__{
      starvation_days: non_negative_value(metadata, "starvation_days"),
      health_drain: non_negative_value(metadata, "health_drain"),
      movement_penalty_days: non_negative_value(metadata, "movement_penalty_days"),
      recovered?: Map.get(metadata, "recovered?", false) == true
    }
  end

  defp from_metadata(_metadata), do: %__MODULE__{}

  defp to_metadata(%__MODULE__{} = state) do
    %{
      "starvation_days" => state.starvation_days,
      "health_drain" => state.health_drain,
      "movement_penalty_days" => state.movement_penalty_days,
      "recovered?" => state.recovered?
    }
  end

  defp non_negative_value(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end
end
