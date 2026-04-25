const ROAD_PATHS = [
  { a: "capital", b: "tower", pts: [[46.0, 46.5], [46.5, 40], [46.8, 32], [45.2, 25], [44.5, 21.0]] },
  { a: "capital", b: "lake-village", pts: [[46.0, 46.5], [48, 51], [51, 56], [55.5, 61.0]] },
  { a: "lake-village", b: "farmstead", pts: [[55.5, 61.0], [53, 71], [50, 80], [48.0, 89.0]] },
  { a: "capital", b: "east-town", pts: [[46.0, 46.5], [52, 42], [60, 36], [68, 30], [77.0, 25.5]] },
  { a: "east-town", b: "kamen", pts: [[77.0, 25.5], [81, 30], [85, 34], [88.0, 37.0]] },
  { a: "capital", b: "windmill", pts: [[46.0, 46.5], [55, 47], [62, 48.5], [69.5, 49.5]] },
  { a: "windmill", b: "east-farms", pts: [[69.5, 49.5], [75, 51], [79, 53], [83.5, 55.0]] },
  { a: "lake-village", b: "windmill", pts: [[55.5, 61.0], [61, 56], [65, 53], [69.5, 49.5]] },
  { a: "tower", b: "hermitage", pts: [[44.5, 21.0], [38, 27], [32, 32], [26, 37], [21.5, 40.5]], dashed: true },
]

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))

const parseLocations = el => {
  try {
    return JSON.parse(el.dataset.locations || "[]")
  } catch (_error) {
    return []
  }
}

const dom = (tag, className, attrs = {}) => {
  const node = document.createElement(tag)
  if (className) node.className = className

  Object.entries(attrs).forEach(([key, value]) => {
    if (key === "text") node.textContent = value
    else if (key === "html") node.innerHTML = value
    else if (key === "style") Object.assign(node.style, value)
    else node.setAttribute(key, value)
  })

  return node
}

const svgPath = pts => {
  if (pts.length < 2) return ""

  let d = `M ${pts[0][0]} ${pts[0][1]}`
  for (let i = 1; i < pts.length - 1; i += 1) {
    const xc = (pts[i][0] + pts[i + 1][0]) / 2
    const yc = (pts[i][1] + pts[i + 1][1]) / 2
    d += ` Q ${pts[i][0]} ${pts[i][1]} ${xc} ${yc}`
  }
  d += ` T ${pts[pts.length - 1][0]} ${pts[pts.length - 1][1]}`
  return d
}

const samplePath = (pts, t) => {
  const lengths = []
  let total = 0

  for (let i = 0; i < pts.length - 1; i += 1) {
    const length = Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
    lengths.push(length)
    total += length
  }

  let travelled = 0
  const target = t * total

  for (let i = 0; i < lengths.length; i += 1) {
    if (travelled + lengths[i] >= target) {
      const local = (target - travelled) / lengths[i]
      return {
        x: pts[i][0] + (pts[i + 1][0] - pts[i][0]) * local,
        y: pts[i][1] + (pts[i + 1][1] - pts[i][1]) * local,
      }
    }
    travelled += lengths[i]
  }

  const last = pts[pts.length - 1]
  return { x: last[0], y: last[1] }
}

const routeKey = (a, b) => `${a}:${b}`

export const MapHook = {
  mounted() {
    this.locations = parseLocations(this.el)
    this.locationById = Object.fromEntries(this.locations.map(location => [location.id, location]))
    this.currentLocationId = "farmstead"
    this.selectedLocationId = null
    this.scale = 1
    this.pan = { x: 0, y: 0 }
    this.isNight = false
    this.drag = null
    this.travel = null
    this.animationFrame = null

    this.render()
    this.bindControls()
    this.centerOn(this.currentLocationId, { scale: 1.18 })
    window.requestAnimationFrame(() => this.el.classList.add("is-ready"))
  },

  destroyed() {
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    if (this.animationFrame) window.cancelAnimationFrame(this.animationFrame)
  },

  render() {
    this.el.className = `${this.el.className} mmgo-map-hook`
    this.el.innerHTML = ""

    this.viewport = dom("div", "mmgo-map-viewport", { role: "application", "aria-label": "Интерактивная карта MMGO" })
    this.stage = dom("div", "mmgo-map-stage")
    this.image = dom("img", "mmgo-map-image", {
      src: this.el.dataset.mapSrc || "/images/mmgo2-map.png",
      alt: "",
      draggable: "false",
    })
    this.routeLayer = dom("svg", "mmgo-map-routes", { viewBox: "0 0 100 100", preserveAspectRatio: "none" })
    this.highlightLayer = dom("svg", "mmgo-map-highlight", { viewBox: "0 0 100 100", preserveAspectRatio: "none" })
    this.markerLayer = dom("div", "mmgo-map-markers")
    this.ambientLayer = dom("div", "mmgo-map-ambient")
    this.player = dom("div", "mmgo-map-player", { text: "◆" })

    this.stage.append(this.image, this.routeLayer, this.highlightLayer, this.markerLayer, this.player, this.ambientLayer)
    this.viewport.append(this.stage)

    this.header = dom("div", "mmgo-map-header")
    this.header.append(
      dom("div", null, {
        html: `
          <p class="mmgo-map-kicker">Карта княжества</p>
          <h2>Дорога в Морвель</h2>
        `,
      }),
      this.headerControls()
    )

    this.infoPanel = dom("aside", "mmgo-map-info", { id: "map-location-drawer" })
    this.toast = dom("div", "mmgo-map-toast")

    this.el.append(this.viewport, this.header, this.infoPanel, this.toast)
    this.drawRoads()
    this.drawMarkers()
    this.movePlayerTo(this.locationById[this.currentLocationId])
  },

  headerControls() {
    const controls = dom("div", "mmgo-map-controls")

    this.zoomOutButton = dom("button", "mmgo-map-control", { id: "map-zoom-out", type: "button", text: "−", "aria-label": "Отдалить карту" })
    this.zoomInButton = dom("button", "mmgo-map-control", { id: "map-zoom-in", type: "button", text: "+", "aria-label": "Приблизить карту" })
    this.recenterButton = dom("button", "mmgo-map-control", { id: "map-recenter", type: "button", text: "◎", "aria-label": "Вернуть карту к персонажу" })
    this.nightButton = dom("button", "mmgo-map-control mmgo-map-control--wide", { id: "map-night-toggle", type: "button", text: "☀ День" })

    controls.append(this.zoomOutButton, this.zoomInButton, this.recenterButton, this.nightButton)
    return controls
  },

  drawRoads() {
    this.routeLayer.innerHTML = ""

    ROAD_PATHS.forEach(road => {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
      path.setAttribute("d", svgPath(road.pts))
      path.setAttribute("class", road.dashed ? "mmgo-map-road mmgo-map-road--cult" : "mmgo-map-road")
      this.routeLayer.append(path)
    })
  },

  drawMarkers() {
    this.markerLayer.innerHTML = ""

    this.locations.forEach((location, index) => {
      const marker = dom("button", `mmgo-map-marker mmgo-map-marker--${location.type}`, {
        id: `map-location-${location.id}`,
        type: "button",
        "data-location-id": location.id,
        style: {
          left: `${location.x}%`,
          top: `${location.y}%`,
          animationDelay: `${index * 70}ms`,
        },
      })

      marker.append(
        dom("span", "mmgo-map-marker__pin", { text: location.icon }),
        dom("span", "mmgo-map-marker__label", { text: location.name })
      )

      const chooseMarker = event => {
        event.stopPropagation()
        event.preventDefault()
        this.selectLocation(location.id)
      }

      marker.addEventListener("click", chooseMarker)
      marker.addEventListener("pointerup", chooseMarker)

      this.markerLayer.append(marker)
    })
  },

  bindControls() {
    this.zoomInButton.addEventListener("click", () => this.zoomBy(0.18))
    this.zoomOutButton.addEventListener("click", () => this.zoomBy(-0.18))
    this.recenterButton.addEventListener("click", () => this.centerOn(this.currentLocationId, { scale: 1.18 }))
    this.nightButton.addEventListener("click", () => this.toggleNight())

    this.viewport.addEventListener("wheel", event => {
      event.preventDefault()
      this.zoomBy(event.deltaY > 0 ? -0.08 : 0.08)
    }, { passive: false })

    this.viewport.addEventListener("pointerdown", event => {
      if (event.button !== 0) return
      if (event.target.closest(".mmgo-map-marker, .mmgo-map-info, .mmgo-map-controls")) return
      this.viewport.setPointerCapture(event.pointerId)
      this.drag = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        panX: this.pan.x,
        panY: this.pan.y,
      }
      this.viewport.classList.add("is-dragging")
    })

    this.onPointerMove = event => {
      if (!this.drag || this.drag.pointerId !== event.pointerId) return
      this.pan = {
        x: this.drag.panX + event.clientX - this.drag.startX,
        y: this.drag.panY + event.clientY - this.drag.startY,
      }
      this.applyTransform()
    }

    this.onPointerUp = event => {
      if (!this.drag || this.drag.pointerId !== event.pointerId) return
      this.drag = null
      this.viewport.classList.remove("is-dragging")
    }

    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
  },

  zoomBy(delta) {
    this.scale = clamp(this.scale + delta, 0.92, 1.95)
    this.applyTransform()
  },

  toggleNight() {
    this.isNight = !this.isNight
    this.el.classList.toggle("is-night", this.isNight)
    this.nightButton.textContent = this.isNight ? "☾ Ночь" : "☀ День"
  },

  applyTransform() {
    const maxPan = 220 * this.scale
    this.pan.x = clamp(this.pan.x, -maxPan, maxPan)
    this.pan.y = clamp(this.pan.y, -maxPan, maxPan)
    this.stage.style.transform = `translate3d(${this.pan.x}px, ${this.pan.y}px, 0) scale(${this.scale})`
  },

  centerOn(id, options = {}) {
    const location = this.locationById[id]
    if (!location) return

    const rect = this.viewport.getBoundingClientRect()
    this.scale = options.scale || Math.max(this.scale, 1.14)
    this.pan = {
      x: (50 - location.x) * rect.width * 0.0105,
      y: (50 - location.y) * rect.height * 0.0105,
    }
    this.applyTransform()
  },

  selectLocation(id) {
    const location = this.locationById[id]
    if (!location || this.travel) return

    if (id === this.currentLocationId) {
      this.showLocationEvent(location)
      return
    }

    this.selectedLocationId = id
    this.markerLayer.querySelectorAll(".mmgo-map-marker").forEach(marker => {
      marker.classList.toggle("is-selected", marker.dataset.locationId === id)
      marker.classList.toggle("is-current", marker.dataset.locationId === this.currentLocationId)
    })

    this.centerOn(id)
    this.highlightRoute(this.currentLocationId, id)
    this.showTravelPanel(location)
  },

  highlightRoute(from, to) {
    this.highlightLayer.innerHTML = ""
    const roads = this.findRoute(from, to)
    if (!roads.length) return

    roads.forEach(edge => {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
      path.setAttribute("d", svgPath(this.roadPoints(edge)))
      path.setAttribute("class", "mmgo-map-route")
      this.highlightLayer.append(path)
    })
  },

  findRoute(from, to) {
    const adjacency = {}
    ROAD_PATHS.forEach(road => {
      adjacency[road.a] = adjacency[road.a] || []
      adjacency[road.b] = adjacency[road.b] || []
      adjacency[road.a].push({ to: road.b, road })
      adjacency[road.b].push({ to: road.a, road })
    })

    const queue = [{ id: from, roads: [] }]
    const seen = new Set([from])

    while (queue.length) {
      const current = queue.shift()
      if (current.id === to) return current.roads

      ;(adjacency[current.id] || []).forEach(next => {
        if (seen.has(next.to)) return
        seen.add(next.to)
        queue.push({ id: next.to, roads: [...current.roads, { road: next.road, from: current.id, to: next.to }] })
      })
    }

    return []
  },

  roadPoints(edge) {
    return edge.from === edge.road.a ? edge.road.pts : [...edge.road.pts].reverse()
  },

  showTravelPanel(location) {
    const distance = Math.max(2, this.findRoute(this.currentLocationId, location.id).length * 2)
    this.infoPanel.className = "mmgo-map-info mmgo-map-info--travel is-visible"
    this.infoPanel.innerHTML = ""

    const travelButton = dom("button", "mmgo-map-primary-action", { id: "map-start-travel", type: "button", text: "Отправиться →" })
    travelButton.addEventListener("click", () => this.startTravel(location.id))

    this.infoPanel.append(
      dom("div", "mmgo-map-info__head", {
        html: `<div><p>${location.typeLabel || "Пункт назначения"}</p><h3>${location.name}</h3></div><button type="button" class="mmgo-map-close" aria-label="Закрыть">×</button>`,
      }),
      dom("p", "mmgo-map-info__body", { text: location.desc }),
      dom("div", "mmgo-map-info__meta", { text: `~${distance} игр. дн.` }),
      travelButton
    )

    this.infoPanel.querySelector(".mmgo-map-close").addEventListener("click", () => this.closePanel())
  },

  startTravel(targetId) {
    const roads = this.findRoute(this.currentLocationId, targetId)
    if (!roads.length) return

    this.travel = {
      targetId,
      roads,
      startedAt: performance.now(),
      duration: Math.max(2200, roads.length * 1450),
    }

    this.infoPanel.className = "mmgo-map-info mmgo-map-info--travel is-visible"
    this.infoPanel.innerHTML = `<p class="mmgo-map-info__body">В пути. Дорога сама выбирает темп.</p><div class="mmgo-map-progress"><span></span></div>`
    this.tickTravel()
  },

  tickTravel() {
    if (!this.travel) return

    const elapsed = performance.now() - this.travel.startedAt
    const t = clamp(elapsed / this.travel.duration, 0, 1)
    const segmentCount = this.travel.roads.length
    const segmentIndex = Math.min(Math.floor(t * segmentCount), segmentCount - 1)
    const localT = t * segmentCount - segmentIndex
    const road = this.travel.roads[segmentIndex]
    const position = samplePath(this.roadPoints(road), localT)

    this.movePlayerTo(position)
    this.infoPanel.querySelector(".mmgo-map-progress span")?.style.setProperty("width", `${t * 100}%`)

    if (t >= 1) {
      this.currentLocationId = this.travel.targetId
      this.travel = null
      this.highlightLayer.innerHTML = ""
      this.markerLayer.querySelectorAll(".mmgo-map-marker").forEach(marker => {
        marker.classList.toggle("is-current", marker.dataset.locationId === this.currentLocationId)
        marker.classList.remove("is-selected")
      })
      this.showLocationEvent(this.locationById[this.currentLocationId])
      return
    }

    this.animationFrame = window.requestAnimationFrame(() => this.tickTravel())
  },

  movePlayerTo(location) {
    if (!location) return
    this.player.style.left = `${location.x}%`
    this.player.style.top = `${location.y}%`
  },

  showLocationEvent(location) {
    this.infoPanel.className = `mmgo-map-info mmgo-map-info--event mmgo-map-info--${location.layout || location.type} is-visible`
    this.infoPanel.innerHTML = ""

    const hero = dom("div", "mmgo-location-hero", { text: location.hero || location.name })
    const text = dom("div", "mmgo-location-text")
    ;(location.text || [location.desc]).forEach((paragraph, index) => {
      const p = dom("p")
      if (index === 0 && paragraph.length > 0) {
        p.append(dom("span", "mmgo-dropcap", { text: paragraph[0] }), document.createTextNode(paragraph.slice(1)))
      } else {
        p.textContent = paragraph
      }
      text.append(p)
    })

    this.infoPanel.append(
      hero,
      dom("div", "mmgo-location-title", {
        html: `<p>${location.subtitle || "Локация"}</p><h3 id="location-title">${location.name}</h3>`,
      }),
      text,
      this.locationActions(location)
    )
  },

  locationActions(location) {
    const actions = dom("div", "mmgo-location-actions")

    ;(location.actions || []).forEach(action => {
      const button = dom("button", action.accent ? "mmgo-location-action is-accent" : "mmgo-location-action", { type: "button" })
      button.append(
        dom("span", "mmgo-location-action__title", { text: action.title }),
        dom("span", "mmgo-location-action__note", { text: action.note || "" })
      )
      button.addEventListener("click", () => this.showToast(action.title))
      actions.append(button)
    })

    const close = dom("button", "mmgo-location-action", { type: "button", text: "Обратно к карте" })
    close.addEventListener("click", () => this.closePanel())
    actions.append(close)

    return actions
  },

  showToast(text) {
    this.toast.textContent = text
    this.toast.classList.add("is-visible")
    window.clearTimeout(this.toastTimer)
    this.toastTimer = window.setTimeout(() => this.toast.classList.remove("is-visible"), 1600)
  },

  closePanel() {
    this.infoPanel.className = "mmgo-map-info"
    this.infoPanel.innerHTML = ""
    this.selectedLocationId = null
    this.highlightLayer.innerHTML = ""
  },
}
