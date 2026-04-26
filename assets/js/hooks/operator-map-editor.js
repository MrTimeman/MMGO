const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""

const formPayload = form =>
  Object.fromEntries(Array.from(new FormData(form).entries()).filter(([_key, value]) => value !== ""))

const slugify = value =>
  value
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/gi, "-")
    .replace(/^-+|-+$/g, "")

export const OperatorMapEditorHook = {
  mounted() {
    this.mode = "pin"
    this.routePoints = []
    this.canvas = this.el.querySelector("#operator-map-canvas")
    this.draft = this.el.querySelector("#operator-draft-route")
    this.locationForm = this.el.querySelector("#operator-location-form")
    this.routeForm = this.el.querySelector("#operator-route-form")

    this.bindModes()
    this.bindCanvas()
    this.bindForms()
    this.updateDraft()
  },

  bindModes() {
    this.el.querySelectorAll("[data-editor-mode]").forEach(button => {
      button.addEventListener("click", () => {
        this.mode = button.dataset.editorMode
        this.el.querySelectorAll("[data-editor-mode]").forEach(btn => btn.classList.toggle("is-active", btn === button))
        this.message(this.mode === "pin" ? "Клик по карте поставит координаты новой точки." : "Кликните две точки, затем добавляйте изгибы кликом по карте.")
      })
    })

    this.el.querySelector("[data-clear-route]")?.addEventListener("click", () => {
      this.routePoints = []
      this.routeForm?.querySelector("[data-route-points]")?.setAttribute("value", "[]")
      this.updateDraft()
      this.message("Черновик дороги очищен.")
    })
  },

  bindCanvas() {
    this.canvas?.addEventListener("click", event => {
      const pin = event.target.closest(".operator-map-pin")
      if (pin) {
        this.handlePin(pin)
        return
      }

      const point = this.eventPoint(event)
      if (this.mode === "pin") this.placePin(point)
      else this.addRoutePoint(point)
    })
  },

  bindForms() {
    this.el.querySelectorAll("form[data-api-path]").forEach(form => {
      form.addEventListener("submit", event => {
        event.preventDefault()
        this.submitForm(form)
      })
    })

    this.locationForm?.querySelector("[name='name']")?.addEventListener("input", event => {
      const slug = this.locationForm.querySelector("[name='slug']")
      if (slug && !slug.value) slug.value = slugify(event.target.value)
    })
  },

  handlePin(pin) {
    if (this.mode === "pin") {
      this.locationForm.querySelector("[name='name']").value = pin.dataset.locationName || ""
      this.locationForm.querySelector("[name='slug']").value = slugify(pin.dataset.locationName || "")
      this.locationForm.querySelector("[data-location-x]").value = pin.dataset.locationX || ""
      this.locationForm.querySelector("[data-location-y]").value = pin.dataset.locationY || ""
      this.message("Координаты точки загружены в форму.")
      return
    }

    const origin = this.routeForm.querySelector("[name='origin_location_id']")
    const destination = this.routeForm.querySelector("[name='destination_location_id']")

    if (!origin.value || origin.value === pin.dataset.locationId) {
      origin.value = pin.dataset.locationId
      this.routePoints = [{ x: Number(pin.dataset.locationX), y: Number(pin.dataset.locationY) }]
      this.message(`Начало дороги: ${pin.dataset.locationName}`)
    } else {
      destination.value = pin.dataset.locationId
      const end = { x: Number(pin.dataset.locationX), y: Number(pin.dataset.locationY) }
      this.routePoints = [this.routePoints[0], end].filter(Boolean)
      const name = this.routeForm.querySelector("[name='name']")
      if (name && !name.value) name.value = `${origin.selectedOptions[0]?.text || "Точка"} — ${pin.dataset.locationName}`
      this.message(`Конец дороги: ${pin.dataset.locationName}`)
    }

    this.persistRoutePoints()
    this.updateDraft()
  },

  placePin(point) {
    this.locationForm.querySelector("[data-location-x]").value = point.x
    this.locationForm.querySelector("[data-location-y]").value = point.y

    const name = this.locationForm.querySelector("[name='name']")
    const slug = this.locationForm.querySelector("[name='slug']")
    if (!name.value) name.value = `Новая точка ${point.x}:${point.y}`
    if (!slug.value) slug.value = slugify(name.value) || `loc-${point.x}-${point.y}`

    this.message(`Точка поставлена: ${point.x}, ${point.y}`)
  },

  addRoutePoint(point) {
    if (this.routePoints.length === 0) {
      this.message("Сначала выберите начальную точку дороги.")
      return
    }

    if (this.routePoints.length === 1) {
      this.message("Теперь выберите конечную точку дороги.")
      return
    }

    this.routePoints.splice(this.routePoints.length - 1, 0, point)
    this.persistRoutePoints()
    this.updateDraft()
    this.message(`Добавлен изгиб: ${point.x}, ${point.y}`)
  },

  eventPoint(event) {
    const rect = this.canvas.getBoundingClientRect()
    return {
      x: Math.round(((event.clientX - rect.left) / rect.width) * 2000),
      y: Math.round(((event.clientY - rect.top) / rect.height) * 2000),
    }
  },

  persistRoutePoints() {
    const input = this.routeForm?.querySelector("[data-route-points]")
    if (input) input.value = JSON.stringify(this.routePoints)
  },

  updateDraft() {
    if (!this.draft) return
    this.draft.setAttribute("points", this.routePoints.map(point => `${point.x},${point.y}`).join(" "))
  },

  message(text) {
    const message = this.el.querySelector("#operator-map-message")
    if (message) message.textContent = text
  },

  async submitForm(form) {
    if (form === this.locationForm) {
      const slug = form.querySelector("[name='slug']")
      const x = form.querySelector("[data-location-x]")?.value || Date.now()
      const y = form.querySelector("[data-location-y]")?.value || "0"
      if (slug && !slug.value) slug.value = `loc-${x}-${y}`
    }

    const button = form.querySelector("button[type='submit']")
    const label = button?.textContent
    if (button) {
      button.disabled = true
      button.textContent = "Сохраняем..."
    }

    try {
      const response = await fetch(form.dataset.apiPath, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-csrf-token": csrfToken(),
        },
        body: JSON.stringify(formPayload(form)),
      })
      const payload = await response.json()
      if (!response.ok || !payload.ok) throw new Error(payload.error || "Не удалось сохранить")
      window.location.reload()
    } catch (error) {
      this.message(error.message || "Не удалось сохранить")
    } finally {
      if (button) {
        button.disabled = false
        button.textContent = label
      }
    }
  },
}
