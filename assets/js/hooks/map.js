// MMGO-2 road paths — percentage coords matching mmgo2-map.png (2000×2000 source).
// Roads are already painted on the bitmap; these control points are used only for
// the route-highlight glow and player travel animation.
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

// Rich display content keyed by backend location slug
const SLUG_DISPLAY = {
  tower: {
    icon: "♜", typeLabel: "Башня", subtitle: "Единственное место, где работает магия",
    hero: "У подножия",
    text: [
      "Воздух здесь звенит, как струна слабо натянутого лука. Камень у входа тёплый — местами теплее ладони.",
      "Внутри слышно, как кто-то сосредоточенно что-то бормочет по-латыни. Голоса сразу трёх.",
    ],
  },
  capital: {
    icon: "♛", typeLabel: "Столица", subtitle: "Главный город княжества",
    hero: "Городские врата",
    text: [
      "Стражники в кольчугах лениво переглядываются. От кузницы тянет углём и потом, с рыночной площади — жареной рыбой и пряной мятой.",
      "К вам подходит мальчишка-посыльный: «Сударь, там на доске объявлений — письмо с вашим именем».",
    ],
  },
  "east-town": {
    icon: "♛", typeLabel: "Город", subtitle: "Пограничный торг",
    hero: "Северные ворота",
    text: ["Каменные склады и узкие улицы пахнут смолой, железом и чужими деньгами."],
  },
  kamen: {
    icon: "◘", typeLabel: "Руины", subtitle: "Старый круг",
    hero: "Предгорья",
    text: ["Над плитами стоит сухая тишина. Руна на центральном камне выглядит свежей."],
  },
  "lake-village": {
    icon: "⌂", typeLabel: "Деревня", subtitle: "Озерная деревня",
    hero: "Причал",
    text: ["Сети сохнут на кольях, дети гоняют деревянный обруч, а староста делает вид, что не ждал вас."],
  },
  windmill: {
    icon: "⌂", typeLabel: "Хутор", subtitle: "Ветряной хутор",
    hero: "Мельничный холм",
    text: ["Крылья мельницы скрипят даже без ветра. На двери висит знак гильдии поставщиков."],
  },
  "east-farms": {
    icon: "⌂", typeLabel: "Поля", subtitle: "Полевые артели",
    hero: "Пшеничные полосы",
    text: ["Поля идут до горизонта, но чучела стоят слишком ровно, будто их расставлял военный инженер."],
  },
  hermitage: {
    icon: "◘", typeLabel: "Скит", subtitle: "Заброшенный скит",
    hero: "Горная хижина",
    text: ["В очаге лежит тёплый пепел. Кто-то ушёл недавно и намеренно не заметал следы."],
  },
  farmstead: {
    icon: "▲", typeLabel: "База", subtitle: "Ваша база",
    hero: "Дом",
    text: ["Скрипит калитка. Пёс без одного уха привычно не гавкает. На крыльце — чей-то оставленный вчера свёрток."],
  },
}

const KIND_ACTIONS = {
  tower: [
    { key: "party", title: "Собрать / найти отряд", note: "перед входом" },
    { key: "dungeon", title: "Войти в подземелье", note: "готовьтесь тщательно", accent: true },
    { key: "library", title: "Библиотека Башни", note: "старые записи" },
  ],
  city: [
    { key: "academy", title: "В Академию", note: "учебные залы", href: "/academy/bulletin-board" },
    { key: "market", title: "На рынок", note: "лавки и торговцы" },
    { key: "tavern", title: "В таверну", note: "новости и наём" },
  ],
  base: [
    { key: "base", title: "Войти в дом", note: "личные комнаты", accent: true },
    { key: "forge", title: "В мастерскую", note: "крафт и ремонт" },
    { key: "garden", title: "Огород и запасы", note: "провиант" },
  ],
  wilderness: [
    { key: "gather", title: "Добыча ресурсов", note: "обыскать округу" },
    { key: "camp", title: "Разбить лагерь", note: "отдых и припасы" },
  ],
}

const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const romanize = n => ROMAN[n - 1] || String(n)
const riskLabel = level => (level >= 60 ? "высокий риск" : level >= 30 ? "средний риск" : "низкий риск")
const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

const dom = (tag, className, attrs = {}) => {
  const el = document.createElement(tag)
  if (className) el.className = className
  Object.entries(attrs).forEach(([k, v]) => {
    if (k === "text") el.textContent = v
    else if (k === "html") el.innerHTML = v
    else if (k === "style") Object.assign(el.style, v)
    else el.setAttribute(k, v)
  })
  return el
}

const svgPath = pts => {
  if (pts.length < 2) return ""
  let d = `M ${pts[0][0]} ${pts[0][1]}`
  for (let i = 1; i < pts.length - 1; i++) {
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
  for (let i = 0; i < pts.length - 1; i++) {
    const len = Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
    lengths.push(len)
    total += len
  }
  let travelled = 0
  const target = t * total
  for (let i = 0; i < lengths.length; i++) {
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

const findRoadPath = (a, b) =>
  ROAD_PATHS.find(r => (r.a === a && r.b === b) || (r.a === b && r.b === a)) || null

export const MapHook = {
  mounted() {
    this.statePath = this.el.dataset.statePath
    this.journeysPath = this.el.dataset.journeysPath
    this.fastArrivePath = this.el.dataset.fastArrivePath

    this.state = null
    this.locations = []
    this.locById = {}
    this.slugById = {}
    this.currentLocationId = null
    this.selectedLocationId = null
    this.scale = 1
    this.pan = { x: 0, y: 0 }
    this.isNight = false
    this.drag = null
    this.animFrame = null
    this.pollTimer = null
    this.pendingTravel = false
    this.wasJourneyActive = false
    this.hasCenteredInitial = false

    this.render()
    this.bindControls()
    this.fetchState()
    window.requestAnimationFrame(() => this.el.classList.add("is-ready"))
  },

  destroyed() {
    window.clearTimeout(this.pollTimer)
    if (this.animFrame) window.cancelAnimationFrame(this.animFrame)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
  },

  render() {
    this.el.classList.add("mmgo-map-hook")
    this.el.innerHTML = ""

    this.viewport = dom("div", "mmgo-map-viewport", {
      role: "application",
      "aria-label": "Интерактивная карта MMGO",
    })
    this.stage = dom("div", "mmgo-map-stage")
    this.image = dom("img", "mmgo-map-image", {
      src: this.el.dataset.mapSrc || "/images/mmgo2-map.png",
      alt: "",
      draggable: "false",
    })
    // Highlight-only SVG — roads come from the bitmap, not SVG
    this.highlightLayer = dom("svg", "mmgo-map-highlight", {
      viewBox: "0 0 100 100",
      preserveAspectRatio: "none",
    })
    this.markerLayer = dom("div", "mmgo-map-markers")
    this.ambientLayer = dom("div", "mmgo-map-ambient")
    this.player = dom("div", "mmgo-map-player", { text: "◆" })

    this.stage.append(this.image, this.highlightLayer, this.markerLayer, this.player, this.ambientLayer)
    this.viewport.append(this.stage)

    // Single floating recenter FAB — replaces the desktop control bar
    this.recenterFab = dom("button", "mmgo-map-recenter-fab", {
      type: "button",
      "aria-label": "Центр на игроке",
      text: "◎",
    })
    this.recenterFab.addEventListener("click", () => {
      if (this.currentLocationId) this.centerOn(this.currentLocationId, { scale: 1.18 })
    })

    this.infoPanel = dom("aside", "mmgo-map-info", { id: "map-location-drawer" })
    this.toast = dom("div", "mmgo-map-toast")

    this.el.append(this.viewport, this.recenterFab, this.infoPanel, this.toast)
  },

  bindControls() {
    this.viewport.addEventListener(
      "wheel",
      event => {
        event.preventDefault()
        this.zoomBy(event.deltaY > 0 ? -0.08 : 0.08)
      },
      { passive: false }
    )

    // Drag to pan
    this.viewport.addEventListener("pointerdown", event => {
      if (event.button !== 0) return
      if (event.target.closest(".mmgo-map-marker, .mmgo-map-info, .mmgo-map-recenter-fab")) return
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
      const dx = event.clientX - this.drag.startX
      const dy = event.clientY - this.drag.startY
      const wasTap = Math.hypot(dx, dy) < 6
      this.drag = null
      this.viewport.classList.remove("is-dragging")
      if (wasTap && this.infoPanel.classList.contains("is-visible")) {
        this.closePanel()
      }
    }

    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)

    // Pinch-to-zoom (touch)
    let pinchDist0 = null
    let pinchScale0 = 1
    this.viewport.addEventListener("touchstart", e => {
      if (e.touches.length === 2) {
        pinchDist0 = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        )
        pinchScale0 = this.scale
      }
    }, { passive: true })
    this.viewport.addEventListener("touchmove", e => {
      if (e.touches.length === 2 && pinchDist0) {
        const dist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        )
        this.scale = clamp(pinchScale0 * (dist / pinchDist0), 0.92, 1.95)
        this.applyTransform()
      }
    }, { passive: true })
    this.viewport.addEventListener("touchend", e => {
      if (e.touches.length < 2) pinchDist0 = null
    }, { passive: true })
  },

  async fetchState(silent = false) {
    if (!this.statePath) return
    try {
      const res = await fetch(this.statePath, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
      })
      const payload = await res.json()
      if (!res.ok || !payload.ok) throw new Error(payload.error || "ошибка")
      this.state = payload.state
      this.syncFromState()
    } catch (_err) {
      if (!silent) this.showToast("Не удалось загрузить карту")
    }
  },

  syncFromState() {
    const { state } = this
    if (!state) return

    const { width, height } = state.map
    this.locations = state.map.locations.map(loc => ({
      ...loc,
      xPct: (loc.x / width) * 100,
      yPct: (loc.y / height) * 100,
    }))
    this.locById = Object.fromEntries(this.locations.map(l => [l.id, l]))
    this.slugById = Object.fromEntries(this.locations.map(l => [l.id, l.slug]))
    this.currentLocationId = state.current_location?.id || null

    this.applyDayPhase(state.time?.day_phase || "day")
    this.updateTimePill(state.time)
    this.drawMarkers()

    if (state.active_journey) {
      this.startTravelLoop(state)
      this.showTravelProgress(state)
    } else {
      this.stopTravelLoop()
      this.updatePlayerPosition()
      if (this.wasJourneyActive && this.currentLocationId) {
        const loc = this.locById[this.currentLocationId]
        if (loc) this.showLocationEvent(loc)
      }
    }
    this.wasJourneyActive = !!state.active_journey

    if (state.active_journey) this.selectedLocationId = null

    if (!this.hasCenteredInitial && this.currentLocationId) {
      this.centerOn(this.currentLocationId, { scale: 1.18 })
      this.hasCenteredInitial = true
    }

    this.schedulePoll(state)
  },

  drawMarkers() {
    this.markerLayer.innerHTML = ""
    this.locations.forEach((loc, index) => {
      const display = SLUG_DISPLAY[loc.slug] || {}
      const icon = display.icon || "●"
      const isCurrent = loc.id === this.currentLocationId
      const isSelected = loc.id === this.selectedLocationId

      const marker = dom(
        "button",
        [
          "mmgo-map-marker",
          `mmgo-map-marker--${loc.kind}`,
          isCurrent ? "is-current" : "",
          isSelected ? "is-selected" : "",
        ]
          .filter(Boolean)
          .join(" "),
        {
          id: `map-location-${loc.id}`,
          type: "button",
          "data-location-id": loc.id,
          style: {
            left: `${loc.xPct}%`,
            top: `${loc.yPct}%`,
            animationDelay: `${index * 70}ms`,
          },
        }
      )
      marker.append(
        dom("span", "mmgo-map-marker__pin", { text: icon }),
        dom("span", "mmgo-map-marker__label", { text: loc.name })
      )

      const handleClick = event => {
        event.stopPropagation()
        event.preventDefault()
        this.selectLocation(loc.id)
      }
      marker.addEventListener("click", handleClick)
      marker.addEventListener("pointerup", handleClick)

      this.markerLayer.append(marker)
    })
  },

  selectLocation(id) {
    const loc = this.locById[id]
    if (!loc || this.state?.active_journey) return

    if (id === this.currentLocationId) {
      this.showLocationEvent(loc)
      return
    }

    this.selectedLocationId = id
    this.drawMarkers()
    this.drawHighlight(id)
    this.centerOn(id)

    const route = this.state?.available_routes?.find(r => r.destination_location_id === id)
    this.showTravelPanel(loc, route)
  },

  drawHighlight(targetId) {
    this.highlightLayer.innerHTML = ""
    if (!targetId || !this.currentLocationId) return

    const currentSlug = this.slugById[this.currentLocationId]
    const targetSlug = this.slugById[targetId]
    if (!currentSlug || !targetSlug) return

    const edges = this.findVisualRoute(currentSlug, targetSlug)
    if (!edges.length) return

    const d = edges.map(edge => svgPath(this.roadPtsForEdge(edge))).join(" ")

    // Zip-style: soft amber glow + animated dashed overlay
    const glow = document.createElementNS("http://www.w3.org/2000/svg", "path")
    glow.setAttribute("d", d)
    glow.setAttribute("class", "mmgo-route-glow")

    const dashes = document.createElementNS("http://www.w3.org/2000/svg", "path")
    dashes.setAttribute("d", d)
    dashes.setAttribute("class", "mmgo-route-dashes")

    this.highlightLayer.append(glow, dashes)
  },

  findVisualRoute(fromSlug, toSlug) {
    const adj = {}
    ROAD_PATHS.forEach(road => {
      ;(adj[road.a] = adj[road.a] || []).push({ to: road.b, road })
      ;(adj[road.b] = adj[road.b] || []).push({ to: road.a, road })
    })
    const queue = [{ id: fromSlug, roads: [] }]
    const seen = new Set([fromSlug])
    while (queue.length) {
      const cur = queue.shift()
      if (cur.id === toSlug) return cur.roads
      ;(adj[cur.id] || []).forEach(next => {
        if (seen.has(next.to)) return
        seen.add(next.to)
        queue.push({ id: next.to, roads: [...cur.roads, { road: next.road, from: cur.id, to: next.to }] })
      })
    }
    return []
  },

  roadPtsForEdge(edge) {
    return edge.from === edge.road.a ? edge.road.pts : [...edge.road.pts].reverse()
  },

  showTravelPanel(loc, route) {
    const display = SLUG_DISPLAY[loc.slug] || {}
    this.infoPanel.className = "mmgo-map-info mmgo-map-info--travel is-visible"
    this.infoPanel.innerHTML = ""

    const head = dom("div", "mmgo-map-info__head", {
      html: `<div><p>${display.typeLabel || loc.kind}</p><h3>${loc.name}</h3></div><button type="button" class="mmgo-map-close" aria-label="Закрыть">×</button>`,
    })
    this.infoPanel.append(head)

    if (route) {
      const meta = `${route.total_game_days} игр. дн. · ${route.required_food_units} паёк · ${riskLabel(route.risk_level)}`
      const travelButton = dom("button", "mmgo-map-primary-action", {
        id: "map-start-travel",
        type: "button",
        text: "Отправиться →",
      })
      travelButton.addEventListener("click", () => this.startJourney(route.id))
      this.infoPanel.append(
        dom("p", "mmgo-map-info__body", { text: loc.description || "" }),
        dom("div", "mmgo-map-info__meta", { text: meta }),
        travelButton
      )
    } else {
      this.infoPanel.append(
        dom("p", "mmgo-map-info__body", { text: "Нет прямого маршрута отсюда." })
      )
    }

    this.infoPanel.querySelector(".mmgo-map-close")?.addEventListener("click", () => this.closePanel())
  },

  async startJourney(routeId) {
    if (!routeId || this.pendingTravel || !this.journeysPath) return
    this.pendingTravel = true

    const btn = this.infoPanel.querySelector("#map-start-travel")
    if (btn) { btn.disabled = true; btn.textContent = "Прокладываем..." }

    try {
      const res = await fetch(this.journeysPath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: JSON.stringify({ route_id: routeId }),
      })
      const payload = await res.json()
      if (!res.ok || !payload.ok) throw new Error(payload.error || "ошибка")
      this.state = payload.state
      this.pendingTravel = false
      this.selectedLocationId = null
      this.syncFromState()
    } catch (err) {
      this.pendingTravel = false
      this.showToast(err.message || "Не удалось начать переход.")
      if (btn) { btn.disabled = false; btn.textContent = "Отправиться →" }
    }
  },

  showTravelProgress(state) {
    const j = state.active_journey
    this.infoPanel.className = "mmgo-map-info mmgo-map-info--travel is-visible"
    this.infoPanel.innerHTML = `
      <div class="mmgo-map-info__head">
        <div><p>В пути</p><h3>${j.from_name} → ${j.to_name}</h3></div>
      </div>
      <p class="mmgo-map-info__body">${j.remaining_game_days} игр. дн. осталось</p>
      <div class="mmgo-map-progress"><span style="width:${j.percent_complete}%"></span></div>
      <button type="button" class="mmgo-map-speed-btn" id="map-speed-btn">⚡ Прибыть (тест)</button>
    `
    this.infoPanel.querySelector("#map-speed-btn")?.addEventListener("click", () => this.fastArrive())
  },

  async fastArrive() {
    if (!this.fastArrivePath) return
    const btn = this.infoPanel.querySelector("#map-speed-btn")
    if (btn) { btn.disabled = true; btn.textContent = "Прибываем..." }
    try {
      const res = await fetch(this.fastArrivePath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: "{}",
      })
      const payload = await res.json()
      if (!res.ok || !payload.ok) throw new Error(payload.error || "ошибка")
      this.state = payload.state
      this.syncFromState()
    } catch (err) {
      this.showToast(err.message || "Ошибка ускорения.")
      if (btn) { btn.disabled = false; btn.textContent = "⚡ Прибыть (тест)" }
    }
  },

  startTravelLoop(state) {
    const j = state.active_journey
    const startedMs = new Date(j.started_at).getTime()
    const arrivalMs = new Date(j.arrival_at).getTime()

    const route = state.map.routes.find(r => r.id === j.route_id)
    let routePts = null
    if (route) {
      const oSlug = this.slugById[route.origin_location_id]
      const dSlug = this.slugById[route.destination_location_id]
      const road = findRoadPath(oSlug, dSlug)
      if (road) {
        const forward = j.from_location_id === route.origin_location_id
        routePts = forward ? road.pts : [...road.pts].reverse()
      }
    }

    if (this.animFrame) window.cancelAnimationFrame(this.animFrame)

    const tick = () => {
      const t = clamp((Date.now() - startedMs) / (arrivalMs - startedMs), 0, 1)

      if (routePts) {
        const pos = samplePath(routePts, t)
        this.player.style.left = `${pos.x}%`
        this.player.style.top = `${pos.y}%`
      } else {
        const { width, height } = state.map
        this.player.style.left = `${(state.player.x / width) * 100}%`
        this.player.style.top = `${(state.player.y / height) * 100}%`
      }

      const fill = this.infoPanel.querySelector(".mmgo-map-progress span")
      if (fill) fill.style.width = `${t * 100}%`

      if (t < 1) {
        this.animFrame = window.requestAnimationFrame(tick)
      } else {
        this.animFrame = null
        this.fetchState(true)
      }
    }

    this.animFrame = window.requestAnimationFrame(tick)
  },

  stopTravelLoop() {
    if (this.animFrame) {
      window.cancelAnimationFrame(this.animFrame)
      this.animFrame = null
    }
  },

  updatePlayerPosition() {
    if (!this.currentLocationId) return
    const loc = this.locById[this.currentLocationId]
    if (loc) {
      this.player.style.left = `${loc.xPct}%`
      this.player.style.top = `${loc.yPct}%`
    }
  },

  schedulePoll(state) {
    window.clearTimeout(this.pollTimer)
    this.pollTimer = null
    if (!state.active_journey) return
    const interval = state.client?.poll_interval_ms || 10_000
    this.pollTimer = window.setTimeout(() => this.fetchState(true), interval)
  },

  applyDayPhase(phase) {
    const isNight = phase === "night"
    if (this.isNight === isNight) return
    this.isNight = isNight
    this.el.classList.toggle("is-night", isNight)
  },

  updateTimePill(timeState) {
    const pill = document.getElementById("game-time-pill")
    if (!pill || !timeState) return
    const day = timeState.game_day || 1
    const year = romanize(timeState.game_year || 1)
    const phase = timeState.day_phase === "night" ? "ночь" : "день"
    pill.innerHTML = `
      <p class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[#7a6030]">День ${day}</p>
      <p class="text-xs text-[#e8d5b0]">${phase} · ${year} г.</p>
    `
  },

  showLocationEvent(loc) {
    const display = SLUG_DISPLAY[loc.slug] || {}
    const actions = KIND_ACTIONS[loc.kind] || KIND_ACTIONS.wilderness

    this.infoPanel.className = `mmgo-map-info mmgo-map-info--event mmgo-map-info--${loc.kind} is-visible`
    this.infoPanel.innerHTML = ""

    const hero = dom("div", "mmgo-location-hero", { text: display.hero || loc.name })
    const titleBlock = dom("div", "mmgo-location-title", {
      html: `<p>${display.subtitle || loc.kind}</p><h3 id="location-title">${loc.name}</h3>`,
    })
    const textBlock = dom("div", "mmgo-location-text")
    ;(display.text || [loc.description || loc.name]).forEach((paragraph, i) => {
      const p = dom("p")
      if (i === 0 && paragraph.length > 0) {
        p.append(
          dom("span", "mmgo-dropcap", { text: paragraph[0] }),
          document.createTextNode(paragraph.slice(1))
        )
      } else {
        p.textContent = paragraph
      }
      textBlock.append(p)
    })

    this.infoPanel.append(hero, titleBlock, textBlock, this.locationActions(actions))
  },

  locationActions(actions) {
    const container = dom("div", "mmgo-location-actions")
    actions.forEach(action => {
      const button = dom(
        "button",
        action.accent ? "mmgo-location-action is-accent" : "mmgo-location-action",
        { type: "button" }
      )
      button.append(
        dom("span", "mmgo-location-action__title", { text: action.title }),
        dom("span", "mmgo-location-action__note", { text: action.note || "" })
      )
      button.addEventListener("click", () => {
        if (action.href) {
          window.location.href = action.href
        } else {
          let notice = container.querySelector(".mmgo-action-notice")
          if (!notice) {
            notice = dom("p", "mmgo-action-notice")
            container.prepend(notice)
          }
          notice.textContent = `${action.title} — пока недоступно`
        }
      })
      container.append(button)
    })
    const close = dom("button", "mmgo-location-action", { type: "button", text: "Обратно к карте" })
    close.addEventListener("click", () => this.closePanel())
    container.append(close)
    return container
  },

  closePanel() {
    this.infoPanel.className = "mmgo-map-info"
    this.infoPanel.innerHTML = ""
    this.selectedLocationId = null
    this.highlightLayer.innerHTML = ""
    this.drawMarkers()
  },

  showToast(text) {
    this.toast.textContent = text
    this.toast.classList.add("is-visible")
    window.clearTimeout(this.toastTimer)
    this.toastTimer = window.setTimeout(() => this.toast.classList.remove("is-visible"), 1600)
  },

  zoomBy(delta) {
    this.scale = clamp(this.scale + delta, 0.92, 1.95)
    this.applyTransform()
  },

  applyTransform() {
    const maxPan = 220 * this.scale
    this.pan.x = clamp(this.pan.x, -maxPan, maxPan)
    this.pan.y = clamp(this.pan.y, -maxPan, maxPan)
    this.stage.style.transform = `translate3d(${this.pan.x}px, ${this.pan.y}px, 0) scale(${this.scale})`
  },

  centerOn(id, options = {}) {
    const loc = this.locById[id]
    if (!loc) return
    const rect = this.viewport.getBoundingClientRect()
    this.scale = options.scale || Math.max(this.scale, 1.14)
    this.pan = {
      x: (50 - loc.xPct) * rect.width * 0.0105,
      y: (50 - loc.yPct) * rect.height * 0.0105,
    }
    this.applyTransform()
  },
}
