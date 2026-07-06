import { axialToPixel, pixelToAxial, hexPolygonPoints, axialNeighbors } from "../hex/grid"
import { parentL1, parentL0, childrenL1, descendantsL0, outlineL1 } from "../hex/hierarchy"

const WORLD_MAP_URL = "/maps/world.json"
const SPRITE_MANIFEST_URL = "/sprites/manifest.json"

const MIN_SCALE = 0.08
const MAX_SCALE = 2.5

const LOD_SPRITE = 0.6
const LOD_GRID = 0.35

const FALLBACK_TERRAIN_COLOR = "#3a3a3a"

const PUSH_DEBOUNCE_MS = 300

// Axial distance between two hexes, used for brush footprints.
function axialDistance(a, b) {
  return (Math.abs(a.q - b.q) + Math.abs(a.q + a.r - b.q - b.r) + Math.abs(a.r - b.r)) / 2
}

export const MapEditorHook = {
  mounted() {
    this.mapData = null
    this.spriteManifest = { sprites: [] }
    this.spriteImages = new Map()
    this.hexBounds = null
    this.hexByCoord = new Map()

    this.scale = 0.8
    this.tx = 0
    this.ty = 0

    this.dragging = false
    this.panning = false
    this.dragMoved = false
    this.spaceHeld = false
    this.lastPointers = new Map()
    this.pinchStartDistance = null
    this.pinchStartScale = null

    this.needsRender = false
    this.rafId = null

    // Editor tool state, kept in sync via the "editor_state" pushed event.
    this.tool = "paint"
    this.brush = 1
    this.terrain = null
    this.sprite = null
    this.location = null

    this.hoverHex = null
    this.dirtyCoords = new Set()
    this.pendingChanges = new Map()
    this.flushTimer = null

    this.build()
    this.bindInput()
    this.bindResize()
    this.bindKeys()

    this.handleEvent("editor_state", state => {
      this.tool = state.tool ?? this.tool
      this.brush = state.brush ?? this.brush
      this.terrain = state.terrain ?? this.terrain
      this.sprite = state.sprite ?? this.sprite
      this.location = state.location ?? this.location
    })

    this.handleEvent("manifest_updated", payload => {
      this.spriteManifest = payload.manifest || { sprites: [] }
      this.preloadSprites().then(() => this.scheduleRender())
    })

    this.handleEvent("terrains_updated", payload => {
      if (this.mapData) this.mapData.terrains = payload.terrains || {}
      this.scheduleRender()
    })

    this.handleEvent("map_saved", () => {
      this.dirtyCoords.clear()
      this.scheduleRender()
    })

    this.loadMapData()
  },

  destroyed() {
    this.cleanup?.()
    this.keyCleanup?.()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.rafId) cancelAnimationFrame(this.rafId)
    if (this.flushTimer) clearTimeout(this.flushTimer)
  },

  // -- setup -------------------------------------------------------------

  build() {
    this.el.classList.add("map-editor__canvas-host")
    this.el.innerHTML = `<canvas class="map-editor__canvas"></canvas>`
    this.canvas = this.el.querySelector(".map-editor__canvas")
    this.ctx = this.canvas.getContext("2d")
    this.resizeCanvas()
  },

  bindResize() {
    this.resizeObserver = new ResizeObserver(() => {
      this.resizeCanvas()
      this.scheduleRender()
    })
    this.resizeObserver.observe(this.el)
  },

  resizeCanvas() {
    const dpr = window.devicePixelRatio || 1
    const w = this.el.clientWidth || 800
    const h = this.el.clientHeight || 600

    this.canvas.width = Math.round(w * dpr)
    this.canvas.height = Math.round(h * dpr)
    this.canvas.style.width = `${w}px`
    this.canvas.style.height = `${h}px`

    this.viewportWidth = w
    this.viewportHeight = h
    this.dpr = dpr
  },

  async loadMapData() {
    try {
      const [mapRes, spriteRes] = await Promise.all([
        fetch(WORLD_MAP_URL),
        fetch(SPRITE_MANIFEST_URL),
      ])

      this.mapData = mapRes.ok ? await mapRes.json() : { hexes: [], terrains: {}, hex_size: 64 }
      this.spriteManifest = spriteRes.ok ? await spriteRes.json() : { sprites: [] }
    } catch (_error) {
      this.mapData = { hexes: [], terrains: {}, hex_size: 64 }
      this.spriteManifest = { sprites: [] }
    }

    this.indexHexes()
    await this.preloadSprites()
    this.computeHexBounds()
    this.fitToBounds()
    this.scheduleRender()
  },

  indexHexes() {
    this.hexByCoord = new Map()
    for (const hex of this.mapData.hexes || []) {
      this.hexByCoord.set(`${hex.q}:${hex.r}`, hex)
    }
  },

  preloadSprites() {
    const sprites = this.spriteManifest?.sprites || []
    const loads = sprites.map(sprite => {
      return new Promise(resolve => {
        const img = new Image()
        img.onload = () => {
          this.spriteImages.set(sprite.id, img)
          resolve()
        }
        img.onerror = () => resolve()
        img.src = `/sprites/${sprite.file}`
      })
    })
    return Promise.allSettled(loads)
  },

  hexSize() {
    return this.mapData?.hex_size || 64
  },

  computeHexBounds() {
    const size = this.hexSize()
    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity

    for (const hex of this.mapData.hexes || []) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      minX = Math.min(minX, x - size)
      minY = Math.min(minY, y - size)
      maxX = Math.max(maxX, x + size)
      maxY = Math.max(maxY, y + size)
    }

    if (!isFinite(minX)) {
      this.hexBounds = { minX: -size * 4, minY: -size * 4, maxX: size * 4, maxY: size * 4 }
    } else {
      this.hexBounds = { minX, minY, maxX, maxY }
    }
  },

  fitToBounds() {
    const b = this.hexBounds
    if (!b) return

    const w = b.maxX - b.minX
    const h = b.maxY - b.minY
    const scale = clamp(
      Math.min(this.viewportWidth / w, this.viewportHeight / h) * 0.95,
      MIN_SCALE,
      MAX_SCALE
    )

    this.scale = scale
    this.tx = this.viewportWidth / 2 - (b.minX + w / 2) * scale
    this.ty = this.viewportHeight / 2 - (b.minY + h / 2) * scale
  },

  // -- input ---------------------------------------------------------------

  bindKeys() {
    const keydown = event => {
      if (event.code === "Space") this.spaceHeld = true
    }
    const keyup = event => {
      if (event.code === "Space") this.spaceHeld = false
    }
    window.addEventListener("keydown", keydown)
    window.addEventListener("keyup", keyup)
    this.keyCleanup = () => {
      window.removeEventListener("keydown", keydown)
      window.removeEventListener("keyup", keyup)
    }
  },

  isPanGesture(event) {
    return this.tool === "pan" || this.spaceHeld || event.button === 1
  },

  bindInput() {
    const down = event => {
      this.el.setPointerCapture?.(event.pointerId)
      this.lastPointers.set(event.pointerId, { x: event.clientX, y: event.clientY })

      if (this.lastPointers.size === 1) {
        this.dragMoved = false
        this.dragStart = { x: event.clientX, y: event.clientY }
        this.dragPrevPoint = this.dragStart

        if (this.isPanGesture(event)) {
          this.panning = true
        } else {
          this.panning = false
          this.applyToolAt(event.clientX, event.clientY)
        }
      } else if (this.lastPointers.size === 2) {
        this.panning = false
        const pts = [...this.lastPointers.values()]
        this.pinchStartDistance = distance(pts[0], pts[1])
        this.pinchStartScale = this.scale
      }
    }

    const move = event => {
      const world = this.screenToWorld(event.clientX, event.clientY)
      const hex = pixelToAxial(world.x, world.y, this.hexSize())
      this.hoverHex = hex
      this.scheduleRender()

      if (!this.lastPointers.has(event.pointerId)) return
      this.lastPointers.set(event.pointerId, { x: event.clientX, y: event.clientY })

      if (this.lastPointers.size === 2) {
        const pts = [...this.lastPointers.values()]
        const dist = distance(pts[0], pts[1])
        const mid = midpoint(pts[0], pts[1])
        if (this.pinchStartDistance) {
          const factor = dist / this.pinchStartDistance
          this.zoomAt(mid, this.pinchStartScale * factor)
        }
        this.scheduleRender()
        return
      }

      if (Math.hypot(event.clientX - this.dragStart.x, event.clientY - this.dragStart.y) > 3) {
        this.dragMoved = true
      }

      if (this.panning) {
        const prev = this.dragPrevPoint
        const dx = event.clientX - prev.x
        const dy = event.clientY - prev.y
        this.dragPrevPoint = { x: event.clientX, y: event.clientY }
        this.tx += dx
        this.ty += dy
        this.scheduleRender()
      } else if (this.lastPointers.size === 1 && this.dragMoved) {
        // Interpolate along the drag path so fast strokes don't leave gaps:
        // step in world-space at roughly half a hex per sample.
        this.paintAlong(this.dragPrevPoint, { x: event.clientX, y: event.clientY })
        this.dragPrevPoint = { x: event.clientX, y: event.clientY }
      }
    }

    const up = event => {
      this.lastPointers.delete(event.pointerId)
      this.el.releasePointerCapture?.(event.pointerId)

      if (this.lastPointers.size < 2) {
        this.pinchStartDistance = null
        this.pinchStartScale = null
      }

      this.panning = false
      this.dragPrevPoint = null
    }

    const wheel = event => {
      event.preventDefault()
      const rect = this.el.getBoundingClientRect()
      const point = { x: event.clientX - rect.left, y: event.clientY - rect.top }
      const factor = Math.exp(-event.deltaY * 0.0015)
      this.zoomAt(point, this.scale * factor)
      this.scheduleRender()
    }

    const contextmenu = event => event.preventDefault()

    this.el.addEventListener("pointerdown", down)
    this.el.addEventListener("pointermove", move)
    this.el.addEventListener("pointerup", up)
    this.el.addEventListener("pointercancel", up)
    this.el.addEventListener("wheel", wheel, { passive: false })
    this.el.addEventListener("contextmenu", contextmenu)

    this.cleanup = () => {
      this.el.removeEventListener("pointerdown", down)
      this.el.removeEventListener("pointermove", move)
      this.el.removeEventListener("pointerup", up)
      this.el.removeEventListener("pointercancel", up)
      this.el.removeEventListener("wheel", wheel)
      this.el.removeEventListener("contextmenu", contextmenu)
    }
  },

  zoomAt(point, nextScale) {
    const clamped = clamp(nextScale, MIN_SCALE, MAX_SCALE)
    const worldX = (point.x - this.tx) / this.scale
    const worldY = (point.y - this.ty) / this.scale
    this.scale = clamped
    this.tx = point.x - worldX * this.scale
    this.ty = point.y - worldY * this.scale
  },

  screenToWorld(clientX, clientY) {
    const rect = this.el.getBoundingClientRect()
    const x = (clientX - rect.left - this.tx) / this.scale
    const y = (clientY - rect.top - this.ty) / this.scale
    return { x, y }
  },

  // Samples points along the segment from `from` to `to` (screen space) at
  // roughly half-hex spacing in world space, applying the tool at each hex
  // encountered so fast drags don't skip hexes.
  paintAlong(from, to) {
    const size = this.hexSize()
    const worldFrom = this.screenToWorld(from.x, from.y)
    const worldTo = this.screenToWorld(to.x, to.y)
    const dist = Math.hypot(worldTo.x - worldFrom.x, worldTo.y - worldFrom.y)
    const step = size * 0.5
    const steps = Math.max(1, Math.ceil(dist / step))

    const seen = new Set()
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      const x = worldFrom.x + (worldTo.x - worldFrom.x) * t
      const y = worldFrom.y + (worldTo.y - worldFrom.y) * t
      const hex = pixelToAxial(x, y, size)
      const key = `${hex.q}:${hex.r}`
      if (seen.has(key)) continue
      seen.add(key)
      this.applyToolAtHex(hex)
    }
  },

  applyToolAt(clientX, clientY) {
    const world = this.screenToWorld(clientX, clientY)
    const hex = pixelToAxial(world.x, world.y, this.hexSize())
    this.applyToolAtHex(hex)
  },

  brushFootprint(center) {
    // Aperture-7 hierarchy brushes: paint every fine hex of the parent cell
    // the cursor is over (7 for a level-1 cell, 49 for a level-0 region).
    if (this.brush === "l1") {
      const [i, j] = parentL1(center.q, center.r)
      return childrenL1(i, j)
    }
    if (this.brush === "l0") {
      const [i, j] = parentL1(center.q, center.r)
      const [m, n] = parentL0(i, j)
      return descendantsL0(m, n)
    }

    const radius = (this.brush || 1) - 1
    if (radius <= 0) return [center]

    const out = []
    for (let dq = -radius; dq <= radius; dq++) {
      for (let dr = -radius; dr <= radius; dr++) {
        const q = center.q + dq
        const r = center.r + dr
        if (axialDistance(center, { q, r }) <= radius) out.push({ q, r })
      }
    }
    return out
  },

  applyToolAtHex(center) {
    if (!this.mapData) return

    switch (this.tool) {
      case "paint":
        for (const hex of this.brushFootprint(center)) this.paintHex(hex)
        break
      case "erase":
        for (const hex of this.brushFootprint(center)) this.eraseHex(hex)
        break
      case "road":
        for (const hex of this.brushFootprint(center)) this.toggleRoadHex(hex)
        break
      case "location":
        this.setLocationHex(center)
        break
      default:
        break
    }

    this.scheduleRender()
    this.scheduleFlush()
  },

  getOrCreateHex(coord) {
    const key = `${coord.q}:${coord.r}`
    let hex = this.hexByCoord.get(key)
    if (!hex) {
      hex = { q: coord.q, r: coord.r, t: this.terrain || Object.keys(this.mapData.terrains || {})[0] }
      this.hexByCoord.set(key, hex)
      this.mapData.hexes.push(hex)
    }
    return hex
  },

  paintHex(coord) {
    if (!this.terrain) return
    const hex = this.getOrCreateHex(coord)
    hex.t = this.terrain
    if (this.sprite) {
      hex.s = this.sprite
    }
    this.markDirty(hex)
  },

  eraseHex(coord) {
    const key = `${coord.q}:${coord.r}`
    const hex = this.hexByCoord.get(key)
    if (!hex) return

    this.hexByCoord.delete(key)
    this.mapData.hexes = this.mapData.hexes.filter(h => h !== hex)
    this.dirtyCoords.add(key)
    this.pendingChanges.set(key, { q: coord.q, r: coord.r, delete: true })
  },

  toggleRoadHex(coord) {
    const hex = this.getOrCreateHex(coord)
    hex.road = !hex.road
    this.markDirty(hex)
  },

  setLocationHex(coord) {
    if (!this.location) return
    const key = `${coord.q}:${coord.r}`
    const hex = this.getOrCreateHex(coord)

    // Enforce one hex per location client-side too, for instant feedback.
    if (hex.loc === this.location) {
      delete hex.loc
    } else {
      for (const other of this.mapData.hexes) {
        if (other.loc === this.location && other !== hex) {
          delete other.loc
          this.markDirty(other)
        }
      }
      hex.loc = this.location
    }

    this.markDirty(hex)
    void key
  },

  markDirty(hex) {
    const key = `${hex.q}:${hex.r}`
    this.dirtyCoords.add(key)
    this.pendingChanges.set(key, {
      q: hex.q,
      r: hex.r,
      t: hex.t,
      s: hex.s || null,
      road: !!hex.road,
      loc: hex.loc || null,
    })
  },

  scheduleFlush() {
    if (this.flushTimer) clearTimeout(this.flushTimer)
    this.flushTimer = setTimeout(() => this.flush(), PUSH_DEBOUNCE_MS)
  },

  flush() {
    this.flushTimer = null
    if (this.pendingChanges.size === 0) return

    const hexes = [...this.pendingChanges.values()]
    this.pendingChanges.clear()
    this.pushEvent("hexes_changed", { hexes })
  },

  // -- render loop -----------------------------------------------------------

  scheduleRender() {
    this.needsRender = true
    if (this.rafId) return

    const loop = () => {
      if (!this.needsRender) {
        this.rafId = null
        return
      }
      this.needsRender = false
      this.render()
      this.rafId = requestAnimationFrame(loop)
    }

    this.rafId = requestAnimationFrame(loop)
  },

  render() {
    const ctx = this.ctx
    const dpr = this.dpr || 1

    ctx.save()
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, this.viewportWidth, this.viewportHeight)
    ctx.fillStyle = "#090d0c"
    ctx.fillRect(0, 0, this.viewportWidth, this.viewportHeight)

    if (this.mapData) {
      ctx.save()
      ctx.translate(this.tx, this.ty)
      ctx.scale(this.scale, this.scale)

      if (this.scale >= LOD_SPRITE) {
        this.renderSpriteTiles()
      } else {
        this.renderFlatTerrain()
      }

      this.renderRoads(Math.max(2 / this.scale, 1))

      if (this.scale >= LOD_GRID) {
        this.renderGridOutlines()
      }

      this.renderDirtyOverlay()
      this.renderLocationBadges()
      this.renderHoverHighlight()

      ctx.restore()
    }

    ctx.restore()
  },

  viewportWorldRect() {
    const minX = -this.tx / this.scale
    const minY = -this.ty / this.scale
    const maxX = (this.viewportWidth - this.tx) / this.scale
    const maxY = (this.viewportHeight - this.ty) / this.scale
    return { minX, minY, maxX, maxY }
  },

  visibleHexes() {
    const rect = this.viewportWorldRect()
    const size = this.hexSize()
    const pad = size * 2
    const out = []

    for (const hex of this.mapData.hexes || []) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      if (x < rect.minX - pad || x > rect.maxX + pad || y < rect.minY - pad || y > rect.maxY + pad) {
        continue
      }
      out.push(hex)
    }

    return out
  },

  renderFlatTerrain() {
    const ctx = this.ctx
    const size = this.hexSize()
    const terrains = this.mapData.terrains || {}
    const byColor = new Map()

    for (const hex of this.visibleHexes()) {
      const terrain = terrains[hex.t]
      const color = terrain?.color || FALLBACK_TERRAIN_COLOR
      if (!byColor.has(color)) byColor.set(color, new Path2D())
      const path = byColor.get(color)

      const { x, y } = axialToPixel(hex.q, hex.r, size)
      const corners = hexPolygonPoints(x, y, size)
      path.moveTo(corners[0][0], corners[0][1])
      for (let i = 1; i < corners.length; i++) path.lineTo(corners[i][0], corners[i][1])
      path.closePath()
    }

    for (const [color, path] of byColor) {
      ctx.fillStyle = color
      ctx.fill(path)
    }
  },

  renderSpriteTiles() {
    const ctx = this.ctx
    const size = this.hexSize()
    const terrains = this.mapData.terrains || {}

    for (const hex of this.visibleHexes()) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      const sprite = hex.s && this.spriteImages.get(hex.s)

      if (sprite) {
        ctx.drawImage(sprite, x - size, y - size, size * 2, size * 2)
      } else {
        const terrain = terrains[hex.t]
        ctx.fillStyle = terrain?.color || FALLBACK_TERRAIN_COLOR
        const corners = hexPolygonPoints(x, y, size)
        ctx.beginPath()
        ctx.moveTo(corners[0][0], corners[0][1])
        for (let i = 1; i < corners.length; i++) ctx.lineTo(corners[i][0], corners[i][1])
        ctx.closePath()
        ctx.fill()
      }
    }
  },

  renderGridOutlines() {
    const ctx = this.ctx
    const size = this.hexSize()

    ctx.strokeStyle = "rgba(255, 255, 255, 0.12)"
    ctx.lineWidth = 1 / this.scale

    const parents = new Set()

    for (const hex of this.visibleHexes()) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      const corners = hexPolygonPoints(x, y, size)
      ctx.beginPath()
      ctx.moveTo(corners[0][0], corners[0][1])
      for (let i = 1; i < corners.length; i++) ctx.lineTo(corners[i][0], corners[i][1])
      ctx.closePath()
      ctx.stroke()

      const [i, j] = parentL1(hex.q, hex.r)
      parents.add(`${i},${j}`)
    }

    // Faint level-1 nesting outlines, consistent with the play renderer.
    ctx.strokeStyle = "rgba(255, 255, 255, 0.28)"
    ctx.lineWidth = 1.5 / this.scale

    for (const key of parents) {
      const [i, j] = key.split(",").map(Number)
      const corners = outlineL1(i, j, size)
      ctx.beginPath()
      ctx.moveTo(corners[0].x, corners[0].y)
      for (let k = 1; k < corners.length; k++) ctx.lineTo(corners[k].x, corners[k].y)
      ctx.closePath()
      ctx.stroke()
    }
  },

  renderRoads(lineWidth) {
    const ctx = this.ctx
    const size = this.hexSize()
    const roadHexes = (this.mapData.hexes || []).filter(hex => hex.road)
    if (roadHexes.length === 0) return

    ctx.strokeStyle = "rgba(218, 194, 133, 0.75)"
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"

    const seen = new Set()
    const rect = this.viewportWorldRect()
    const pad = size * 4

    for (const hex of roadHexes) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      if (x < rect.minX - pad || x > rect.maxX + pad || y < rect.minY - pad || y > rect.maxY + pad) {
        continue
      }

      for (const { q: nq, r: nr } of axialNeighbors(hex.q, hex.r).slice(0, 3)) {
        const neighbor = this.hexByCoord.get(`${nq}:${nr}`)
        if (!neighbor || !neighbor.road) continue

        const key = `${Math.min(hex.q, nq)}:${Math.min(hex.r, nr)}:${Math.max(hex.q, nq)}:${Math.max(hex.r, nr)}`
        if (seen.has(key)) continue
        seen.add(key)

        const np = axialToPixel(nq, nr, size)
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.lineTo(np.x, np.y)
        ctx.stroke()
      }
    }
  },

  renderDirtyOverlay() {
    if (this.dirtyCoords.size === 0) return

    const ctx = this.ctx
    const size = this.hexSize()
    ctx.fillStyle = "rgba(251, 191, 36, 0.28)"

    for (const key of this.dirtyCoords) {
      const [q, r] = key.split(":").map(Number)
      const { x, y } = axialToPixel(q, r, size)
      const corners = hexPolygonPoints(x, y, size)
      ctx.beginPath()
      ctx.moveTo(corners[0][0], corners[0][1])
      for (let i = 1; i < corners.length; i++) ctx.lineTo(corners[i][0], corners[i][1])
      ctx.closePath()
      ctx.fill()
    }
  },

  renderLocationBadges() {
    const ctx = this.ctx
    const size = this.hexSize()
    const invScale = 1 / this.scale

    for (const hex of this.mapData.hexes || []) {
      if (!hex.loc) continue
      const { x, y } = axialToPixel(hex.q, hex.r, size)

      ctx.save()
      ctx.translate(x, y)
      ctx.scale(invScale, invScale)

      ctx.beginPath()
      ctx.arc(0, 0, 10, 0, Math.PI * 2)
      ctx.fillStyle = "#7c6df2"
      ctx.fill()
      ctx.lineWidth = 2
      ctx.strokeStyle = "#d8d1ff"
      ctx.stroke()

      ctx.font = "12px var(--font-sans, sans-serif)"
      ctx.textAlign = "center"
      ctx.lineWidth = 3
      ctx.strokeStyle = "#090d0c"
      ctx.fillStyle = "#f2eee8"
      ctx.strokeText(hex.loc, 0, 24)
      ctx.fillText(hex.loc, 0, 24)

      ctx.restore()
    }
  },

  renderHoverHighlight() {
    if (!this.hoverHex) return
    const ctx = this.ctx
    const size = this.hexSize()

    const footprint = this.brushFootprint(this.hoverHex)

    ctx.strokeStyle = "rgba(255, 255, 255, 0.9)"
    ctx.lineWidth = 2 / this.scale

    for (const hex of footprint) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      const corners = hexPolygonPoints(x, y, size)
      ctx.beginPath()
      ctx.moveTo(corners[0][0], corners[0][1])
      for (let i = 1; i < corners.length; i++) ctx.lineTo(corners[i][0], corners[i][1])
      ctx.closePath()
      ctx.stroke()
    }
  },
}

function clamp(value, lo, hi) {
  return Math.max(lo, Math.min(hi, value))
}

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

function midpoint(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
}
