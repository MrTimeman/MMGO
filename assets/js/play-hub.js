import L from "leaflet"

// Route path waypoints extracted from MpGO.svg overlay.
// Each entry is an array of Leaflet [lat, lng] = [game_y, game_x] pairs
// tracing the road artwork between the two endpoints.
const ROUTE_PATHS = {
  "Capital Road to the Tower": [[869,1111],[870,1142],[871,1156],[883,1206],[883,1230],[861,1235],[882,1272],[757,1379],[756,1401],[757,1432],[756,1468],[460,1642],[452,1680],[452,1761]],
  "Merchant Wake":             [[882,1178],[882,1132],[865,1259],[867,1217],[861,1235],[869,1111],[862,1087],[655,1195],[662,1065],[659,1073],[649,1125],[634,1173],[631,1161],[624,1188]],
  "Ash Road":                  [[870,1142],[864,1143],[871,1156],[888,1193],[878,1205],[883,1230],[861,1235],[883,1248],[882,1272],[759,1369],[757,1379],[758,1392],[755,1410],[757,1432]],
  "Harbor Trace":              [[655,1117],[643,1125],[655,1126],[652,1136],[613,1154],[631,1153],[618,1164],[655,1157],[625,1180],[665,1189],[755,1371],[756,1389],[751,1409],[757,1432]],
  "Watchers' Spur":            [[756,1468],[757,1442],[751,1409],[753,1386],[757,1379],[862,1273],[882,1272],[868,1241],[878,1230],[1185,1195],[1197,1183],[1198,1165],[1190,1141],[1202,1139]],
  "Pilgrim Stair":             [[756,1401],[751,1409],[753,1420],[757,1442],[753,1451],[756,1468],[752,1475],[756,1489],[460,1642],[460,1651],[460,1680],[459,1725],[435,1722],[452,1761]],
  "High Watch Road":           [[1207,1105],[1199,1142],[1195,1154],[1202,1184],[1201,1207],[757,1379],[753,1386],[753,1420],[753,1451],[752,1475],[460,1642],[452,1680],[460,1761],[460,1838]],
}

const LOCATION_COLORS = {
  city: "#d6b36d",
  tower: "#c26f50",
  wilderness: "#8a8e62",
  base: "#6f9f84",
  dungeon_entrance: "#7b88b7",
}

function firstErrorMessage(payload) {
  const details = payload?.details

  if (details && typeof details === "object") {
    for (const messages of Object.values(details)) {
      if (Array.isArray(messages) && messages.length > 0) {
        return messages[0]
      }
    }
  }

  return payload?.error || "Не удалось обновить карту."
}

function riskLabel(riskLevel) {
  if (riskLevel >= 60) return "высокий риск"
  if (riskLevel >= 30) return "средний риск"
  return "низкий риск"
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return "прибытие скоро"

  const minutes = Math.round(seconds / 60)

  if (minutes < 60) {
    return `${minutes} мин`
  }

  const hours = Math.floor(minutes / 60)
  const restMinutes = minutes % 60

  if (restMinutes === 0) {
    return `${hours} ч`
  }

  return `${hours} ч ${restMinutes} мин`
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

function pointForLocation(location) {
  return [location.y, location.x]
}

function selectedRouteId(state, selectedLocationId) {
  if (state?.active_journey?.route_id) {
    return state.active_journey.route_id
  }

  return (
    state?.available_routes?.find((route) => route.destination_location_id === selectedLocationId)?.id || null
  )
}

class PlayHubApp {
  constructor(root) {
    this.root = root
    this.statePath = root.dataset.statePath
    this.journeysPath = root.dataset.journeysPath
    this.utilitySpellsPath = root.dataset.utilitySpellsPath
    this.demoResetPath = root.dataset.demoResetPath
    this.state = null
    this.errorMessage = ""
    this.loading = true
    this.pendingAction = null
    this.selectedLocationId = null
    this.pollTimer = null
    this.overlay = null
    this.routeLayer = null
    this.markerLayer = null
    this.playerMarker = null
    this.overlayReady = false
    this.screen = "map"
    this.screenEl = null
    this.handleRootClick = this.handleRootClick.bind(this)
    this.handleResize = this.handleResize.bind(this)
    this.applyViewport = () => {}
  }

  mount() {
    if (this.root.dataset.playHubMounted === "true") {
      return
    }

    this.root.dataset.playHubMounted = "true"
    this.renderShell()
    this.initMap()
    this.setupTelegramShell()
    this.root.addEventListener("click", this.handleRootClick)
    window.addEventListener("resize", this.handleResize)
    this.fetchState()
  }

  renderShell() {
    this.root.innerHTML = `
      <div class="play-map-shell">
        <div class="play-map-surface" data-play-map></div>
        <div class="play-map-sheet" data-play-sheet></div>
        <div class="play-screen" data-play-screen style="display:none"></div>
      </div>
    `

    this.mapEl = this.root.querySelector("[data-play-map]")
    this.sheetEl = this.root.querySelector("[data-play-sheet]")
    this.screenEl = this.root.querySelector("[data-play-screen]")
  }

  initMap() {
    this.map = L.map(this.mapEl, {
      crs: L.CRS.Simple,
      minZoom: -2,
      maxZoom: 1.5,
      zoomSnap: 0.1,
      zoomControl: false,
      attributionControl: false,
      preferCanvas: true,
    })

    this.routeLayer = L.layerGroup().addTo(this.map)
    this.markerLayer = L.layerGroup().addTo(this.map)

    // Coordinate calibration helper — click anywhere to log [x, y] for seeds
    this.map.on("click", (e) => {
      const x = Math.round(e.latlng.lng)
      const y = Math.round(e.latlng.lat)
      console.log(`[MAP CLICK] x: ${x}, y: ${y}`)
    })
  }

  setupTelegramShell() {
    const telegram = window.Telegram?.WebApp

    this.applyViewport = () => {
      const height = telegram?.viewportStableHeight ?? telegram?.viewportHeight ?? window.innerHeight
      this.root.style.setProperty("--tg-viewport-height", `${Math.round(height)}px`)
    }

    this.applyViewport()

    if (!telegram) {
      return
    }

    telegram.ready?.()
    telegram.expand?.()
    telegram.disableVerticalSwipes?.()
    telegram.setBackgroundColor?.("#0f0d0b")
    telegram.setHeaderColor?.("#0f0d0b")
    telegram.onEvent?.("themeChanged", this.handleResize)
    telegram.onEvent?.("viewportChanged", this.handleResize)
  }

  handleResize() {
    this.applyViewport()

    if (this.map) {
      this.map.invalidateSize(false)
    }
  }

  destroy() {
    window.clearTimeout(this.pollTimer)
    this.pollTimer = null

    this.root.removeEventListener("click", this.handleRootClick)
    window.removeEventListener("resize", this.handleResize)

    const telegram = window.Telegram?.WebApp

    telegram?.offEvent?.("themeChanged", this.handleResize)
    telegram?.offEvent?.("viewportChanged", this.handleResize)

    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async fetchState({ silent = false } = {}) {
    if (!silent) {
      this.loading = true
      this.renderSheet()
    }

    try {
      const response = await fetch(this.statePath, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
      })
      const payload = await response.json()

      if (!response.ok || payload.ok === false) {
        throw new Error(firstErrorMessage(payload))
      }

      this.state = payload.state
      this.loading = false
      this.pendingAction = null
      this.errorMessage = ""
      this.normalizeSelection()
      this.syncMap()
      this.renderSheet()
      this.schedulePoller()
    } catch (error) {
      this.loading = false
      this.errorMessage = error.message || "Не удалось загрузить карту."
      this.renderSheet()
    }
  }

  async startJourney(routeId) {
    if (!routeId || this.pendingAction) {
      return
    }

    this.pendingAction = "travel"
    this.errorMessage = ""
    this.renderSheet()

    try {
      const response = await fetch(this.journeysPath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: JSON.stringify({ route_id: routeId }),
      })
      const payload = await response.json()

      if (!response.ok || payload.ok === false) {
        throw new Error(firstErrorMessage(payload))
      }

      this.state = payload.state
      this.pendingAction = null
      this.errorMessage = ""
      this.loading = false
      this.normalizeSelection()
      this.syncMap()
      this.renderSheet()
      this.schedulePoller()
      this.focusJourneyRoute({ animate: true })
    } catch (error) {
      this.pendingAction = null
      this.errorMessage = error.message || "Не удалось начать переход."
      this.renderSheet()
    }
  }

  async resetDemo() {
    if (!this.demoResetPath || this.pendingAction) {
      return
    }

    this.pendingAction = "reset"
    this.errorMessage = ""
    this.renderSheet()

    try {
      const response = await fetch(this.demoResetPath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: JSON.stringify({}),
      })
      const payload = await response.json()

      if (!response.ok || payload.ok === false) {
        throw new Error(firstErrorMessage(payload))
      }

      this.state = payload.state
      this.pendingAction = null
      this.errorMessage = ""
      this.loading = false
      this.normalizeSelection()
      this.syncMap()
      this.renderSheet()
      this.schedulePoller()
      this.focusCurrentLocation({ animate: true })
    } catch (error) {
      this.pendingAction = null
      this.errorMessage = error.message || "Не удалось сбросить демо."
      this.renderSheet()
    }
  }

  async castUtilitySpell(spellId) {
    if (!this.utilitySpellsPath || !spellId || this.pendingAction) {
      return
    }

    this.pendingAction = `utility:${spellId}`
    this.errorMessage = ""
    this.renderSheet()

    try {
      const response = await fetch(this.utilitySpellsPath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: JSON.stringify({ spell_id: spellId }),
      })
      const payload = await response.json()

      if (!response.ok || payload.ok === false) {
        throw new Error(firstErrorMessage(payload))
      }

      this.state = payload.state
      this.pendingAction = null
      this.errorMessage = ""
      this.loading = false
      this.normalizeSelection()
      this.syncMap()
      this.renderSheet()
    } catch (error) {
      this.pendingAction = null
      this.errorMessage = error.message || "Не удалось применить чары."
      this.renderSheet()
    }
  }

  normalizeSelection() {
    const locations = this.state?.map?.locations || []
    const locationIds = new Set(locations.map((location) => location.id))

    if (this.state?.active_journey?.to_location_id) {
      this.selectedLocationId = this.state.active_journey.to_location_id
      return
    }

    if (
      this.selectedLocationId &&
      locationIds.has(this.selectedLocationId) &&
      this.selectedTravelOption()
    ) {
      return
    }

    this.selectedLocationId =
      this.state?.available_routes?.[0]?.destination_location_id || this.state?.current_location?.id || null
  }

  schedulePoller() {
    window.clearTimeout(this.pollTimer)
    this.pollTimer = null

    if (!this.state?.active_journey) {
      return
    }

    this.pollTimer = window.setTimeout(() => this.fetchState({ silent: true }), this.pollInterval())
  }

  pollInterval() {
    return this.state?.client?.poll_interval_ms || 10_000
  }

  ensureOverlay() {
    const imageUrl = this.state?.map?.image_url
    const width = this.state?.map?.width
    const height = this.state?.map?.height

    if (!imageUrl || !width || !height) {
      return
    }

    const bounds = [
      [0, 0],
      [height, width],
    ]

    if (!this.overlay) {
      this.overlay = L.imageOverlay(imageUrl, bounds).addTo(this.map)
      this.map.fitBounds(bounds, { padding: [24, 24] })
      this.map.setMaxBounds(bounds)
      this.overlayReady = true
      return
    }

    this.overlay.setBounds(bounds)
  }

  syncMap() {
    if (!this.state) {
      return
    }

    this.ensureOverlay()
    this.routeLayer.clearLayers()
    this.markerLayer.clearLayers()

    const locations = new Map(this.state.map.locations.map((location) => [location.id, location]))
    const focusedRouteId = selectedRouteId(this.state, this.selectedLocationId)

    this.state.map.routes.forEach((route) => {
      const origin = locations.get(route.origin_location_id)
      const destination = locations.get(route.destination_location_id)

      if (!origin || !destination) {
        return
      }

      const focused = focusedRouteId === route.id
      // Use traced SVG waypoints when available; fall back to straight line
      const tracedPath = ROUTE_PATHS[route.name]
      const latlngs = tracedPath || [pointForLocation(origin), pointForLocation(destination)]

      L.polyline(latlngs, {
        color: focused ? "#e8c37a" : "#a99b7d",
        weight: focused ? 4 : 2,
        opacity: focused ? 0.9 : 0.42,
        dashArray: focused ? null : "10 14",
      }).addTo(this.routeLayer)
    })

    this.state.map.locations.forEach((location) => {
      const selected = location.id === this.selectedLocationId
      const current = location.id === this.state.current_location?.id
      const destination = location.id === this.state.active_journey?.to_location_id

      const marker = L.circleMarker(pointForLocation(location), {
        radius: current || destination ? 8 : 6,
        color: "#f4ead7",
        weight: selected ? 3 : 2,
        fillColor: LOCATION_COLORS[location.kind] || "#9b927f",
        fillOpacity: current || destination ? 0.98 : 0.88,
        opacity: 0.95,
      })

      marker.on("click", () => {
        if (!this.state?.active_journey) {
          if (location.current) {
            this.showScreen("location")
            return
          }
          this.selectedLocationId = location.id
          this.focusLocationSelection(location.id, { animate: true })
        }

        this.renderSheet()
        this.syncMap()
      })

      marker.bindTooltip(location.name, {
        direction: "top",
        offset: [0, -12],
        opacity: 0.96,
        className: "play-map-tooltip",
      })

      marker.addTo(this.markerLayer)
    })

    this.syncPlayerMarker()
  }

  syncPlayerMarker() {
    if (!this.state?.player) {
      return
    }

    const latLng = [this.state.player.y, this.state.player.x]

    if (!this.playerMarker) {
      this.playerMarker = L.circleMarker(latLng, {
        radius: 9,
        color: "#fff3dc",
        weight: 3,
        fillColor: "#e0a33b",
        fillOpacity: 1,
        opacity: 1,
      }).addTo(this.map)

      return
    }

    this.playerMarker.setLatLng(latLng)
  }

  handleRootClick(event) {
    const action = event.target.closest("[data-action]")

    if (!action) {
      return
    }

    switch (action.dataset.action) {
      case "pick-route":
        this.selectedLocationId = action.dataset.destinationId
        this.renderSheet()
        this.syncMap()
        this.focusLocationSelection(this.selectedLocationId, { animate: true })
        break
      case "start-route":
        this.startJourney(action.dataset.routeId)
        break
      case "reset-demo":
        this.resetDemo()
        break
      case "cast-utility-spell":
        this.castUtilitySpell(action.dataset.spellId)
        break
      case "loc-back":
        this.showScreen("map")
        break
      case "loc-go-screen":
        this.showScreen(action.dataset.screen)
        break
      case "loc-go-href":
        window.location.href = action.dataset.href
        break
      case "base-back":
        this.showScreen("location")
        break
      case "loc-stub":
      case "base-stub":
        break
      default:
        break
    }
  }

  selectedTravelOption() {
    return (
      this.state?.available_routes?.find(
        (route) => route.destination_location_id === this.selectedLocationId
      ) || null
    )
  }

  currentLocation() {
    return this.state?.map?.locations?.find(
      (location) => location.id === this.state?.current_location?.id
    )
  }

  locationById(locationId) {
    return this.state?.map?.locations?.find((location) => location.id === locationId) || null
  }

  focusCurrentLocation(options = {}) {
    const currentLocation = this.currentLocation()

    if (!currentLocation) {
      return
    }

    this.map.panTo(pointForLocation(currentLocation), {
      animate: options.animate ?? false,
      duration: 0.35,
    })
  }

  focusLocationSelection(locationId, options = {}) {
    if (!locationId) {
      return
    }

    const selectedRoute = this.state?.available_routes?.find(
      (route) => route.destination_location_id === locationId
    )

    if (selectedRoute) {
      this.focusRouteById(selectedRoute.id, options)
      return
    }

    const location = this.locationById(locationId)

    if (!location) {
      return
    }

    this.map.panTo(pointForLocation(location), {
      animate: options.animate ?? false,
      duration: 0.35,
    })
  }

  focusJourneyRoute(options = {}) {
    const routeId = this.state?.active_journey?.route_id

    if (!routeId) {
      return
    }

    this.focusRouteById(routeId, options)
  }

  focusRouteById(routeId, options = {}) {
    const route = this.state?.map?.routes?.find((item) => item.id === routeId)

    if (!route) {
      return
    }

    const origin = this.locationById(route.origin_location_id)
    const destination = this.locationById(route.destination_location_id)

    if (!origin || !destination) {
      return
    }

    const bounds = L.latLngBounds([pointForLocation(origin), pointForLocation(destination)])

    this.map.fitBounds(bounds, {
      animate: options.animate ?? false,
      duration: 0.45,
      paddingTopLeft: [24, 24],
      paddingBottomRight: [24, 220],
      maxZoom: -0.2,
    })
  }

  renderSheet() {
    if (!this.sheetEl) {
      return
    }

    if (this.loading && !this.state) {
      this.sheetEl.innerHTML = `
        <div class="play-strip play-strip--loading">
          <div class="play-strip__title">Загрузка карты...</div>
        </div>
      `
      return
    }

    if (!this.state) {
      this.sheetEl.innerHTML = `
        <div class="play-strip play-strip--error">
          <div class="play-strip__title">Карта недоступна</div>
          <div class="play-strip__meta">${this.errorMessage}</div>
        </div>
      `
      return
    }

    const currentLocationName = this.state.current_location?.name || "Неизвестная точка"
    const resetButton =
      this.state.demo?.reset_available
        ? `
          <button
            type="button"
            class="play-strip__ghost"
            data-action="reset-demo"
            ${this.pendingAction ? "disabled" : ""}
          >
            ${this.pendingAction === "reset" ? "Сброс..." : "Сбросить демо"}
          </button>
        `
        : ""

    const alert = this.errorMessage
      ? `<div class="play-strip__alert" role="alert">${this.errorMessage}</div>`
      : ""

    if (this.state.active_journey) {
      const journey = this.state.active_journey

      this.sheetEl.innerHTML = `
        <div class="play-strip">
          ${alert}
          <div class="play-strip__header">
            <div>
              <div class="play-strip__kicker">В пути</div>
              <div class="play-strip__title">${journey.from_name} → ${journey.to_name}</div>
              <div class="play-strip__meta">${formatDuration(journey.remaining_seconds)} • ${journey.remaining_game_days} игровых дн.</div>
            </div>
            ${resetButton}
          </div>

          <div class="play-strip__progress">
            <span class="play-strip__progress-fill" style="width:${journey.percent_complete}%"></span>
          </div>
        </div>
      `

      return
    }

    const selected = this.selectedTravelOption()
    const utilitySpells = this.state.magic?.utility_spells || []
    const utilityButtons = utilitySpells
      .map(
        (spell) => `
          <button
            type="button"
            class="play-strip__route"
            data-action="cast-utility-spell"
            data-spell-id="${spell.id}"
            ${this.pendingAction ? "disabled" : ""}
          >
            ${this.pendingAction === `utility:${spell.id}` ? "Чары..." : spell.name}
          </button>
        `
      )
      .join("")

    const utilityPanel =
      this.state.client?.can_cast_utility_spell && utilityButtons
        ? `
          <div class="play-strip__meta">
            Утилитарные чары · ${this.state.dungeon?.dungeon_name || "Подземелье"} · ${this.state.dungeon?.current_node_name || "узел"}
          </div>
          <div class="play-strip__routes">${utilityButtons}</div>
        `
        : ""

    const routeButtons = (this.state.available_routes || [])
      .map(
        (route) => `
          <button
            type="button"
            class="play-strip__route${selected?.id === route.id ? " play-strip__route--active" : ""}"
            data-action="pick-route"
            data-destination-id="${route.destination_location_id}"
          >
            ${route.destination_name}
          </button>
        `
      )
      .join("")

    this.sheetEl.innerHTML = `
      <div class="play-strip">
        ${alert}
        <div class="play-strip__header">
          <div>
            <div class="play-strip__kicker">${currentLocationName}</div>
            <div class="play-strip__title">${selected ? selected.destination_name : "Выберите маршрут"}</div>
            <div class="play-strip__meta">
              ${
                selected
                  ? `${selected.total_game_days} дн. • ${selected.required_food_units} паёк • ${riskLabel(selected.risk_level)}`
                  : `${(this.state.available_routes || []).length} доступных переходов`
              }
            </div>
          </div>
          ${resetButton}
        </div>

        <div class="play-strip__routes">${routeButtons}</div>
        ${utilityPanel}

        ${
          selected
            ? `
              <div class="play-strip__actions">
                <button
                  type="button"
                  class="play-strip__primary"
                  data-action="start-route"
                  data-route-id="${selected.id}"
                  ${this.pendingAction ? "disabled" : ""}
                >
                  ${this.pendingAction === "travel" ? "Прокладываем..." : "Начать переход"}
                </button>
              </div>
            `
            : ""
        }
      </div>
    `
  }

  showScreen(name) {
    this.screen = name
    if (name === "map") {
      this.screenEl.style.display = "none"
      this.sheetEl.style.display = ""
      this.renderSheet()
    } else {
      this.sheetEl.style.display = "none"
      this.screenEl.style.display = ""
      if (name === "location") this.renderLocationScreen()
      else if (name === "base") this.renderBaseScreen()
    }
  }

  locationContentFor(location) {
    const kind = location?.kind || "wilderness"
    const name = location?.name || "Место"

    const byKind = {
      city: {
        kicker: "Безопасная зона",
        body: "В воздухе витает запах свежего хлеба и кузнечного угля. Горожане спешат по делам. Торговцы зазывают у лавок.",
        actions: [
          { label: "В Академию", hint: "учебные залы", accent: true, href: "/academy/bulletin-board" },
          { label: "На рынок", hint: "торговля", stub: true },
          { label: "В таверну", hint: "новости и отдых", stub: true },
          { label: "Обратно на карту", back: true },
        ],
      },
      tower: {
        kicker: "Магическая зона",
        body: "Воздух звенит, как натянутая струна. Камни у входа тёплые на ощупь. Здесь работает магия — единственное место в округе, где это возможно.",
        actions: [
          { label: "Войти в Башню", hint: "подземелье и бои", accent: true, stub: true },
          { label: "Найти отряд", hint: "совместный поход", stub: true },
          { label: "Библиотека Башни", hint: "свитки и знания", stub: true },
          { label: "Обратно на карту", back: true },
        ],
      },
      base: {
        kicker: "Ваша база",
        body: "Скрипит знакомая калитка. Всё на месте — снаряжение, запасы, заготовки. Здесь можно отдохнуть и подготовиться.",
        actions: [
          { label: "Войти в дом", hint: "запасы и мастерская", accent: true, screen: "base" },
          { label: "Обратно на карту", back: true },
        ],
      },
      wilderness: {
        kicker: "Дикая местность",
        body: "Ветер гуляет по открытой равнине. Вдали что-то движется. Дорога уходит в обе стороны.",
        actions: [
          { label: "Добыча ресурсов", hint: "обыскать округу", stub: true },
          { label: "Разбить лагерь", hint: "отдых и припасы", stub: true },
          { label: "Обратно на карту", back: true },
        ],
      },
      dungeon_entrance: {
        kicker: "Вход в подземелье",
        body: "Тёмный зев входа. Откуда-то снизу доносится далёкий гул. Запах сырого камня и старого дыма.",
        actions: [
          { label: "Войти в подземелье", hint: "опасно в одиночку", accent: true, stub: true },
          { label: "Подождать отряд", hint: "у входа", stub: true },
          { label: "Обратно на карту", back: true },
        ],
      },
    }

    return { name, ...(byKind[kind] || byKind.wilderness) }
  }

  renderLocationScreen() {
    const location = this.currentLocation()
    const content = this.locationContentFor(location)

    const actionButtons = content.actions
      .map((a) => {
        let attrs = ""
        if (a.back) attrs = `data-action="loc-back"`
        else if (a.screen) attrs = `data-action="loc-go-screen" data-screen="${a.screen}"`
        else if (a.href) attrs = `data-action="loc-go-href" data-href="${a.href}"`
        else attrs = `data-action="loc-stub" disabled`

        return `
          <button type="button" class="play-loc__action${a.accent ? " play-loc__action--primary" : ""}" ${attrs}>
            <span class="play-loc__action-label">${a.label}</span>
            ${a.hint ? `<span class="play-loc__action-hint">${a.hint}</span>` : ""}
          </button>
        `
      })
      .join("")

    this.screenEl.innerHTML = `
      <div class="play-loc">
        <div class="play-loc__hero">
          <div class="play-loc__hero-kicker">${content.kicker}</div>
          <div class="play-loc__hero-title">${content.name}</div>
        </div>
        <div class="play-loc__body">
          <p class="play-loc__text">${content.body}</p>
          <div class="play-loc__divider"></div>
          <div class="play-loc__actions">${actionButtons}</div>
        </div>
      </div>
    `
  }

  renderBaseScreen() {
    const supplies = this.state?.supplies || {}
    const foodUnits = supplies.food_units_available ?? 0
    const carriedWeight = supplies.carried_weight ?? 0
    const carryCapacity = supplies.carry_capacity ?? 20

    const tiles = [
      { icon: "circle", title: "Круг призыва", sub: "Создание заклинаний", accent: true, stub: true },
      { icon: "book", title: "Полки с гримуарами", sub: "Зарядить заклинания", stub: true },
      { icon: "chest", title: "Сундук", sub: `${carriedWeight}/${carryCapacity} кг снаряжения`, stub: true },
      { icon: "alembic", title: "Алхимический стол", sub: "Варка зелий", stub: true },
      { icon: "forge", title: "Мастерская", sub: "Починка и ремёсла", stub: true },
      { icon: "bed", title: "Кровать", sub: "Отдохнуть до рассвета", stub: true },
    ]
      .map((t) => this.baseTile(t))
      .join("")

    this.screenEl.innerHTML = `
      <div class="play-loc">
        <div class="play-loc__hero">
          <div class="play-loc__hero-kicker">Ваша база</div>
          <div class="play-loc__hero-title">${this.currentLocation()?.name || "База"}</div>
        </div>
        <div class="play-loc__body">
          <div class="play-base__meta">${foodUnits} дн. припасов · ${carriedWeight}/${carryCapacity} кг</div>
          <div class="play-base__tiles">${tiles}</div>
          <div class="play-loc__divider"></div>
          <button type="button" class="play-loc__action" data-action="base-back">
            <span class="play-loc__action-label">Выйти во двор</span>
          </button>
        </div>
      </div>
    `
  }

  baseTile({ icon, title, sub, accent, stub, href }) {
    const action = href
      ? `data-action="loc-go-href" data-href="${href}"`
      : stub
        ? `data-action="base-stub" disabled`
        : ""
    return `
      <button type="button" class="play-base__tile${accent ? " play-base__tile--accent" : ""}" ${action}>
        <div class="play-base__tile-icon">${this.tileIconSvg(icon)}</div>
        <div class="play-base__tile-copy">
          <div class="play-base__tile-title">${title}</div>
          <div class="play-base__tile-sub">${sub}</div>
        </div>
        <svg class="play-base__tile-chevron" width="14" height="14" viewBox="0 0 24 24" fill="none">
          <path d="M9 6l6 6-6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
    `
  }

  tileIconSvg(icon) {
    const icons = {
      circle: `<svg width="22" height="22" viewBox="-11 -11 22 22" fill="none" stroke="currentColor">
        <circle r="9" stroke-width="1"/>
        <circle r="6.5" stroke-width="0.7" stroke-dasharray="1 1.5"/>
        <circle r="4" stroke-width="0.7"/>
        <polygon points="0,-3 2.6,1.5 -2.6,1.5" stroke-width="0.7"/>
      </svg>`,
      book: `<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor">
        <rect x="3" y="4" width="6" height="14" rx="1" stroke-width="1"/>
        <rect x="10" y="2" width="5" height="16" rx="1" stroke-width="1"/>
        <rect x="16" y="5" width="3" height="13" rx="0.5" stroke-width="1"/>
        <line x1="5" y1="8" x2="7" y2="8" stroke-width="0.7"/>
        <line x1="12" y1="6" x2="14" y2="6" stroke-width="0.7"/>
      </svg>`,
      chest: `<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor">
        <rect x="2" y="9" width="18" height="10" rx="1" stroke-width="1"/>
        <path d="M2 9 Q11 5 20 9" stroke-width="1"/>
        <line x1="2" y1="13" x2="20" y2="13" stroke-width="0.7"/>
        <rect x="9" y="11" width="4" height="4" rx="0.5" stroke-width="0.8"/>
      </svg>`,
      alembic: `<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor">
        <path d="M8 3h6v5l4 9a2 2 0 01-2 3H6a2 2 0 01-2-3l4-9V3z" stroke-width="1"/>
        <line x1="7.5" y1="13" x2="14.5" y2="13" stroke-width="0.7"/>
      </svg>`,
      forge: `<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor">
        <path d="M4 18h14" stroke-width="1"/>
        <path d="M7 18v-7L4 8l4-4 9 9-2 2H7" stroke-width="1"/>
      </svg>`,
      bed: `<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor">
        <rect x="2" y="11" width="18" height="7" rx="1" stroke-width="1"/>
        <path d="M2 11V7a2 2 0 012-2h3a2 2 0 012 2v4" stroke-width="1"/>
        <line x1="2" y1="15" x2="20" y2="15" stroke-width="0.7"/>
      </svg>`,
    }
    return icons[icon] || ""
  }
}

export function mountPlayHub() {
  const root = document.querySelector("[data-play-hub-root]")

  if (!root) {
    return
  }

  new PlayHubApp(root).mount()
}

export const PlayHubHook = {
  mounted() {
    this.playHub = new PlayHubApp(this.el)
    this.playHub.mount()
  },

  destroyed() {
    this.playHub?.destroy()
    this.playHub = null
  },
}
