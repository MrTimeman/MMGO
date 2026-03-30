// EventScrollHook — Renders a location-based narrative event with selectable options.
// Behaves like a real scroll: content accumulates, never rewrites previous sections.

import { h } from './utils'

export const EventScrollHook = {
  mounted() {
    this._rendered = { title: null, body: null, options: false, result: false }
    this.handleEvent('event_scroll_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'EventScroll' })
  },

  render({ title, body, options = [], resolved_option, result_text }) {
    const root = this.el
    if (!root.classList.contains('evs')) {
      root.innerHTML = ''
      root.className = 'evs'
      this._rendered = { title: null, body: null, options: false, result: false }
    }

    // ── Title (once) ──────────────────────────────────────────────────────
    if (title && this._rendered.title !== title) {
      if (this._rendered.title !== null) {
        // Title changed = entirely new event, reset scroll
        root.innerHTML = ''
        this._rendered = { title: null, body: null, options: false, result: false }
      }
      const titleEl = h('div', { class: 'evs__title' }, title)
      root.appendChild(titleEl)
      this._rendered.title = title
    }

    // ── Body (once) ───────────────────────────────────────────────────────
    if (body && this._rendered.body !== body) {
      const bodyEl = h('div', { class: 'evs__body' }, body)
      root.appendChild(bodyEl)
      this._rendered.body = body
    }

    // ── Options (once, until resolved) ────────────────────────────────────
    if (!this._rendered.options && !resolved_option && options.length > 0) {
      const grid = h('div', { class: 'evs__options' })
      this._optionsEl = grid
      for (let i = 0; i < options.length; i++) {
        const opt = options[i]
        const btn = h('button', { class: 'evs__option', type: 'button' }, opt.label)
        btn.style.animationDelay = `${0.3 + i * 0.08}s`
        btn.addEventListener('click', () => {
          btn.classList.add('evs__option--chosen')
          grid.querySelectorAll('.evs__option').forEach(b => {
            if (b !== btn) b.classList.add('evs__option--dimmed')
          })
          setTimeout(() => this.pushEvent('event_option_select', { code: opt.code }), 400)
        })
        grid.appendChild(btn)
      }
      root.appendChild(grid)
      this._rendered.options = true
    }

    // ── Result (appended after choice) ────────────────────────────────────
    if (resolved_option && result_text && !this._rendered.result) {
      // Collapse options to just the chosen one
      if (this._optionsEl) {
        this._optionsEl.querySelectorAll('.evs__option').forEach(b => {
          if (!b.classList.contains('evs__option--chosen')) b.remove()
        })
        const chosen = this._optionsEl.querySelector('.evs__option--chosen')
        if (chosen) {
          chosen.classList.add('evs__option--resolved')
          chosen.disabled = true
        }
      }

      const result = h('div', { class: 'evs__result' }, result_text)
      root.appendChild(result)
      this._rendered.result = true
    }
  },

  destroyed() {},
}
