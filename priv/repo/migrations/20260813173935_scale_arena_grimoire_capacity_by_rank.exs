defmodule MMGO.Repo.Migrations.ScaleArenaGrimoireCapacityByRank do
  use Ecto.Migration

  # Arena loadouts grow with the ladder: 15 slots at the foot, and 45 belong to
  # the Champion and the Deputy alone. Books written under the flat 8-slot rule
  # are widened to the band their owner has already earned. From here the
  # application bumps capacity on promotion.
  def up do
    execute """
    UPDATE grimoires
    SET capacity = CASE arena_profiles.division
      WHEN 'initiate'  THEN 15
      WHEN 'bronze'    THEN 15
      WHEN 'silver'    THEN 20
      WHEN 'gold'      THEN 25
      WHEN 'platinum'  THEN 30
      WHEN 'diamond'   THEN 35
      WHEN 'archmage'  THEN 40
      WHEN 'champion'  THEN 45
      ELSE 15
    END,
    updated_at = NOW()
    FROM arena_profiles
    WHERE arena_profiles.character_id = grimoires.owner_character_id
      AND COALESCE(grimoires.metadata->>'arena', '') = 'true'
    """
  end

  def down do
    :ok
  end
end
