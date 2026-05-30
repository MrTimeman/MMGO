// MapHook — lightweight pan/zoom world map, no external library
//
// Server pushes:
//   map_state  %{locations: [...], player: %{location_slug, x, y}, others: [...]}
//   map_player_move  %{x, y, location_slug}
//
// Client pushes:
//   location_clicked  %{slug}

const MAP_W = 2000
const MAP_H = 2000
const MIN_SCALE = 0.25
const MAX_SCALE = 2.5
const MOBILE_INITIAL_SCALE = 0.38

const KIND_ICON = {
  city:             { symbol: "⬡", color: "#f59e0b", size: 22, labelOffset: 16 },
  tower:            { symbol: "▲", color: "#a78bfa", size: 20, labelOffset: 15 },
  wilderness:       { symbol: "◆", color: "#4ade80", size: 14, labelOffset: 12 },
  dungeon_entrance: { symbol: "☽", color: "#f87171", size: 18, labelOffset: 14 },
  base:             { symbol: "⌂", color: "#94a3b8", size: 16, labelOffset: 13 },
}

export const MapHook = {
  mounted() {
    this._locations = []
    this._player   = null
    this._others   = []
    this._selected = null

    this._buildDOM()
    this._initTransform()
    this._bindPointer()
    this._bindWheel()

    this.handleEvent("map_state", (payload) => {
      this._locations = payload.locations || []
      this._player    = payload.player    || null
      this._others    = payload.others    || []
      this._render()
    })

    this.handleEvent("map_player_move", (payload) => {
      this._player = { ...this._player, ...payload }
      this._renderPlayers()
    })
  },

  destroyed() {
    this._pointerCleanup?.()
  },

  // ── DOM structure ──────────────────────────────────────────────────────────

  _buildDOM() {
    const root = this.el
    root.style.cssText = "position:relative;overflow:hidden;background:#0c1a10;touch-action:none;user-select:none"

    const viewport = document.createElement("div")
    viewport.style.cssText = "position:absolute;inset:0;overflow:hidden"
    this._viewport = viewport

    const stage = document.createElement("div")
    stage.style.cssText = "position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform"
    this._stage = stage

    const img = document.createElement("img")
    img.src = "/images/world_map.png"
    img.style.cssText = `width:${MAP_W}px;height:${MAP_H}px;display:block;pointer-events:none;image-rendering:auto`
    img.draggable = false
    this._img = img

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("viewBox", `0 0 ${MAP_W} ${MAP_H}`)
    svg.style.cssText = `position:absolute;top:0;left:0;width:${MAP_W}px;height:${MAP_H}px;overflow:visible;pointer-events:none`
    this._svg = svg

    stage.appendChild(img)
    stage.appendChild(svg)
    viewport.appendChild(stage)
    root.appendChild(viewport)

    // Info panel
    const panel = document.createElement("div")
    panel.style.cssText = `
      position:absolute;bottom:0;left:0;right:0;
      background:rgba(12,10,9,0.96);border-top:1px solid #44403c;
      padding:1rem;font-family:'PT Serif',serif;color:#e7e5e4;
      transform:translateY(100%);transition:transform 0.25s ease;
      z-index:10;max-height:50%;overflow-y:auto
    `
    panel.id = "map-panel"
    this._panel = panel
    root.appendChild(panel)
  },

  // ── Transform state ────────────────────────────────────────────────────────

  _initTransform() {
    const rw = this.el.clientWidth  || 390
    const rh = this.el.clientHeight || 600
    const s  = Math.min(MOBILE_INITIAL_SCALE, rw / MAP_W, rh / MAP_H)
    this._scale = s
    this._tx    = (rw - MAP_W * s) / 2
    this._ty    = (rh - MAP_H * s) / 2
    this._applyTransform()
  },

  _applyTransform() {
    this._stage.style.transform = `translate(${this._tx}px,${this._ty}px) scale(${this._scale})`
  },

  _clampTranslation() {
    const rw = this.el.clientWidth  || 390
    const rh = this.el.clientHeight || 600
    const sw = MAP_W * this._scale
    const sh = MAP_H * this._scale
    const marginX = Math.min(0.3 * rw, 0.3 * sw)
    const marginY = Math.min(0.3 * rh, 0.3 * sh)
    this._tx = Math.min(marginX, Math.max(this._tx, rw - sw - marginX))
    this._ty = Math.min(marginY, Math.max(this._ty, rh - sh - marginY))
  },

  // ── Pointer / touch input ──────────────────────────────────────────────────

  _bindPointer() {
    const el = this.el
    let dragging = false
    let lastX, lastY, startX, startY, startTime
    let pinchDist = null

    const dist = (t) =>
      Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY)

    const onDown = (e) => {
      if (e.touches?.length === 2) {
        pinchDist = dist(e.touches)
        return
      }
      dragging  = true
      lastX     = e.touches ? e.touches[0].clientX : e.clientX
      lastY     = e.touches ? e.touches[0].clientY : e.clientY
      startX    = lastX
      startY    = lastY
      startTime = Date.now()
    }

    const onMove = (e) => {
      if (e.touches?.length === 2 && pinchDist !== null) {
        const d   = dist(e.touches)
        const cx  = (e.touches[0].clientX + e.touches[1].clientX) / 2
        const cy  = (e.touches[0].clientY + e.touches[1].clientY) / 2
        this._zoom(d / pinchDist, cx, cy)
        pinchDist = d
        return
      }
      if (!dragging) return
      const cx = e.touches ? e.touches[0].clientX : e.clientX
      const cy = e.touches ? e.touches[0].clientY : e.clientY
      this._tx += cx - lastX
      this._ty += cy - lastY
      lastX = cx
      lastY = cy
      this._clampTranslation()
      this._applyTransform()
    }

    const onUp = (e) => {
      if (!dragging) { pinchDist = null; return }
      const cx = e.changedTouches ? e.changedTouches[0].clientX : e.clientX
      const cy = e.changedTouches ? e.changedTouches[0].clientY : e.clientY
      const dx = cx - startX
      const dy = cy - startY
      const dt = Date.now() - startTime
      dragging  = false
      pinchDist = null
      if (Math.hypot(dx, dy) < 8 && dt < 300) this._handleTap(cx, cy)
    }

    el.addEventListener("mousedown",  onDown,  { passive: true })
    el.addEventListener("mousemove",  onMove,  { passive: true })
    el.addEventListener("mouseup",    onUp)
    el.addEventListener("touchstart", onDown,  { passive: true })
    el.addEventListener("touchmove",  onMove,  { passive: false })
    el.addEventListener("touchend",   onUp)

    this._pointerCleanup = () => {
      el.removeEventListener("mousedown",  onDown)
      el.removeEventListener("mousemove",  onMove)
      el.removeEventListener("mouseup",    onUp)
      el.removeEventListener("touchstart", onDown)
      el.removeEventListener("touchmove",  onMove)
      el.removeEventListener("touchend",   onUp)
    }
  },

  _bindWheel() {
    this.el.addEventListener("wheel", (e) => {
      e.preventDefault()
      this._zoom(e.deltaY < 0 ? 1.1 : 0.9, e.clientX, e.clientY)
    }, { passive: false })
  },

  _zoom(factor, cx, cy) {
    const rect  = this.el.getBoundingClientRect()
    const newS  = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this._scale * factor))
    const ratio = newS / this._scale
    this._tx    = cx - rect.left - ratio * (cx - rect.left - this._tx)
    this._ty    = cy - rect.top  - ratio * (cy - rect.top  - this._ty)
    this._scale = newS
    this._clampTranslation()
    this._applyTransform()
  },

  // ── Tap / click handling ───────────────────────────────────────────────────

  _handleTap(screenX, screenY) {
    const rect = this.el.getBoundingClientRect()
    const mapX = (screenX - rect.left - this._tx) / this._scale
    const mapY = (screenY - rect.top  - this._ty) / this._scale

    const hit = this._locations.find((loc) => {
      const dx = mapX - loc.x
      const dy = mapY - loc.y
      return Math.hypot(dx, dy) < 40
    })

    if (hit) {
      this._selectLocation(hit)
    } else {
      this._closePanel()
    }
  },

  _selectLocation(loc) {
    this._selected = loc.slug
    this._renderLocations()

    const others = this._others.filter((o) => o.location_slug === loc.slug)
    const isHere = this._player?.location_slug === loc.slug

    const kindLabel = {
      city:             "Город",
      tower:            "Башня",
      wilderness:       "Дикая местность",
      dungeon_entrance: "Вход в подземелье",
      base:             "База",
    }[loc.kind] || loc.kind

    const safeTag = loc.safe_zone
      ? `<span style="color:#22c55e;font-size:0.75rem">● Безопасная зона</span>`
      : `<span style="color:#ef4444;font-size:0.75rem">● PvP зона</span>`

    const othersHtml = others.length
      ? `<div style="margin-top:0.75rem;font-size:0.85rem;color:#a8a29e">
           Здесь: ${others.map((o) => `<span style="color:#f59e0b">${o.name}</span>`).join(", ")}
         </div>`
      : ""

    const travelBtn = (!isHere)
      ? `<button onclick="this.closest('[id]').__hook.travelTo('${loc.slug}')"
           style="margin-top:1rem;width:100%;padding:0.6rem;background:#78350f;color:#fef3c7;
                  border:1px solid #f59e0b;border-radius:0.375rem;font-family:inherit;
                  font-size:0.9rem;cursor:pointer">
           Отправиться →
         </button>`
      : `<div style="margin-top:1rem;font-size:0.85rem;color:#22c55e">Вы здесь</div>`

    this._panel.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:0.5rem">
        <div>
          <div style="font-size:1.1rem;font-weight:700;color:#f59e0b">${loc.name}</div>
          <div style="font-size:0.8rem;color:#a8a29e;margin-top:0.15rem">${kindLabel}</div>
        </div>
        ${safeTag}
      </div>
      ${loc.description ? `<div style="font-size:0.85rem;color:#d4d0cc;line-height:1.5">${loc.description}</div>` : ""}
      ${othersHtml}
      ${travelBtn}
    `
    // attach hook ref for button callback
    this._panel.id = "map-panel"
    this._panel.__hook = this
    this._panel.style.transform = "translateY(0)"
  },

  travelTo(slug) {
    this.pushEvent("location_clicked", { slug })
    this._closePanel()
  },

  _closePanel() {
    this._selected = null
    this._panel.style.transform = "translateY(100%)"
    this._renderLocations()
  },

  // ── Rendering ──────────────────────────────────────────────────────────────

  _render() {
    this._renderLocations()
    this._renderPlayers()
  },

  _renderLocations() {
    while (this._svg.firstChild) this._svg.removeChild(this._svg.firstChild)

    // Route lines first (below nodes)
    const routes = this._locations.flatMap((loc) =>
      (loc.routes || []).map((r) => ({ from: loc, toSlug: r.destination_slug, risk: r.risk_level }))
    )
    const drawn = new Set()
    routes.forEach(({ from, toSlug, risk }) => {
      const to = this._locations.find((l) => l.slug === toSlug)
      if (!to) return
      const key = [from.slug, toSlug].sort().join("|")
      if (drawn.has(key)) return
      drawn.add(key)
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      line.setAttribute("x1", from.x); line.setAttribute("y1", from.y)
      line.setAttribute("x2", to.x);   line.setAttribute("y2", to.y)
      line.setAttribute("stroke", risk > 50 ? "#7f1d1d" : "#44403c")
      line.setAttribute("stroke-width", "3")
      line.setAttribute("stroke-dasharray", "12 8")
      line.setAttribute("opacity", "0.6")
      this._svg.appendChild(line)
    })

    // Location nodes
    this._locations.forEach((loc) => {
      const cfg      = KIND_ICON[loc.kind] || KIND_ICON.wilderness
      const selected = loc.slug === this._selected
      const isHere   = this._player?.location_slug === loc.slug

      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      g.style.cursor = "pointer"
      g.style.pointerEvents = "all"

      // Glow ring if selected or player is here
      if (selected || isHere) {
        const glow = document.createElementNS("http://www.w3.org/2000/svg", "circle")
        glow.setAttribute("cx", loc.x)
        glow.setAttribute("cy", loc.y)
        glow.setAttribute("r", cfg.size + 8)
        glow.setAttribute("fill", "none")
        glow.setAttribute("stroke", selected ? "#f59e0b" : "#22c55e")
        glow.setAttribute("stroke-width", "2")
        glow.setAttribute("opacity", "0.7")
        g.appendChild(glow)
      }

      // Background circle
      const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      circle.setAttribute("cx", loc.x)
      circle.setAttribute("cy", loc.y)
      circle.setAttribute("r", cfg.size)
      circle.setAttribute("fill", "rgba(12,10,9,0.8)")
      circle.setAttribute("stroke", cfg.color)
      circle.setAttribute("stroke-width", selected ? "3" : "2")
      g.appendChild(circle)

      // Icon text
      const icon = document.createElementNS("http://www.w3.org/2000/svg", "text")
      icon.setAttribute("x", loc.x)
      icon.setAttribute("y", loc.y)
      icon.setAttribute("text-anchor", "middle")
      icon.setAttribute("dominant-baseline", "central")
      icon.setAttribute("font-size", Math.floor(cfg.size * 0.9))
      icon.setAttribute("fill", cfg.color)
      icon.textContent = cfg.symbol
      g.appendChild(icon)

      // Label
      const label = document.createElementNS("http://www.w3.org/2000/svg", "text")
      label.setAttribute("x", loc.x)
      label.setAttribute("y", loc.y + cfg.size + cfg.labelOffset)
      label.setAttribute("text-anchor", "middle")
      label.setAttribute("font-size", "18")
      label.setAttribute("font-family", "'PT Serif', serif")
      label.setAttribute("fill", "#e7e5e4")
      label.setAttribute("paint-order", "stroke")
      label.setAttribute("stroke", "#0c0a09")
      label.setAttribute("stroke-width", "5")
      label.setAttribute("stroke-linejoin", "round")
      label.textContent = loc.name
      g.appendChild(label)

      this._svg.appendChild(g)
    })
  },

  _renderPlayers() {
    // Remove old player layers
    this._svg.querySelectorAll("[data-players]").forEach((el) => el.remove())

    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-players", "1")

    // Other players
    this._others.forEach((other) => {
      const loc = this._locations.find((l) => l.slug === other.location_slug)
      if (!loc) return
      const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      dot.setAttribute("cx", loc.x + (Math.random() * 20 - 10))
      dot.setAttribute("cy", loc.y - 30 + (Math.random() * 10 - 5))
      dot.setAttribute("r", "7")
      dot.setAttribute("fill", "#60a5fa")
      dot.setAttribute("stroke", "#1e3a5f")
      dot.setAttribute("stroke-width", "2")
      g.appendChild(dot)
    })

    // Current player
    if (this._player) {
      const loc = this._locations.find((l) => l.slug === this._player.location_slug)
      if (loc) {
        const pulse = document.createElementNS("http://www.w3.org/2000/svg", "circle")
        pulse.setAttribute("cx", loc.x)
        pulse.setAttribute("cy", loc.y - 34)
        pulse.setAttribute("r", "12")
        pulse.setAttribute("fill", "none")
        pulse.setAttribute("stroke", "#22c55e")
        pulse.setAttribute("stroke-width", "2")
        pulse.setAttribute("opacity", "0.5")
        g.appendChild(pulse)

        const player = document.createElementNS("http://www.w3.org/2000/svg", "circle")
        player.setAttribute("cx", loc.x)
        player.setAttribute("cy", loc.y - 34)
        player.setAttribute("r", "9")
        player.setAttribute("fill", "#22c55e")
        player.setAttribute("stroke", "#14532d")
        player.setAttribute("stroke-width", "2")
        g.appendChild(player)
      }
    }

    this._svg.appendChild(g)
  },
}
