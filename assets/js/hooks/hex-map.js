import { axialToPixel, hexPolygonPoints } from "../hex/grid"
import { parentL1, parentL0, outlineL1, outlineL0 } from "../hex/hierarchy"

const WORLD_MAP_URL = "/maps/world.json"
const SPRITE_MANIFEST_URL = "/sprites/manifest.json"
const PLANE_SIZE = 2000

const MIN_SCALE = 0.08
const MAX_SCALE = 2.5

// Aperture-7 nested LOD: fine 64px hexes above LOD_FINE, level-1 parent
// hexagons (7 fine each) between LOD_MID and LOD_FINE, level-0 hexagons
// (49 fine each) below LOD_MID. Sprites appear above LOD_SPRITE.
const LOD_SPRITE = 0.6
const LOD_FINE = 0.45
const LOD_MID = 0.16

const MAP_LAYERS = [
  { key: "terrain", label: "Рельеф", mark: "⌁" },
  { key: "political", label: "Владения", mark: "♜" },
  { key: "infrastructure", label: "Пути и сети", mark: "⌘" },
  { key: "economic", label: "Торговля", mark: "¤" },
  { key: "diplomacy", label: "Дипломатия", mark: "⚭" },
]

const KIND = {
  city: { r: 16, fill: "#d6a643", stroke: "#fff1a8" },
  tower: { r: 18, fill: "#7c6df2", stroke: "#d8d1ff" },
  wilderness: { r: 12, fill: "#4f8f5b", stroke: "#b7efbf" },
  dungeon_entrance: { r: 15, fill: "#b94c4c", stroke: "#ffd0d0" },
  base: { r: 14, fill: "#8c9bad", stroke: "#e1e8f0" },
}

const KIND_LABEL = {
  city: "город",
  tower: "башня",
  wilderness: "урочище",
  dungeon_entrance: "вход в подземелье",
  base: "убежище",
}

const FALLBACK_TERRAIN_COLOR = "#3a3a3a"

export const HexMapHook = {
  mounted() {
    this.locations = []
    this.player = null
    this.selected = null
    this.sheetOpen = false

    this.mapData = null
    this.spriteManifest = null
    this.spriteImages = new Map()
    this.hexBounds = null

    this.scale = 0.8
    this.tx = 0
    this.ty = 0

    this.dragging = false
    this.dragMoved = false
    this.lastPointers = new Map()
    this.pinchStartDistance = null
    this.pinchStartScale = null

    this.needsRender = false
    this.rafId = null

    this.pathPreview = null
    this.activeFilter = "terrain"
    this.layerMenuOpen = false
    this.orgs = []
    this.economic = []
    this.diplomacy = []
    this.orgOverlay = null

    this.build()
    this.bindInput()
    this.bindResize()

    this.handleEvent("map_state", payload => {
      this.locations = payload.locations || []
      this.player = payload.player || null
      this.orgs = payload.filters?.orgs || []
      this.economic = payload.filters?.economic || []
      this.diplomacy = payload.filters?.diplomacy || []
      this.orgOverlay = null
      this.selected = null
      this.pathPreview = null
      this.closeSheet()
      this.updateLegend()
      this.applyInitialViewIfNeeded()
      this.scheduleRender()
    })

    this.handleEvent("path_preview", payload => {
      if (this.selected !== payload.slug) return
      this.pathPreview = payload
      this.updateSheetPreview()
      this.scheduleRender()
    })

    this.handleEvent("path_preview_error", payload => {
      if (this.selected !== payload.slug) return
      this.pathPreview = null
      this.updateSheetPreview()
      this.scheduleRender()
    })

    this.handleEvent("close_map_sheet", () => {
      this.selected = null
      this.closeSheet()
      this.scheduleRender()
    })

    this.handleEvent("close_map_layer_menu", () => this.setLayerMenuOpen(false))

    this.loadMapData()
  },

  destroyed() {
    this.cleanup?.()
    this.controlCleanup?.()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.rafId) cancelAnimationFrame(this.rafId)
  },

  // -- setup -------------------------------------------------------------

  build() {
    this.el.classList.add("hex-map")
    this.el.innerHTML = `
      <canvas class="hex-map__canvas"></canvas>
      <div class="hex-map__layers" data-layer-control>
        <button
          class="hex-map__layer-toggle"
          type="button"
          aria-expanded="false"
          aria-controls="hex-map-layer-menu"
        >
          <span class="hex-map__layer-compass" aria-hidden="true">✥</span>
          <span class="hex-map__layer-toggle-copy">
            <small>Слои атласа</small>
            <strong data-layer-label>Рельеф</strong>
          </span>
          <span class="hex-map__layer-chevron" aria-hidden="true">⌄</span>
        </button>
        <div
          id="hex-map-layer-menu"
          class="hex-map__layer-menu"
          role="radiogroup"
          aria-label="Слой карты"
          hidden
        >
          <p>Картографические кальки</p>
          ${MAP_LAYERS.map(
            layer => `
              <button
                type="button"
                role="radio"
                aria-checked="${layer.key === this.activeFilter}"
                data-filter="${layer.key}"
              >
                <span aria-hidden="true">${layer.mark}</span>
                ${layer.label}
              </button>
            `
          ).join("")}
        </div>
      </div>
      <div class="hex-map__legend" hidden></div>
      <section class="hex-map__sheet" hidden></section>
    `
    this.canvas = this.el.querySelector(".hex-map__canvas")
    this.ctx = this.canvas.getContext("2d")
    this.sheet = this.el.querySelector(".hex-map__sheet")
    this.legend = this.el.querySelector(".hex-map__legend")
    this.layerControl = this.el.querySelector("[data-layer-control]")
    this.layerToggle = this.el.querySelector(".hex-map__layer-toggle")
    this.layerMenu = this.el.querySelector(".hex-map__layer-menu")
    this.layerLabel = this.el.querySelector("[data-layer-label]")

    this.bindLayerControl()
    this.updateLayerControl()

    this.resizeCanvas()
  },

  bindLayerControl() {
    const toggle = event => {
      event.stopPropagation()
      this.setLayerMenuOpen(!this.layerMenuOpen)
    }

    const choose = event => {
      const button = event.target.closest("[data-filter]")
      if (!button) return

      event.stopPropagation()
      this.setActiveFilter(button.dataset.filter)
      this.setLayerMenuOpen(false)
    }

    const dismiss = event => {
      if (this.layerMenuOpen && !this.layerControl.contains(event.target)) {
        this.setLayerMenuOpen(false)
      }
    }

    const dismissWithKeyboard = event => {
      if (event.key !== "Escape" || !this.layerMenuOpen) return

      this.setLayerMenuOpen(false)
      this.layerToggle.focus()
    }

    this.layerToggle.addEventListener("click", toggle)
    this.layerMenu.addEventListener("click", choose)
    document.addEventListener("pointerdown", dismiss)
    document.addEventListener("keydown", dismissWithKeyboard)

    this.controlCleanup = () => {
      this.layerToggle.removeEventListener("click", toggle)
      this.layerMenu.removeEventListener("click", choose)
      document.removeEventListener("pointerdown", dismiss)
      document.removeEventListener("keydown", dismissWithKeyboard)
    }
  },

  setLayerMenuOpen(open) {
    this.layerMenuOpen = open
    this.layerMenu.hidden = !open
    this.layerToggle.setAttribute("aria-expanded", String(open))
    this.layerControl.classList.toggle("is-open", open)

    if (open) this.pushEvent("close_account_menu", {})
  },

  setActiveFilter(filter) {
    if (!MAP_LAYERS.some(layer => layer.key === filter)) return

    this.activeFilter = filter
    this.orgOverlay = null
    this.updateLayerControl()
    this.updateLegend()
    this.scheduleRender()
  },

  updateLayerControl() {
    const active = MAP_LAYERS.find(layer => layer.key === this.activeFilter) || MAP_LAYERS[0]
    this.layerLabel.textContent = active.label

    for (const button of this.layerMenu.querySelectorAll("[data-filter]")) {
      const selected = button.dataset.filter === active.key
      button.setAttribute("aria-checked", String(selected))
      button.classList.toggle("is-active", selected)
    }
  },

  updateLegend() {
    if (this.activeFilter === "diplomacy") {
      if (this.diplomacy.length === 0) {
        this.legend.hidden = true
        this.legend.innerHTML = ""
        return
      }

      this.legend.hidden = false
      this.legend.innerHTML = `
        <strong class="hex-map__legend-title">Дипломатия</strong>
        <span class="hex-map__legend-chip"><i style="background:#69d3ff"></i>Союз</span>
        <span class="hex-map__legend-chip"><i style="background:#ef6767"></i>Соперничество</span>
        <span class="hex-map__legend-chip"><i style="background:#ffae45"></i>Война</span>
      `
      return
    }

    if (this.activeFilter === "economic") {
      if (this.economic.length === 0) {
        this.legend.hidden = true
        this.legend.innerHTML = ""
        return
      }

      const organizationsById = new Map(this.orgs.map(org => [org.id, org]))
      this.legend.hidden = false
      this.legend.innerHTML = [`<strong class="hex-map__legend-title">Экономическая активность</strong>`]
        .concat(
          this.economic.map(activity => {
            const org = organizationsById.get(activity.organization_id)
            const color = org?.color || "#e6bb58"
            return `
              <span class="hex-map__legend-chip">
                <i style="background:${color}"></i>${escapeHtml(activity.organization_name)} · ${economicActivityLabel(activity.activity_level)}
              </span>
            `
          })
        )
        .join("")
      return
    }

    if (!["political", "infrastructure"].includes(this.activeFilter) || this.orgs.length === 0) {
      this.legend.hidden = true
      this.legend.innerHTML = ""
      return
    }

    this.legend.hidden = false
    const label = this.activeFilter === "political" ? "Владения" : "Инфраструктура"
    this.legend.innerHTML = [`<strong class="hex-map__legend-title">${label}</strong>`]
      .concat(
        this.orgs.map(
          org => `
            <span class="hex-map__legend-chip">
              <i style="background:${org.color}"></i>${escapeHtml(org.name)}
            </span>
          `
        )
      )
      .join("")
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
    const w = this.el.clientWidth || 390
    const h = this.el.clientHeight || 700

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

      this.mapData = mapRes.ok ? await mapRes.json() : null
      this.spriteManifest = spriteRes.ok ? await spriteRes.json() : { sprites: [] }
    } catch (_error) {
      this.mapData = null
      this.spriteManifest = { sprites: [] }
    }

    if (this.mapData) {
      this.indexHexes()
      this.computeHierarchy()
      await this.preloadSprites()
      this.computeHexBounds()
    }

    this.applyInitialViewIfNeeded()
    this.scheduleRender()
  },

  indexHexes() {
    this.hexByCoord = new Map()
    this.hexByLoc = new Map()
    this.terrainsById = this.mapData.terrains || {}

    for (const hex of this.mapData.hexes || []) {
      const key = `${hex.q}:${hex.r}`
      this.hexByCoord.set(key, hex)
      if (hex.loc) this.hexByLoc.set(hex.loc, hex)
    }
  },

  // Aggregates the sparse fine grid into level-1 cells (up to 7 fine hexes,
  // majority terrain / any road) and level-0 cells (up to 7 level-1 cells,
  // majority weighted by fine-hex count). Precomputed once per map load;
  // outlines are cached as Path2D for cheap filling every frame.
  computeHierarchy() {
    const size = this.hexSize()
    const l1 = new Map()

    for (const hex of this.mapData.hexes || []) {
      const [i, j] = parentL1(hex.q, hex.r)
      const key = `${i},${j}`
      let cell = l1.get(key)
      if (!cell) {
        cell = { i, j, terrainCounts: new Map(), road: false, count: 0 }
        l1.set(key, cell)
      }
      cell.terrainCounts.set(hex.t, (cell.terrainCounts.get(hex.t) || 0) + 1)
      if (hex.road) cell.road = true
      cell.count++
    }

    const l0 = new Map()

    for (const cell of l1.values()) {
      cell.terrain = majorityKey(cell.terrainCounts)
      cell.path = polygonPath(outlineL1(cell.i, cell.j, size))

      const [m, n] = parentL0(cell.i, cell.j)
      const key = `${m},${n}`
      let parent = l0.get(key)
      if (!parent) {
        parent = { m, n, terrainCounts: new Map(), count: 0 }
        l0.set(key, parent)
      }
      parent.terrainCounts.set(
        cell.terrain,
        (parent.terrainCounts.get(cell.terrain) || 0) + cell.count
      )
      parent.count += cell.count
    }

    for (const cell of l0.values()) {
      cell.terrain = majorityKey(cell.terrainCounts)
      cell.path = polygonPath(outlineL0(cell.m, cell.n, size))
    }

    this.l1Cells = l1
    this.l0Cells = l0
  },

  // Political overlay: for every org-linked location, resolve the fine hex
  // plus its ancestor cells so each LOD tier can tint the right shape.
  computeOrgOverlay() {
    const overlay = { fine: [], l1: new Map(), l0: new Map(), rings: new Map() }

    for (const org of this.orgs) {
      for (const slug of org.location_slugs || []) {
        const hex = this.hexByLoc?.get(slug)
        if (!hex) continue

        overlay.fine.push({ q: hex.q, r: hex.r, color: org.color })
        overlay.rings.set(slug, org.color)

        const [i, j] = parentL1(hex.q, hex.r)
        overlay.l1.set(`${i},${j}`, org.color)
        const [m, n] = parentL0(i, j)
        overlay.l0.set(`${m},${n}`, org.color)
      }
    }

    return overlay
  },

  orgOverlayData() {
    if (!this.orgOverlay) this.orgOverlay = this.computeOrgOverlay()
    return this.orgOverlay
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
      this.hexBounds = { minX: 0, minY: 0, maxX: size, maxY: size }
    } else {
      this.hexBounds = { minX, minY, maxX, maxY }
    }
  },

  // -- location <-> hex-pixel mapping -------------------------------------

  // Returns world (hex-space) pixel coordinates for a location, matching by
  // slug via the map file's `loc` fields first, falling back to scaling the
  // location's x,y from the 2000x2000 plane onto the hex-map pixel bounds.
  locationWorldPos(loc) {
    const hex = this.hexByLoc?.get(loc.slug)
    if (hex) {
      return axialToPixel(hex.q, hex.r, this.hexSize())
    }

    if (this.hexBounds) {
      const b = this.hexBounds
      const w = b.maxX - b.minX
      const h = b.maxY - b.minY
      return {
        x: b.minX + (loc.x / PLANE_SIZE) * w,
        y: b.minY + (loc.y / PLANE_SIZE) * h,
      }
    }

    return { x: loc.x, y: loc.y }
  },

  // -- view fitting --------------------------------------------------------

  applyInitialViewIfNeeded() {
    if (this.initialViewApplied) return
    if (!this.hexBounds) return
    if (this.locations.length === 0 && !this.mapData) return

    this.initialViewApplied = true

    const player = this.player
    const playerLoc = player && this.locations.find(loc => loc.slug === player.location_slug)

    if (playerLoc) {
      this.centerOn(this.locationWorldPos(playerLoc), 0.8)
    } else {
      this.fitToBounds()
    }
  },

  centerOn(worldPos, scale) {
    this.scale = clamp(scale, MIN_SCALE, MAX_SCALE)
    this.tx = this.viewportWidth / 2 - worldPos.x * this.scale
    this.ty = this.viewportHeight / 2 - worldPos.y * this.scale
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

  bindInput() {
    const interactiveTarget = target =>
      target instanceof Element && target.closest("button, a, input, select, textarea, [role='button']")

    const down = event => {
      // The location sheet lives inside the map hook. Capturing a pointer that
      // started on its Travel button retargets the following click to the map
      // root, so the button never fires.
      if (interactiveTarget(event.target)) return

      try {
        this.el.setPointerCapture?.(event.pointerId)
      } catch (_error) {
        // Synthetic pointer events (tests) have no active pointer to capture.
      }
      this.lastPointers.set(event.pointerId, { x: event.clientX, y: event.clientY })

      if (this.lastPointers.size === 1) {
        this.dragging = true
        this.dragMoved = false
        this.dragStart = { x: event.clientX, y: event.clientY }
      } else if (this.lastPointers.size === 2) {
        this.dragging = false
        const pts = [...this.lastPointers.values()]
        this.pinchStartDistance = distance(pts[0], pts[1])
        this.pinchStartScale = this.scale
        this.pinchMidpoint = midpoint(pts[0], pts[1])
      }
    }

    const move = event => {
      if (!this.lastPointers.has(event.pointerId)) return
      this.lastPointers.set(event.pointerId, { x: event.clientX, y: event.clientY })

      if (this.lastPointers.size === 2) {
        const pts = [...this.lastPointers.values()]
        const dist = distance(pts[0], pts[1])
        const mid = midpoint(pts[0], pts[1])

        if (this.pinchStartDistance) {
          const factor = dist / this.pinchStartDistance
          this.zoomAt(mid, this.pinchStartScale * factor, true)
        }
        this.scheduleRender()
        return
      }

      if (!this.dragging) return

      const prev = this.dragPrevPoint || this.dragStart
      const dx = event.clientX - prev.x
      const dy = event.clientY - prev.y
      this.dragPrevPoint = { x: event.clientX, y: event.clientY }

      if (Math.hypot(event.clientX - this.dragStart.x, event.clientY - this.dragStart.y) > 6) {
        this.dragMoved = true
      }

      this.tx += dx
      this.ty += dy
      this.scheduleRender()
    }

    const up = event => {
      if (!this.lastPointers.has(event.pointerId)) return

      this.lastPointers.delete(event.pointerId)
      try {
        this.el.releasePointerCapture?.(event.pointerId)
      } catch (_error) {
        // Synthetic pointer events (tests) hold no capture to release.
      }

      if (this.lastPointers.size < 2) {
        this.pinchStartDistance = null
        this.pinchStartScale = null
      }

      if (this.dragging && !this.dragMoved) {
        this.tap(event.clientX, event.clientY)
      }

      this.dragging = false
      this.dragPrevPoint = null
    }

    const wheel = event => {
      if (interactiveTarget(event.target)) return

      event.preventDefault()
      const rect = this.el.getBoundingClientRect()
      const point = { x: event.clientX - rect.left, y: event.clientY - rect.top }
      const factor = Math.exp(-event.deltaY * 0.0015)
      this.zoomAt(point, this.scale * factor, false)
      this.scheduleRender()
    }

    this.el.addEventListener("pointerdown", down)
    this.el.addEventListener("pointermove", move)
    this.el.addEventListener("pointerup", up)
    this.el.addEventListener("pointercancel", up)
    this.el.addEventListener("wheel", wheel, { passive: false })

    this.cleanup = () => {
      this.el.removeEventListener("pointerdown", down)
      this.el.removeEventListener("pointermove", move)
      this.el.removeEventListener("pointerup", up)
      this.el.removeEventListener("pointercancel", up)
      this.el.removeEventListener("wheel", wheel)
    }
  },

  // point is in element-local (CSS pixel) coordinates
  zoomAt(point, nextScale, isPinch) {
    const clamped = clamp(nextScale, MIN_SCALE, MAX_SCALE)
    const worldX = (point.x - this.tx) / this.scale
    const worldY = (point.y - this.ty) / this.scale

    this.scale = clamped
    this.tx = point.x - worldX * this.scale
    this.ty = point.y - worldY * this.scale

    if (isPinch) this.dragMoved = true
  },

  screenToWorld(clientX, clientY) {
    const rect = this.el.getBoundingClientRect()
    const x = (clientX - rect.left - this.tx) / this.scale
    const y = (clientY - rect.top - this.ty) / this.scale
    return { x, y }
  },

  tap(clientX, clientY) {
    const world = this.screenToWorld(clientX, clientY)
    const screenRadius = 40 / this.scale

    let hit = null
    let hitDist = Infinity

    for (const loc of this.locations) {
      const pos = this.locationWorldPos(loc)
      const d = Math.hypot(pos.x - world.x, pos.y - world.y)
      if (d < screenRadius && d < hitDist) {
        hit = loc
        hitDist = d
      }
    }

    if (!hit) {
      this.selected = null
      this.pathPreview = null
      this.closeSheet()
      this.scheduleRender()
      return
    }

    this.selected = hit.slug
    this.pathPreview = null
    this.openSheet(hit)
    this.scheduleRender()
  },

  // -- sheet ---------------------------------------------------------------

  openSheet(loc) {
    const safe = loc.safe_zone ? "безопасное место" : "дикие земли"
    const action = loc.can_travel
      ? `<button class="hex-map__travel" data-travel="${loc.slug}">Отправиться</button>`
      : this.player?.location_slug === loc.slug
        ? `<span class="hex-map__here">Вы здесь</span>`
        : `<span class="hex-map__muted">Нет прямого пути</span>`

    // Map-first: activities are offered here, on the sheet of the place the
    // player is physically at (the server only sends actions in that case).
    const actions = (loc.actions || [])
      .map(a => `<a class="hex-map__action" href="${a.href}">${escapeHtml(a.label)}</a>`)
      .join("")

    this.sheet.hidden = false
    this.setSheetOpen(true)
    this.sheet.innerHTML = `
      <div>
        <h2>${escapeHtml(loc.name)}</h2>
        <p>${safe} · ${KIND_LABEL[loc.kind] || "неизведанное место"}</p>
        <p class="hex-map__preview" data-preview hidden></p>
      </div>
      ${actions ? `<div class="hex-map__actions">${actions}</div>` : ""}
      ${action}
    `

    const button = this.sheet.querySelector("[data-travel]")
    if (button) {
      button.addEventListener(
        "click",
        event => {
          event.stopPropagation()
          this.pushEvent("location_clicked", { slug: loc.slug })
        },
        { once: true }
      )
    }

    if (loc.can_travel) {
      this.pushEvent("preview_path", { slug: loc.slug })
    }
  },

  updateSheetPreview() {
    const el = this.sheet.querySelector("[data-preview]")
    if (!el) return

    if (this.pathPreview) {
      const { travel_days, food_units } = this.pathPreview
      el.hidden = false
      el.textContent = `≈ ${travel_days} дн. пути · еда: ${food_units}`
    } else {
      el.hidden = true
      el.textContent = ""
    }
  },

  closeSheet() {
    this.sheet.hidden = true
    this.sheet.innerHTML = ""
    this.pathPreview = null
    this.setSheetOpen(false)
  },

  setSheetOpen(open) {
    if (this.sheetOpen === open) return

    this.sheetOpen = open
    this.pushEvent("map_location_selected", { selected: open })
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

      if (this.scale >= LOD_FINE) {
        // FINE: individual 64px hexes, with the level-1 nesting visible.
        if (this.scale >= LOD_SPRITE) {
          this.renderSpriteTiles()
        } else {
          this.renderFlatTerrain()
        }
        this.renderRoads(this.scale >= LOD_SPRITE ? 5 / this.scale : 2 / this.scale)
        this.renderPoliticalFine()
        this.renderParentOutlines(this.l1Cells, 1.5 / this.scale, 0.28)
      } else if (this.scale >= LOD_MID) {
        // MID: every 7 fine hexes merged into their rotated level-1 parent.
        this.renderCells(this.l1Cells)
        this.renderL1Roads(6 / this.scale)
        this.renderPoliticalCells(this.l1Cells, "l1")
        this.renderParentOutlines(this.l0Cells, 2 / this.scale, 0.3)
      } else {
        // WORLD: level-0 hexagons, 49 fine hexes each.
        this.renderCells(this.l0Cells)
        this.renderPoliticalCells(this.l0Cells, "l0")
      }

      this.renderInfrastructure()
      this.renderEconomic()
      this.renderDiplomacy()

      ctx.restore()
    }

    if (this.pathPreview) {
      ctx.save()
      ctx.translate(this.tx, this.ty)
      ctx.scale(this.scale, this.scale)
      this.renderPathPreview(3 / this.scale)
      ctx.restore()
    }

    if (this.scale >= LOD_MID) {
      this.renderLocations(ctx)
    } else {
      this.renderLocationMarkersOnly(ctx)
    }

    ctx.restore()
  },

  // Viewport (world-space) rectangle currently visible, for culling.
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
    const byColor = new Map()

    for (const hex of this.visibleHexes()) {
      const terrain = this.terrainsById[hex.t]
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

    for (const hex of this.visibleHexes()) {
      const { x, y } = axialToPixel(hex.q, hex.r, size)
      const sprite = hex.s && this.spriteImages.get(hex.s)

      if (sprite) {
        ctx.drawImage(sprite, x - size, y - size, size * 2, size * 2)
      } else {
        const terrain = this.terrainsById[hex.t]
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

  renderRoads(lineWidth) {
    const ctx = this.ctx
    const size = this.hexSize()
    const roadHexes = (this.mapData.hexes || []).filter(hex => hex.road)
    if (roadHexes.length === 0) return

    const byCoord = this.hexByCoord

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

      for (const [dq, dr] of [
        [1, 0],
        [1, -1],
        [0, -1],
      ]) {
        const nq = hex.q + dq
        const nr = hex.r + dr
        const neighbor = byCoord.get(`${nq}:${nr}`)
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

  // Draws the previewed travel route as a dashed amber polyline through the
  // hex centers of `this.pathPreview.hexes`. Drawn above terrain/roads but
  // below location markers.
  renderPathPreview(lineWidth) {
    const hexes = this.pathPreview?.hexes
    if (!hexes || hexes.length < 2) return

    const ctx = this.ctx
    const size = this.hexSize()

    ctx.save()
    ctx.setLineDash([10 / this.scale, 8 / this.scale])
    ctx.strokeStyle = "rgba(245, 158, 11, 0.9)"
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    ctx.beginPath()
    hexes.forEach(([q, r], index) => {
      const { x, y } = axialToPixel(q, r, size)
      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })
    ctx.stroke()
    ctx.restore()
  },

  renderLocations(ctx) {
    ctx.save()
    ctx.translate(this.tx, this.ty)
    ctx.scale(this.scale, this.scale)

    const invScale = 1 / this.scale

    for (const loc of this.locations) {
      const pos = this.locationWorldPos(loc)
      const kind = KIND[loc.kind] || KIND.wilderness
      const isHere = this.player?.location_slug === loc.slug
      const isSelected = this.selected === loc.slug
      const isReachable = loc.can_travel

      ctx.save()
      ctx.translate(pos.x, pos.y)
      ctx.scale(invScale, invScale) // keep markers a constant screen size

      if (this.activeFilter === "political") {
        const ringColor = this.orgOverlayData().rings.get(loc.slug)
        if (ringColor) {
          ctx.beginPath()
          ctx.arc(0, 0, kind.r + 17, 0, Math.PI * 2)
          ctx.strokeStyle = ringColor
          ctx.lineWidth = 4
          ctx.stroke()
        }
      }

      if (isReachable || isHere || isSelected) {
        ctx.beginPath()
        ctx.arc(0, 0, kind.r + 11, 0, Math.PI * 2)
        ctx.strokeStyle = isSelected
          ? "rgba(255, 241, 168, 0.95)"
          : isHere
            ? "rgba(34, 197, 94, 0.75)"
            : "rgba(245, 158, 11, 0.55)"
        ctx.lineWidth = 3
        ctx.stroke()
      }

      ctx.beginPath()
      ctx.arc(0, 0, kind.r, 0, Math.PI * 2)
      ctx.fillStyle = kind.fill
      ctx.fill()
      ctx.lineWidth = 3
      ctx.strokeStyle = kind.stroke
      ctx.stroke()

      ctx.restore()
    }

    const occupiedLabels = []
    const maxLabelWidth = Math.min(160, Math.max(92, this.viewportWidth * 0.36))
    const orderedLocations = [...this.locations].sort((a, b) => {
      const priority = location => {
        if (this.selected === location.slug) return 0
        if (this.player?.location_slug === location.slug) return 1
        if (location.can_travel) return 2
        return 3
      }

      return priority(a) - priority(b)
    })

    for (const loc of orderedLocations) {
      const pos = this.locationWorldPos(loc)
      const kind = KIND[loc.kind] || KIND.wilderness
      const screenX = pos.x * this.scale + this.tx
      const screenY = pos.y * this.scale + this.ty + kind.r + 22

      if (
        screenX < -maxLabelWidth ||
        screenX > this.viewportWidth + maxLabelWidth ||
        screenY < -24 ||
        screenY > this.viewportHeight + 24
      ) {
        continue
      }

      ctx.save()
      ctx.translate(pos.x, pos.y)
      ctx.scale(invScale, invScale)
      ctx.font = "18px var(--font-serif, serif)"
      ctx.textAlign = "center"
      const label = fitCanvasText(ctx, loc.name, maxLabelWidth)
      const labelWidth = Math.min(ctx.measureText(label).width, maxLabelWidth)
      ctx.lineWidth = 4
      ctx.strokeStyle = "#090d0c"
      ctx.fillStyle = "#f2eee8"
      const labelY = kind.r + 22
      const labelBox = {
        left: screenX - labelWidth / 2 - 4,
        right: screenX + labelWidth / 2 + 4,
        top: screenY - 17,
        bottom: screenY + 5,
      }
      const overlaps = occupiedLabels.some(
        box =>
          labelBox.left < box.right &&
          labelBox.right > box.left &&
          labelBox.top < box.bottom &&
          labelBox.bottom > box.top
      )

      if (!overlaps) {
        ctx.strokeText(label, 0, labelY)
        ctx.fillText(label, 0, labelY)
        occupiedLabels.push(labelBox)
      }
      ctx.restore()
    }

    ctx.restore()
  },

  renderLocationMarkersOnly(ctx) {
    ctx.save()
    ctx.translate(this.tx, this.ty)
    ctx.scale(this.scale, this.scale)
    const invScale = 1 / this.scale

    for (const loc of this.locations) {
      const pos = this.locationWorldPos(loc)
      const kind = KIND[loc.kind] || KIND.wilderness
      const isHere = this.player?.location_slug === loc.slug

      ctx.save()
      ctx.translate(pos.x, pos.y)
      ctx.scale(invScale, invScale)

      ctx.beginPath()
      ctx.arc(0, 0, kind.r * 0.7, 0, Math.PI * 2)
      ctx.fillStyle = isHere ? "#22c55e" : kind.fill
      ctx.fill()

      ctx.restore()
    }

    ctx.restore()
  },

  // -- hierarchy tiers -------------------------------------------------------

  // Fills every visible parent cell (level 1 or level 0) with its aggregated
  // terrain color, then strokes cell borders so the hex nesting reads clearly.
  renderCells(cells) {
    if (!cells) return
    const ctx = this.ctx
    const rect = this.viewportWorldRect()
    const size = this.hexSize()
    const radius = size * 8 // generous cull pad covering level-0 outlines

    for (const cell of cells.values()) {
      const center = this.cellCenter(cell)
      if (
        center.x < rect.minX - radius ||
        center.x > rect.maxX + radius ||
        center.y < rect.minY - radius ||
        center.y > rect.maxY + radius
      ) {
        continue
      }

      const terrain = this.terrainsById[cell.terrain]
      ctx.fillStyle = terrain?.color || FALLBACK_TERRAIN_COLOR
      ctx.fill(cell.path)
      ctx.strokeStyle = "rgba(9, 13, 12, 0.55)"
      ctx.lineWidth = 1.5 / this.scale
      ctx.stroke(cell.path)
    }
  },

  // Faint outlines of the next hierarchy level up, drawn over a finer tier —
  // this is what makes the "hexes inside hexes" structure visible.
  renderParentOutlines(cells, lineWidth, alpha) {
    if (!cells) return
    const ctx = this.ctx
    const rect = this.viewportWorldRect()
    const size = this.hexSize()
    const radius = size * 10

    ctx.save()
    ctx.strokeStyle = `rgba(242, 238, 232, ${alpha})`
    ctx.lineWidth = lineWidth

    for (const cell of cells.values()) {
      const center = this.cellCenter(cell)
      if (
        center.x < rect.minX - radius ||
        center.x > rect.maxX + radius ||
        center.y < rect.minY - radius ||
        center.y > rect.maxY + radius
      ) {
        continue
      }
      ctx.stroke(cell.path)
    }

    ctx.restore()
  },

  cellCenter(cell) {
    if (!cell.centerPx) {
      const size = this.hexSize()
      if ("i" in cell) {
        const corners = outlineL1(cell.i, cell.j, size)
        cell.centerPx = polygonCenter(corners)
      } else {
        const corners = outlineL0(cell.m, cell.n, size)
        cell.centerPx = polygonCenter(corners)
      }
    }
    return cell.centerPx
  },

  // Road strokes between adjacent level-1 cells that both carry roads.
  renderL1Roads(lineWidth) {
    if (!this.l1Cells) return
    const ctx = this.ctx

    ctx.strokeStyle = "rgba(218, 194, 133, 0.7)"
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"

    for (const cell of this.l1Cells.values()) {
      if (!cell.road) continue
      const from = this.cellCenter(cell)

      for (const [di, dj] of [
        [1, 0],
        [1, -1],
        [0, -1],
      ]) {
        const neighbor = this.l1Cells.get(`${cell.i + di},${cell.j + dj}`)
        if (!neighbor || !neighbor.road) continue

        const to = this.cellCenter(neighbor)
        ctx.beginPath()
        ctx.moveTo(from.x, from.y)
        ctx.lineTo(to.x, to.y)
        ctx.stroke()
      }
    }
  },

  // -- political filter -------------------------------------------------------

  renderPoliticalFine() {
    if (this.activeFilter !== "political") return
    const overlay = this.orgOverlayData()
    const ctx = this.ctx
    const size = this.hexSize()

    for (const { q, r, color } of overlay.fine) {
      const { x, y } = axialToPixel(q, r, size)
      const corners = hexPolygonPoints(x, y, size)
      ctx.beginPath()
      ctx.moveTo(corners[0][0], corners[0][1])
      for (let i = 1; i < corners.length; i++) ctx.lineTo(corners[i][0], corners[i][1])
      ctx.closePath()
      ctx.fillStyle = withAlpha(color, 0.35)
      ctx.fill()
      ctx.strokeStyle = withAlpha(color, 0.9)
      ctx.lineWidth = 2.5 / this.scale
      ctx.stroke()
    }
  },

  renderPoliticalCells(cells, level) {
    if (this.activeFilter !== "political" || !cells) return
    const overlay = this.orgOverlayData()
    const tinted = level === "l1" ? overlay.l1 : overlay.l0
    const ctx = this.ctx

    for (const [key, color] of tinted) {
      const cell = cells.get(key)
      if (!cell) continue
      ctx.fillStyle = withAlpha(color, 0.35)
      ctx.fill(cell.path)
      ctx.strokeStyle = withAlpha(color, 0.9)
      ctx.lineWidth = 2.5 / this.scale
      ctx.stroke(cell.path)
    }
  },

  // Infrastructure is distinct from political control: it draws the actual
  // organization-linked network between locations. Each organization is a
  // small spanning tree rooted at its first linked location, which keeps the
  // map legible even when a network has many destinations.
  renderInfrastructure() {
    if (this.activeFilter !== "infrastructure") return

    const locationsBySlug = new Map(this.locations.map(location => [location.slug, location]))
    const ctx = this.ctx

    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.setLineDash([12 / this.scale, 9 / this.scale])

    for (const org of this.orgs) {
      const nodes = (org.location_slugs || [])
        .map(slug => locationsBySlug.get(slug))
        .filter(Boolean)
        .map(location => ({ slug: location.slug, pos: this.locationWorldPos(location) }))

      if (nodes.length === 0) continue

      ctx.strokeStyle = withAlpha(org.color, 0.88)
      ctx.fillStyle = withAlpha(org.color, 0.36)
      ctx.lineWidth = 5 / this.scale

      const root = nodes[0]

      for (const node of nodes.slice(1)) {
        ctx.beginPath()
        ctx.moveTo(root.pos.x, root.pos.y)
        ctx.lineTo(node.pos.x, node.pos.y)
        ctx.stroke()
      }

      for (const node of nodes) {
        ctx.beginPath()
        ctx.arc(node.pos.x, node.pos.y, 13 / this.scale, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    ctx.restore()
  },

  // Economic activity reflects real, recent organization-ledger movements at
  // linked locations. The payload contains a tier only—not a balance or a
  // transaction amount—so collective finances stay private on the world map.
  renderEconomic() {
    if (this.activeFilter !== "economic" || this.economic.length === 0) return

    const locationsBySlug = new Map(this.locations.map(location => [location.slug, location]))
    const organizationsById = new Map(this.orgs.map(org => [org.id, org]))
    const ctx = this.ctx

    ctx.save()

    for (const activity of this.economic) {
      const org = organizationsById.get(activity.organization_id)
      const color = org?.color || "#e6bb58"
      const tier = clamp(Number(activity.activity_level) || 1, 1, 4)
      const radius = (8 + tier * 4) / this.scale

      for (const slug of activity.location_slugs || []) {
        const location = locationsBySlug.get(slug)
        if (!location) continue

        const position = this.locationWorldPos(location)

        ctx.fillStyle = withAlpha(color, 0.22 + tier * 0.07)
        ctx.strokeStyle = withAlpha(color, 0.9)
        ctx.lineWidth = 2.5 / this.scale

        ctx.beginPath()
        ctx.arc(position.x, position.y, radius, 0, Math.PI * 2)
        ctx.fill()
        ctx.stroke()

        ctx.beginPath()
        ctx.arc(position.x, position.y, radius + 6 / this.scale, 0, Math.PI * 2)
        ctx.strokeStyle = withAlpha(color, 0.42)
        ctx.lineWidth = 1.25 / this.scale
        ctx.stroke()
      }
    }

    ctx.restore()
  },

  // Diplomatic overlays are drawn only after both organizations have stored a
  // reciprocal relationship. Each line joins the real linked-location network
  // centers, so an organization with no visible infrastructure cannot claim a
  // made-up territorial link on the client.
  renderDiplomacy() {
    if (this.activeFilter !== "diplomacy" || this.diplomacy.length === 0) return

    const locationsBySlug = new Map(this.locations.map(location => [location.slug, location]))
    const organizationsById = new Map(this.orgs.map(organization => [organization.id, organization]))
    const ctx = this.ctx

    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    for (const relationship of this.diplomacy) {
      const source = organizationsById.get(relationship.source_organization_id)
      const target = organizationsById.get(relationship.target_organization_id)
      const sourceAnchor = this.organizationAnchor(source, locationsBySlug)
      const targetAnchor = this.organizationAnchor(target, locationsBySlug)

      if (!sourceAnchor || !targetAnchor) continue

      const alliance = relationship.kind === "alliance"
      const war = relationship.kind === "war"
      const color = alliance ? "#69d3ff" : war ? "#ffae45" : "#ef6767"

      ctx.strokeStyle = withAlpha(color, 0.9)
      ctx.fillStyle = withAlpha(color, 0.36)
      ctx.lineWidth = 5 / this.scale
      ctx.setLineDash(
        alliance ? [18 / this.scale, 9 / this.scale] : war ? [] : [5 / this.scale, 9 / this.scale]
      )

      ctx.beginPath()
      ctx.moveTo(sourceAnchor.x, sourceAnchor.y)
      ctx.lineTo(targetAnchor.x, targetAnchor.y)
      ctx.stroke()

      for (const anchor of [sourceAnchor, targetAnchor]) {
        ctx.beginPath()
        ctx.arc(anchor.x, anchor.y, 11 / this.scale, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    ctx.restore()
  },

  organizationAnchor(organization, locationsBySlug) {
    if (!organization) return null

    const nodes = (organization.location_slugs || [])
      .map(slug => locationsBySlug.get(slug))
      .filter(Boolean)

    if (nodes.length === 0) return null

    return nodes
      .map(location => this.locationWorldPos(location))
      .reduce(
        (center, position) => ({ x: center.x + position.x / nodes.length, y: center.y + position.y / nodes.length }),
        { x: 0, y: 0 }
      )
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

function economicActivityLabel(level) {
  if (level >= 4) return "узел"
  if (level >= 3) return "центр"
  if (level >= 2) return "оживление"
  return "след"
}

function fitCanvasText(ctx, value, maxWidth) {
  const text = String(value || "")
  if (ctx.measureText(text).width <= maxWidth) return text

  let shortened = text
  while (shortened.length > 1 && ctx.measureText(`${shortened}…`).width > maxWidth) {
    shortened = shortened.slice(0, -1)
  }

  return `${shortened.trimEnd()}…`
}

function majorityKey(counts) {
  let best = null
  let bestCount = -1
  for (const [key, count] of counts) {
    if (count > bestCount) {
      best = key
      bestCount = count
    }
  }
  return best
}

function polygonPath(corners) {
  const path = new Path2D()
  path.moveTo(corners[0].x, corners[0].y)
  for (let i = 1; i < corners.length; i++) path.lineTo(corners[i].x, corners[i].y)
  path.closePath()
  return path
}

function polygonCenter(corners) {
  let x = 0
  let y = 0
  for (const corner of corners) {
    x += corner.x
    y += corner.y
  }
  return { x: x / corners.length, y: y / corners.length }
}

// "#rrggbb" -> "rgba(r, g, b, alpha)"
function withAlpha(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

function escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text
  return div.innerHTML
}
