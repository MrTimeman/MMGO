defmodule MMGO.Combat.Resolution do
  @moduledoc """
  Shared post-resolution hook for combats.

  `MMGO.Combat` itself has no awareness of what a combat's `kind` means to
  the rest of the game (a wagered duel, a dungeon encounter, ...). Any code
  path that resolves a combat turn (Telegram commands, LiveViews, future
  API/game surfaces) should call `finalize/1` right after
  `MMGO.Combat.resolve_turn/1` so that finishing a combat always has the
  correct side effects, no matter which surface triggered the resolution.

  This module is intentionally the *only* place that knows the mapping from
  combat `kind` to the domain action that must run when it finishes
  (`MMGO.PVP.settle_duel_from_combat/1` for duels, `MMGO.Dungeons.sync_encounter_combat/1`
  for dungeon encounters). It lives under `MMGO.Combat` but depends on
  `MMGO.PVP` and `MMGO.Dungeons`, both of which already depend on
  `MMGO.Combat` — keeping the dependency pointed one way avoids a compile-time
  cycle between those contexts.
  """

  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Dungeons
  alias MMGO.PVP

  @doc """
  Runs the settlement/sync side effect for a combat, if any is required.

  Safe to call for any combat regardless of `status`/`kind` — it is a no-op
  unless the combat is `:finished` and belongs to a domain (duel, dungeon
  encounter) that has one. Also safe to call more than once for the same
  finished combat: the underlying settlement/sync functions re-check their
  own state (duel/encounter status) inside a locked transaction and return
  an error instead of double-settling, so a caller can call `finalize/1`
  defensively without risking a double payout or double loot drop.
  """
  def finalize(%CombatSchema{status: :finished, kind: :duel} = combat) do
    if duel_id(combat) do
      PVP.settle_duel_from_combat(combat)
    else
      {:ok, :no_op}
    end
  end

  def finalize(%CombatSchema{status: :finished, kind: :dungeon_encounter} = combat) do
    Dungeons.sync_encounter_combat(combat)
  end

  def finalize(%CombatSchema{} = _combat), do: {:ok, :no_op}

  defp duel_id(%CombatSchema{metadata: metadata}) do
    metadata["duel_id"] || metadata[:duel_id]
  end
end
