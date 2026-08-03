const MAP_W = 2000
const MAP_H = 2000
const BASE_MAP_URL = "/images/placeholder_world_map.png"

const KIND = {
  city: { r: 16, fill: "#d6a643", stroke: "#fff1a8" },
  tower: { r: 18, fill: "#7c6df2", stroke: "#d8d1ff" },
  wilderness: { r: 12, fill: "#4f8f5b", stroke: "#b7efbf" },
  dungeon_entrance: { r: 15, fill: "#b94c4c", stroke: "#ffd0d0" },
  base: { r: 14, fill: "#8c9bad", stroke: "#e1e8f0" },
}

const KIND_LABELS = {
  city: "город",
  tower: "башня",
  wilderness: "дикая местность",
  dungeon_entrance: "вход в подземелье",
  base: "убежище",
}

export const PlayMapHook = {
  mounted() {
    this.locations = []
    this.player = null
    this.selected = null
    this.scale = 1
    this.tx = 0
    this.ty = 0

    this.build()
    this.bindInput()

    this.handleEvent("map_state", payload => {
      this.locations = payload.locations || []
      this.player = payload.player || null
      this.selected = null
      this.fit()
      this.render()
    })
  },

  destroyed() {
    this.cleanup?.()
  },

  build() {
    this.el.classList.add("play-map")
    this.el.innerHTML = `
      <div class="play-map__stage">
        <svg class="play-map__svg" viewBox="0 0 ${MAP_W} ${MAP_H}" aria-hidden="true"></svg>
      </div>
      <section class="play-map__sheet" hidden></section>
    `
    this.stage = this.el.querySelector(".play-map__stage")
    this.svg = this.el.querySelector(".play-map__svg")
    this.sheet = this.el.querySelector(".play-map__sheet")
  },

  fit() {
    const w = this.el.clientWidth || 390
    const h = this.el.clientHeight || 700
    const base = Math.min(w / MAP_W, h / MAP_H) * 1.18
    this.scale = Math.max(base, 0.34)
    this.tx = (w - MAP_W * this.scale) / 2
    this.ty = (h - MAP_H * this.scale) / 2
    this.applyTransform()
  },

  applyTransform() {
    this.stage.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
  },

  bindInput() {
    let dragging = false
    let sx = 0
    let sy = 0
    let lx = 0
    let ly = 0

    const point = event => {
      const touch = event.touches?.[0] || event.changedTouches?.[0]
      return touch || event
    }

    const down = event => {
      const p = point(event)
      dragging = true
      sx = lx = p.clientX
      sy = ly = p.clientY
    }

    const move = event => {
      if (!dragging) return
      const p = point(event)
      this.tx += p.clientX - lx
      this.ty += p.clientY - ly
      lx = p.clientX
      ly = p.clientY
      this.applyTransform()
    }

    const up = event => {
      if (!dragging) return
      const p = point(event)
      dragging = false
      if (Math.hypot(p.clientX - sx, p.clientY - sy) < 8) this.tap(p.clientX, p.clientY)
    }

    this.el.addEventListener("pointerdown", down)
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", up)

    this.cleanup = () => {
      this.el.removeEventListener("pointerdown", down)
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", up)
    }
  },

  tap(clientX, clientY) {
    const rect = this.el.getBoundingClientRect()
    const x = (clientX - rect.left - this.tx) / this.scale
    const y = (clientY - rect.top - this.ty) / this.scale
    const hit = this.locations.find(loc => Math.hypot(loc.x - x, loc.y - y) < 44)

    if (!hit) {
      this.selected = null
      this.closeSheet()
      this.render()
      return
    }

    this.selected = hit.slug
    this.openSheet(hit)
    this.render()
  },

  openSheet(loc) {
    const safety = loc.safe_zone ? "Безопасная зона" : "Опасная местность"
    const kind = KIND_LABELS[loc.kind] || "место"
    const action = loc.can_travel
      ? `<button class="play-map__travel" data-travel="${loc.slug}">Отправиться</button>`
      : this.player?.location_slug === loc.slug
        ? `<span class="play-map__here">Вы здесь</span>`
        : `<span class="play-map__muted">Нет прямого пути</span>`

    this.sheet.hidden = false
    this.sheet.innerHTML = `
      <div>
        <h2>${loc.name}</h2>
        <p>${safety} · ${kind}</p>
      </div>
      ${action}
    `

    const button = this.sheet.querySelector("[data-travel]")
    if (button) {
      button.addEventListener("click", () => {
        this.pushEvent("location_clicked", { slug: loc.slug })
        this.closeSheet()
      }, { once: true })
    }
  },

  closeSheet() {
    this.sheet.hidden = true
    this.sheet.innerHTML = ""
  },

  render() {
    const routeKeys = new Set()
    const lines = []

    for (const loc of this.locations) {
      for (const route of loc.routes || []) {
        const to = this.locations.find(item => item.slug === route.destination_slug)
        if (!to) continue
        const key = [loc.slug, to.slug].sort().join(":")
        if (routeKeys.has(key)) continue
        routeKeys.add(key)
        lines.push(`<line class="play-map__route ${route.risk_level >= 50 ? "is-risky" : ""}" x1="${loc.x}" y1="${loc.y}" x2="${to.x}" y2="${to.y}" />`)
      }
    }

    const nodes = this.locations.map(loc => {
      const kind = KIND[loc.kind] || KIND.wilderness
      const selected = this.selected === loc.slug ? " is-selected" : ""
      const here = this.player?.location_slug === loc.slug ? " is-here" : ""
      const reachable = loc.can_travel ? " is-reachable" : ""
      return `
        <g class="play-map__node${selected}${here}${reachable}" data-slug="${loc.slug}">
          <circle cx="${loc.x}" cy="${loc.y}" r="${kind.r + 11}" class="play-map__halo" />
          <circle cx="${loc.x}" cy="${loc.y}" r="${kind.r}" fill="${kind.fill}" stroke="${kind.stroke}" />
          <text x="${loc.x}" y="${loc.y + kind.r + 26}">${loc.name}</text>
        </g>
      `
    }).join("")

    this.svg.innerHTML = `
      <defs>
        <filter id="play-map-glow">
          <feGaussianBlur stdDeviation="8" result="blur" />
          <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
        </filter>
      </defs>
      <image class="play-map__base" href="${BASE_MAP_URL}" x="0" y="0" width="${MAP_W}" height="${MAP_H}" preserveAspectRatio="xMidYMid slice" />
      <rect class="play-map__shade" width="${MAP_W}" height="${MAP_H}" />
      <g>${lines.join("")}</g>
      <g>${nodes}</g>
    `
  },
}
