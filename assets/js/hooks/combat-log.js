// CombatLogHook — the narration region is the only window players get onto
// combat resolution (GDD §3.4), so its behaviour is atmospheric, not
// utilitarian. This hook is pure progressive enhancement: the prose is fully
// present in the DOM without it (server-rendered, CSS handles the fade-in of
// each newly-appended turn). When registered, the hook keeps the newest turn
// in view and gives the latest block a brief "reading light" sweep so the eye
// lands on the fresh text.
//
// The log container uses phx-update="append", so existing turn blocks are
// never re-rendered — safe for us to touch their classes without fighting
// LiveView's diff.

function prefersReducedMotion() {
  return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

export const CombatLogHook = {
  mounted() {
    // The server fires this the instant a resolved turn is appended.
    this.handleEvent('combat_reveal', () => this._onNewTurn())
    this._scrollToNewest(false)
  },

  updated() {
    // Fallback: even without the event, follow the growing log.
    this._scrollToNewest(true)
  },

  _onNewTurn() {
    // Let the appended node land in the DOM first.
    requestAnimationFrame(() => {
      this._markNewest()
      this._scrollToNewest(true)
    })
  },

  _markNewest() {
    const blocks = this.el.querySelectorAll('.cbt-turn')
    if (!blocks.length) return
    const latest = blocks[blocks.length - 1]
    blocks.forEach((b) => b.classList.remove('cbt-turn--focus'))
    if (prefersReducedMotion()) return
    latest.classList.add('cbt-turn--focus')
    // The sweep is a one-shot; drop the class so re-entry can replay it.
    window.setTimeout(() => latest.classList.remove('cbt-turn--focus'), 1600)
  },

  _scrollToNewest(smooth) {
    // Prefer scrolling the newest turn (or the outcome) into view over a raw
    // scrollTop jump — reads as the camera panning down to what just happened.
    const target =
      this.el.querySelector('#cbt-outcome') ||
      this.el.querySelector('.cbt-turn:last-of-type')

    const behavior = smooth && !prefersReducedMotion() ? 'smooth' : 'auto'

    requestAnimationFrame(() => {
      if (target && target.scrollIntoView) {
        target.scrollIntoView({ behavior, block: 'end' })
      } else {
        this.el.scrollTop = this.el.scrollHeight
      }
    })
  },
}
