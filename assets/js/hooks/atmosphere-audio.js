const STORAGE_KEY = "mmgo:atmosphere-audio-enabled"

function readEnabledPreference() {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "true"
  } catch (_error) {
    return false
  }
}

function writeEnabledPreference(enabled) {
  try {
    window.localStorage.setItem(STORAGE_KEY, String(enabled))
  } catch (_error) {
    // Storage can be unavailable in a private or embedded webview. The sound
    // control still works for this page; it simply will not persist.
  }
}

// Audio is intentionally progressive enhancement. Semantic cues are rendered
// by the server as data attributes even if a deployment has no licensed asset,
// while this hook handles autoplay restrictions and the player's local choice.
export const AtmosphereAudioHook = {
  mounted() {
    this.audio = this.el.querySelector("#atmosphere-audio-player")
    this.button = this.el.querySelector("[data-atmosphere-toggle]")
    this.status = this.el.querySelector("[data-atmosphere-status]")
    this.enabled = readEnabledPreference()
    this.currentSource = null
    this.currentKind = null
    this.eventKey = null
    this.completedEventKey = null

    this.onToggle = () => {
      if (this.button?.disabled) return

      this.enabled = !this.enabled
      writeEnabledPreference(this.enabled)
      this.sync()
    }

    this.onEnded = () => {
      if (this.currentKind === "event" && this.eventKey) {
        this.completedEventKey = this.eventKey
        this.currentSource = null
        this.currentKind = null
        this.sync()
      }
    }

    this.button?.addEventListener("click", this.onToggle)
    this.audio?.addEventListener("ended", this.onEnded)
    this.sync()
  },

  updated() {
    this.sync()
  },

  destroyed() {
    this.button?.removeEventListener("click", this.onToggle)
    this.audio?.removeEventListener("ended", this.onEnded)
    this.stop()
  },

  sync() {
    if (!this.audio || !this.button || !this.status) return

    const eventKey = this.currentEventKey()
    if (eventKey !== this.eventKey) {
      this.eventKey = eventKey
      this.completedEventKey = null
    }

    const playback = this.playbackForState()
    const label = this.el.dataset.label || "мир"
    const available = Boolean(playback.source)

    this.button.disabled = !available

    if (!available) {
      this.stop()
      this.button.setAttribute("aria-pressed", "false")
      this.status.textContent = "Звук: запись не подключена"
      return
    }

    if (!this.enabled) {
      this.stop()
      this.button.setAttribute("aria-pressed", "false")
      this.status.textContent = `Звук мира: выкл. (${label})`
      return
    }

    this.button.setAttribute("aria-pressed", "true")
    this.status.textContent = `Звук мира: вкл. (${label})`
    this.play(playback)
  },

  currentEventKey() {
    const cue = this.el.dataset.majorEventCue || ""
    const source = this.el.dataset.eventSource || ""
    return cue && source ? `${cue}:${source}` : null
  },

  playbackForState() {
    const eventSource = this.el.dataset.eventSource || null
    const ambientSource = this.el.dataset.ambientSource || null
    const activeSource = this.el.dataset.activeSource || null

    if (eventSource && this.eventKey !== this.completedEventKey) {
      return { source: eventSource, loop: false, kind: "event" }
    }

    if (ambientSource) {
      return { source: ambientSource, loop: true, kind: "ambient" }
    }

    if (activeSource) {
      return {
        source: activeSource,
        loop: this.el.dataset.loop === "true",
        kind: "active",
      }
    }

    return { source: null, loop: false, kind: null }
  },

  play({ source, loop, kind }) {
    const sourceChanged = this.currentSource !== source || this.audio.loop !== loop

    if (sourceChanged) {
      this.audio.pause()
      this.audio.currentTime = 0
      this.audio.src = source
      this.audio.loop = loop
      this.audio.volume = kind === "event" ? 0.55 : 0.28
      this.currentSource = source
      this.currentKind = kind
    }

    this.audio.play().catch(() => {
      // The toggle is a real user control, but embedded clients can still
      // require an additional gesture after navigation. Never surface this as
      // a game failure or disable the semantic scene.
      this.status.textContent = "Нажмите ещё раз, чтобы включить звук"
    })
  },

  stop() {
    if (!this.audio) return

    this.audio.pause()
    this.audio.currentTime = 0
    this.currentSource = null
    this.currentKind = null
  },
}
