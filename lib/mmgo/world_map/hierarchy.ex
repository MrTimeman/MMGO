defmodule MMGO.WorldMap.Hierarchy do
  @moduledoc """
  Aperture-7 hex hierarchy math (H3-style: "every hexagon contains 7
  hexagons") layered on top of the fine (level-2) pointy-top axial hex grid
  defined in `MMGO.WorldMap` (`x = size*sqrt(3)*(q + r/2)`, `y = size*1.5*r`).

  ## The three levels

    * level 2 ("fine") — the grid the game actually renders on, addressed by
      plain axial coordinates `{q, r}` exactly as in `MMGO.WorldMap`.
    * level 1 — groups of 7 fine hexes, addressed by an index `{i, j}` in the
      *coarse* lattice.
    * level 0 — groups of 7 level-1 hexes (49 fine hexes), addressed by an
      index `{m, n}` in the *doubly-coarse* lattice. Level 0 is built by
      applying the exact same level-1 construction to level-1 indices.

  ## The sublattice

  Level-1 centers sit on the sublattice of the fine axial lattice spanned by

      A = (2, 1)
      B = (-1, 3)

  `det([A; B]) = 2*3 - 1*(-1) = 7`, so this sublattice has index 7 in the
  fine lattice — exactly one sublattice point per 7 fine hexes, as required
  for an aperture-7 partition. Every fine hex is assigned to whichever
  sublattice point is nearest to it in hex distance. For this particular
  sublattice that assignment is exact and unambiguous: each parent ends up
  owning precisely its center hex plus that center's 6 axial neighbors (a
  clean 7-hex "flower"), with no ties — see `parent/1` for how the search is
  done and `PROPERTY TESTING` in the test suite for a from-scratch
  verification over a large region.

  An index `{i, j}` maps back to its fine-grid center via

      center(i, j) = (2*i - j, i + 3*j)

  (i.e. `i*A + j*B`).

  ## Finding the parent of a fine hex

  To invert `center/1` for a hex `h = {q, r}` we solve `(q, r) = i*A + j*B`
  for real-valued `i, j`:

      i = (3*q + r) / 7
      j = (-q + 2*r) / 7

  Naively rounding `i` and `j` to the nearest integers independently is
  *not* correct — it does not respect hex distance and can pick the wrong
  lattice point. Instead we use a small, robust, brute-force search: take
  the floor and ceiling of `i` and of `j` (4 combinations), expand that set
  to also include their immediate integer neighbors (a 3x3 block around
  each), map every candidate `{i, j}` back to its fine center via
  `center/1`, and keep whichever candidate's center is at the smallest hex
  distance from `h`. This is guaranteed (and verified by property tests) to
  land at distance <= 1 — i.e. `h` is either the candidate's center itself
  or one of its 6 neighbors.

  This candidate-search approach is a few dozen integer operations — simple,
  exact, and fast enough to call per-hex.

  ## Geometry

  A level-1 parent hex, drawn in pixel space, is the fine hex's own pointy
  -top hexagon shape but scaled by `sqrt(7)` and rotated by the angle
  between the fine lattice's unit vector `(1, 0)` and the coarse lattice's
  basis vector `A = (2, 1)`, both mapped through the standard axial-to-pixel
  transform:

      rotation_l1() = atan2(1.5, 2.5*sqrt(3)) ~= 0.333473 rad ~= 19.1066 deg
      scale_l1()    = sqrt(7)

  Level 0 repeats the same construction one level up, so its rotation and
  scale simply compose:

      rotation_l0() = 2 * rotation_l1() ~= 38.2132 deg
      scale_l0()    = 7.0
  """

  @type axial :: {integer(), integer()}
  @type index :: {integer(), integer()}

  @a {2, 1}
  @b {-1, 3}

  @axial_directions [
    {1, 0},
    {1, -1},
    {0, -1},
    {-1, 0},
    {-1, 1},
    {0, 1}
  ]

  # -- level 1 ------------------------------------------------------------

  @doc """
  Returns the level-1 parent index `{i, j}` of a fine (level-2) axial hex
  `{q, r}`.

  Uses the candidate-search method described in the moduledoc: computes the
  fractional lattice coordinates, expands floor/ceil combinations to a 3x3
  neighborhood of integer candidates, maps each back to its fine center, and
  picks the one nearest to `{q, r}` in hex distance.
  """
  @spec parent(axial()) :: index()
  def parent({q, r}) do
    nearest_index({q, r})
  end

  @doc "Maps a level-1 index `{i, j}` to its fine axial center `{q, r}`."
  @spec center_l1(index()) :: axial()
  def center_l1({i, j}), do: lattice_center({i, j})

  @doc """
  Returns the 7 fine hexes belonging to level-1 parent `{i, j}`: its center
  plus the center's 6 axial neighbors.
  """
  @spec children_l1(index()) :: [axial()]
  def children_l1({i, j}) do
    center = center_l1({i, j})
    [center | neighbors(center)]
  end

  @doc "Rotation (radians) of a level-1 parent hex outline relative to the fine grid."
  @spec rotation_l1() :: float()
  def rotation_l1, do: base_rotation()

  @doc "Scale factor of a level-1 parent hex outline relative to a fine hex."
  @spec scale_l1() :: float()
  def scale_l1, do: :math.sqrt(7)

  @doc """
  Returns the 6 pixel corner coordinates `{x, y}` of the level-1 parent hex
  `{i, j}`'s outline, for a fine grid with the given `hex_size`.
  """
  @spec outline_l1(index(), number()) :: [{float(), float()}]
  def outline_l1({i, j}, hex_size) do
    {cx, cy} = axial_to_pixel(center_l1({i, j}), hex_size)
    outline_corners(cx, cy, hex_size * scale_l1(), rotation_l1())
  end

  # -- level 0 --------------------------------------------------------------

  @doc """
  Returns the level-0 parent index `{m, n}` of a level-1 index `{i, j}`,
  using the identical construction as `parent/1` one level up.
  """
  @spec parent_l0(index()) :: index()
  def parent_l0({i, j}) do
    nearest_index({i, j})
  end

  @doc """
  Maps a level-0 index `{m, n}` to its fine axial center `{q, r}` (the
  center of the level-1 index that is itself the center of `{m, n}`).
  """
  @spec center_l0(index()) :: axial()
  def center_l0({m, n}) do
    {m, n} |> lattice_center() |> center_l1()
  end

  @doc """
  Returns the 7 level-1 indices belonging to level-0 parent `{m, n}`: its
  center plus the center's 6 neighbors, in the level-1 index lattice.
  """
  @spec children_l0(index()) :: [index()]
  def children_l0({m, n}) do
    center = lattice_center({m, n})
    [center | neighbors(center)]
  end

  @doc """
  Returns all 49 fine hexes descending from level-0 parent `{m, n}`: the
  union of `children_l1/1` for each of `children_l0({m, n})`.
  """
  @spec descendants_l0(index()) :: [axial()]
  def descendants_l0({m, n}) do
    {m, n}
    |> children_l0()
    |> Enum.flat_map(&children_l1/1)
  end

  @doc "Rotation (radians) of a level-0 parent hex outline relative to the fine grid."
  @spec rotation_l0() :: float()
  def rotation_l0, do: base_rotation() * 2

  @doc "Scale factor of a level-0 parent hex outline relative to a fine hex."
  @spec scale_l0() :: float()
  def scale_l0, do: 7.0

  @doc """
  Returns the 6 pixel corner coordinates `{x, y}` of the level-0 parent hex
  `{m, n}`'s outline, for a fine grid with the given `hex_size`.
  """
  @spec outline_l0(index(), number()) :: [{float(), float()}]
  def outline_l0({m, n}, hex_size) do
    {cx, cy} = axial_to_pixel(center_l0({m, n}), hex_size)
    outline_corners(cx, cy, hex_size * scale_l0(), rotation_l0())
  end

  # -- convenience ----------------------------------------------------------

  @doc """
  Returns both ancestor indices of a fine hex `{q, r}` as
  `%{l1: {i, j}, l0: {m, n}}`.
  """
  @spec ancestors(axial()) :: %{l1: index(), l0: index()}
  def ancestors({q, r}) do
    l1 = parent({q, r})
    l0 = parent_l0(l1)
    %{l1: l1, l0: l0}
  end

  # -- internals --------------------------------------------------------------

  # Maps a coarse index {i, j} to its fine-lattice center via i*A + j*B.
  defp lattice_center({i, j}) do
    {ax, ay} = @a
    {bx, by} = @b
    {i * ax + j * bx, i * ay + j * by}
  end

  # Given a point {q, r} in the fine (child) lattice, finds the nearest
  # coarse-lattice index by brute-force candidate search, as described in
  # the moduledoc.
  defp nearest_index({q, r}) do
    i_f = (3 * q + r) / 7
    j_f = (-q + 2 * r) / 7

    i_lo = floor(i_f)
    j_lo = floor(j_f)

    candidates =
      for di <- -1..2, dj <- -1..2 do
        {i_lo + di, j_lo + dj}
      end

    candidates
    |> Enum.uniq()
    |> Enum.min_by(fn {i, j} ->
      {cq, cr} = lattice_center({i, j})
      hex_distance({q, r}, {cq, cr})
    end)
  end

  defp neighbors({q, r}) do
    Enum.map(@axial_directions, fn {dq, dr} -> {q + dq, r + dr} end)
  end

  defp hex_distance({q1, r1}, {q2, r2}) do
    dq = q1 - q2
    dr = r1 - r2
    (abs(dq) + abs(dr) + abs(dq + dr)) / 2
  end

  defp axial_to_pixel({q, r}, size) do
    x = size * :math.sqrt(3) * (q + r / 2)
    y = size * 1.5 * r
    {x, y}
  end

  # Angle between the fine lattice's unit vector (1, 0) and the coarse
  # lattice's basis vector A = (2, 1), both mapped through the fine-grid
  # pixel transform. See moduledoc "Geometry" section for the derivation.
  defp base_rotation do
    {ax, ay} = axial_to_pixel(@a, 1.0)
    {ux, uy} = axial_to_pixel({1, 0}, 1.0)
    :math.atan2(ay, ax) - :math.atan2(uy, ux)
  end

  # Pointy-top hex corners (angles 30 + 60*k degrees from center), rotated
  # by `rotation` radians and scaled to `radius`.
  defp outline_corners(cx, cy, radius, rotation) do
    for k <- 0..5 do
      angle = :math.pi() / 180 * (60 * k - 30) + rotation
      {cx + radius * :math.cos(angle), cy + radius * :math.sin(angle)}
    end
  end
end
