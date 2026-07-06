// Pointy-top axial hex-grid math, shared between the HexMap renderer hook
// and (later) the map editor. Dependency-free on purpose.
//
// Conventions mirror lib/mmgo/world_map.ex:
//   x = size * sqrt(3) * (q + r / 2)
//   y = size * 1.5 * r

const SQRT3 = Math.sqrt(3)

export function axialToPixel(q, r, size) {
  return {
    x: size * SQRT3 * (q + r / 2),
    y: size * 1.5 * r,
  }
}

// Inverse of axialToPixel, with cube rounding to snap to the nearest hex.
export function pixelToAxial(x, y, size) {
  const q = ((SQRT3 / 3) * x - (1 / 3) * y) / size
  const r = ((2 / 3) * y) / size
  return cubeRound(q, r)
}

function cubeRound(q, r) {
  let x = q
  let z = r
  let y = -x - z

  let rx = Math.round(x)
  let ry = Math.round(y)
  let rz = Math.round(z)

  const xDiff = Math.abs(rx - x)
  const yDiff = Math.abs(ry - y)
  const zDiff = Math.abs(rz - z)

  if (xDiff > yDiff && xDiff > zDiff) {
    rx = -ry - rz
  } else if (yDiff > zDiff) {
    ry = -rx - rz
  } else {
    rz = -rx - ry
  }

  return { q: rx, r: rz }
}

// Corner points of a pointy-top hex centered at (cx, cy), as an array of
// [x, y] pairs starting from the top corner, going clockwise.
export function hexPolygonPoints(cx, cy, size) {
  const points = []
  for (let i = 0; i < 6; i++) {
    const angleDeg = 60 * i - 30
    const angleRad = (Math.PI / 180) * angleDeg
    points.push([cx + size * Math.cos(angleRad), cy + size * Math.sin(angleRad)])
  }
  return points
}

const AXIAL_DIRECTIONS = [
  [1, 0],
  [1, -1],
  [0, -1],
  [-1, 0],
  [-1, 1],
  [0, 1],
]

export function axialNeighbors(q, r) {
  return AXIAL_DIRECTIONS.map(([dq, dr]) => ({ q: q + dq, r: r + dr }))
}
