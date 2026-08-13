defmodule MMGO.Repo.Migrations.WipeSpellsAndReissueStarters do
  use Ecto.Migration

  @moduledoc """
  Clears every spell forged under the old rules.

  Craft now sets a spell's power and power sets the rank allowed to wield it.
  Spells written before that have numbers that mean something else entirely, so
  they are removed rather than reinterpreted — a spell whose magnitudes were
  never rescaled to a budget would sit alongside the new ones as an heirloom
  nobody could have earned.

  `grimoire_entries.spell_id` cascades and combat action references nilify, so
  the delete is enough on its own. Re-stocking the emptied books is deliberately
  **not** done here: a migration runs against whatever the schema looked like at
  this point in the sequence, while the application structs it would need are
  always at their newest. `MMGO.Arena.restock_empty_arena_books/0` does it from
  the seed instead, which runs after every migration has landed.

  **Take a database backup before deploying this.** It is not reversible: down
  leaves the spells deleted, because there is nothing to restore them from.
  """

  def up do
    execute("DELETE FROM spells")

    # Creation attempts point at spells that no longer exist and describe a
    # compilation contract that no longer holds.
    execute("DELETE FROM spell_creation_attempts")
  end

  def down do
    :ok
  end
end
