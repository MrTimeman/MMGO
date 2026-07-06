// Aperture-7 hex hierarchy math (H3-style: "every hexagon contains 7
// hexagons") layered on top of the fine (level-2) pointy-top axial hex grid
// defined in ./grid.js (x = size*sqrt(3)*(q + r/2), y = size*1.5*r).
//
// This is a straight port of lib/mmgo/world_map/hierarchy.ex — see that
// module's @moduledoc for the full derivation. Summary:
//
// Three levels:
//   - level 2 ("fine"): the grid actually rendered, axial {q, r}.
//   - level 1: groups of 7 fine hexes, indexed {i, j} in a coarse lattice.
//   - level 0: groups of 7 level-1 hexes (49 fine hexes), indexed {m, n},
//     built by applying the same level-1 construction to level-1 indices.
//
// The level-1 sublattice is spanned by A = (2, 1) and B = (-1, 3)
// (det = 2*3 - 1*(-1) = 7), so index {i, j} maps to fine center
//   center(i, j) = (2*i - j, i + 3*j)
//
// To find the parent of fine hex {q, r}, solve (q, r) = i*A + j*B for real
// i, j:
//   i = (3*q + r) / 7
//   j = (-q + 2*r) / 7
// Naive independent rounding of i and j does NOT respect hex distance and
// can pick the wrong lattice point. Instead we brute-force a small
// neighborhood of integer candidates around floor(i)/floor(j) (a 4x4 block
// covering every floor/ceil combination plus their immediate neighbors),
// map each candidate back to its fine center, and keep whichever is
// nearest to {q, r} in hex distance. This always lands at distance <= 1
// (the hex is either the parent's center or one of its 6 neighbors) for
// this sublattice, verified by property tests on the Elixir side.
//
// Geometry: a level-1 parent hex drawn in pixel space is the fine hex's own
// pointy-top shape scaled by sqrt(7) and rotated by the angle between the
// fine lattice's unit vector (1, 0) and the coarse basis vector A = (2, 1),
// both mapped through the axial-to-pixel transform:
//   ROT_L1 = atan2(1.5, 2.5*sqrt(3)) ~= 0.333473 rad ~= 19.1066 deg
//   SCALE_L1 = sqrt(7)
// Level 0 composes: ROT_L0 = 2 * ROT_L1, SCALE_L0 = 7.

const SQRT3 = Math.sqrt(3)

const A = [2, 1]
const B = [-1, 3]

const AXIAL_DIRECTIONS = [
  [1, 0],
  [1, -1],
  [0, -1],
  [-1, 0],
  [-1, 1],
  [0, 1],
]

function axialToPixel(q, r, size) {
  return {
    x: size * SQRT3 * (q + r / 2),
    y: size * 1.5 * r,
  }
}

function hexDistance(q1, r1, q2, r2) {
  const dq = q1 - q2
  const dr = r1 - r2
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2
}

// Maps a coarse index [i, j] to its fine-lattice center via i*A + j*B.
function latticeCenter(i, j) {
  return [i * A[0] + j * B[0], i * A[1] + j * B[1]]
}

// Given a point [q, r] in the fine (child) lattice, finds the nearest
// coarse-lattice index by brute-force candidate search (see header comment).
function nearestIndex(q, r) {
  const iF = (3 * q + r) / 7
  const jF = (-q + 2 * r) / 7

  const iLo = Math.floor(iF)
  const jLo = Math.floor(jF)

  let best = null
  let bestDist = Infinity

  for (let di = -1; di <= 2; di++) {
    for (let dj = -1; dj <= 2; dj++) {
      const i = iLo + di
      const j = jLo + dj
      const [cq, cr] = latticeCenter(i, j)
      const d = hexDistance(q, r, cq, cr)
      if (d < bestDist) {
        bestDist = d
        best = [i, j]
      }
    }
  }

  return best
}

function neighborsOf(q, r) {
  return AXIAL_DIRECTIONS.map(([dq, dr]) => [q + dq, r + dr])
}

// Angle between the fine lattice's unit vector (1, 0) and the coarse
// lattice's basis vector A = (2, 1), both mapped through the fine-grid
// pixel transform.
function baseRotation() {
  const a = axialToPixel(A[0], A[1], 1.0)
  const u = axialToPixel(1, 0, 1.0)
  return Math.atan2(a.y, a.x) - Math.atan2(u.y, u.x)
}

export const ROT_L1 = baseRotation()
export const ROT_L0 = baseRotation() * 2
export const SCALE_L1 = Math.sqrt(7)
export const SCALE_L0 = 7.0

// Pointy-top hex corners (angles 30 + 60*k degrees from center), rotated by
// `rotation` radians and scaled to `radius`.
function outlineCorners(cx, cy, radius, rotation) {
  const points = []
  for (let k = 0; k < 6; k++) {
    const angle = (Math.PI / 180) * (60 * k - 30) + rotation
    points.push({ x: cx + radius * Math.cos(angle), y: cy + radius * Math.sin(angle) })
  }
  return points
}

// -- level 1 ----------------------------------------------------------------

// Returns the level-1 parent index [i, j] of a fine axial hex (q, r).
export function parentL1(q, r) {
  return nearestIndex(q, r)
}

// Maps a level-1 index [i, j] to its fine axial center {q, r}.
export function centerL1(i, j) {
  const [q, r] = latticeCenter(i, j)
  return { q, r }
}

// Returns the 7 fine hexes belonging to level-1 parent [i, j]: its center
// plus the center's 6 axial neighbors. Each entry is {q, r}.
export function childrenL1(i, j) {
  const [cq, cr] = latticeCenter(i, j)
  const neighbors = neighborsOf(cq, cr)
  return [{ q: cq, r: cr }, ...neighbors.map(([q, r]) => ({ q, r }))]
}

// Returns the 6 pixel corner coordinates {x, y} of the level-1 parent hex
// [i, j]'s outline, for a fine grid with the given hexSize.
export function outlineL1(i, j, hexSize) {
  const { q, r } = centerL1(i, j)
  const { x: cx, y: cy } = axialToPixel(q, r, hexSize)
  return outlineCorners(cx, cy, hexSize * SCALE_L1, ROT_L1)
}

// -- level 0 ------------------------------------------------------------------

// Returns the level-0 parent index [m, n] of a level-1 index [i, j], using
// the identical construction as parentL1 one level up.
export function parentL0(i, j) {
  return nearestIndex(i, j)
}

// Maps a level-0 index [m, n] to its fine axial center {q, r}.
export function centerL0(m, n) {
  const [i, j] = latticeCenter(m, n)
  return centerL1(i, j)
}

// Returns the 7 level-1 indices belonging to level-0 parent [m, n]: its
// center plus the center's 6 neighbors, in the level-1 index lattice. Each
// entry is {i, j}.
export function childrenL0(m, n) {
  const [ci, cj] = latticeCenter(m, n)
  const neighbors = neighborsOf(ci, cj)
  return [{ i: ci, j: cj }, ...neighbors.map(([i, j]) => ({ i, j }))]
}

// Returns all 49 fine hexes descending from level-0 parent [m, n]: the
// union of childrenL1 for each of childrenL0(m, n). Each entry is {q, r}.
export function descendantsL0(m, n) {
  const l1Children = childrenL0(m, n)
  const result = []
  for (const { i, j } of l1Children) {
    result.push(...childrenL1(i, j))
  }
  return result
}

// Returns the 6 pixel corner coordinates {x, y} of the level-0 parent hex
// [m, n]'s outline, for a fine grid with the given hexSize.
export function outlineL0(m, n, hexSize) {
  const { q, r } = centerL0(m, n)
  const { x: cx, y: cy } = axialToPixel(q, r, hexSize)
  return outlineCorners(cx, cy, hexSize * SCALE_L0, ROT_L0)
}

// -- convenience --------------------------------------------------------------

// Returns both ancestor indices of a fine hex (q, r) as
// { l1: {i, j}, l0: {m, n} }.
export function ancestors(q, r) {
  const [i, j] = parentL1(q, r)
  const [m, n] = parentL0(i, j)
  return { l1: { i, j }, l0: { m, n } }
}
