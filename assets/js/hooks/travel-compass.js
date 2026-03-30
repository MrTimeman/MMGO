// TravelCompassHook — Compact compass toggle. Click to expand journey details.
// The needle smoothly rotates to show travel direction.

import { h } from './utils'

export const TravelCompassHook = {
  mounted() {
    this._open    = false
    this._bearing = 0
    this._targetBearing = 0
    this._journey = null
    this._needleEl = null
    this.handleEvent('compass_update', ({ bearing, journey }) => {
      this._targetBearing = bearing ?? 0
      this._journey = journey ?? null
      this._animateNeedle()
      this.render()
    })
    this.pushEvent('hook_mounted', { hook: 'TravelCompass' })
  },

  _animateNeedle() {
    // Smooth needle rotation via CSS transition (applied after render)
    const from = this._bearing
    const to   = this._targetBearing
    // Take the shortest rotation path
    let delta = ((to - from + 540) % 360) - 180
    this._bearing = from + delta
  },

  render() {
    const root = this.el
    root.innerHTML = ''
    root.className = `cmp${this._open ? ' cmp--open' : ''}`

    const toggle = h('button', { class: 'cmp__toggle', type: 'button',
                                  title: this._journey ? `→ ${this._journey.to_name}` : 'Нет путешествия' })
    toggle.appendChild(this._compassSVG(this._bearing, 44))
    if (this._journey) {
      toggle.appendChild(h('span', { class: 'cmp__toggle-dest' }, this._journey.to_name))
    }
    toggle.addEventListener('click', () => {
      this._open = !this._open
      this.render()
    })
    root.appendChild(toggle)

    if (this._open) {
      const panel = h('div', { class: 'cmp__panel' })

      if (!this._journey) {
        panel.appendChild(h('div', { class: 'cmp__idle' }, 'Нет активного путешествия'))
      } else {
        const j = this._journey

        const route = h('div', { class: 'cmp__route' })
        route.appendChild(h('span', {}, j.from_name))
        route.appendChild(h('span', { class: 'cmp__arrow' }, '→'))
        route.appendChild(h('span', {}, j.to_name))
        panel.appendChild(route)

        const total = j.travel_days ?? 1
        const remaining = j.days_remaining ?? 0
        const pct = Math.round(((total - remaining) / total) * 100)
        panel.appendChild(this._stat(`Дней в пути: ${total - remaining} из ${total}`, pct, ''))

        const foodPct = Math.round(((j.food_units ?? 0) / (j.food_capacity || 1)) * 100)
        panel.appendChild(this._stat(`Припасы: ${j.food_units} / ${j.food_capacity}`, foodPct, 'food'))
      }

      root.appendChild(panel)
    }
  },

  _stat(label, pct, mod) {
    const row = h('div', { class: 'cmp__stat' })
    row.appendChild(h('span', { class: 'cmp__stat-label' }, label))
    const bar = h('div', { class: 'cmp__bar-wrap' })
    const fill = h('div', { class: `cmp__bar-fill${mod ? ' cmp__bar-fill--' + mod : ''}` })
    // Animate from 0
    requestAnimationFrame(() => { fill.style.width = `${Math.min(pct, 100)}%` })
    bar.appendChild(fill)
    row.appendChild(bar)
    return row
  },

  _compassSVG(bearing, size) {
    const ns = 'http://www.w3.org/2000/svg'
    const svg = document.createElementNS(ns, 'svg')
    svg.setAttribute('viewBox', '0 0 44 44')
    svg.setAttribute('width',  String(size))
    svg.setAttribute('height', String(size))
    svg.setAttribute('class', 'cmp__svg')

    const ring = document.createElementNS(ns, 'circle')
    ring.setAttribute('cx', '22'); ring.setAttribute('cy', '22'); ring.setAttribute('r', '20')
    ring.setAttribute('fill', 'none')
    ring.setAttribute('stroke', 'var(--color-border)')
    ring.setAttribute('stroke-width', '1')
    svg.appendChild(ring)

    for (let i = 0; i < 8; i++) {
      const a = (i * 45 - 90) * Math.PI / 180
      const isMajor = i % 2 === 0
      const r1 = isMajor ? 14 : 16
      const line = document.createElementNS(ns, 'line')
      line.setAttribute('x1', (22 + r1 * Math.cos(a)).toFixed(1))
      line.setAttribute('y1', (22 + r1 * Math.sin(a)).toFixed(1))
      line.setAttribute('x2', (22 + 19 * Math.cos(a)).toFixed(1))
      line.setAttribute('y2', (22 + 19 * Math.sin(a)).toFixed(1))
      line.setAttribute('stroke', 'var(--color-border)')
      line.setAttribute('stroke-width', isMajor ? '1.5' : '0.8')
      svg.appendChild(line)
    }

    const n = document.createElementNS(ns, 'text')
    n.setAttribute('x', '22'); n.setAttribute('y', '7')
    n.setAttribute('text-anchor', 'middle'); n.setAttribute('dominant-baseline', 'middle')
    n.setAttribute('font-size', '6'); n.setAttribute('fill', 'var(--color-text-muted)')
    n.textContent = 'С'
    svg.appendChild(n)

    // Needle — uses CSS transition for smooth rotation
    const g = document.createElementNS(ns, 'g')
    g.setAttribute('class', 'cmp__needle')
    g.style.transform = `rotate(${bearing}deg)`
    g.style.transformOrigin = '22px 22px'

    const nPoly = document.createElementNS(ns, 'polygon')
    nPoly.setAttribute('points', '22,5 19.5,22 22,20 24.5,22')
    nPoly.setAttribute('fill', 'var(--color-danger)')
    g.appendChild(nPoly)

    const sPoly = document.createElementNS(ns, 'polygon')
    sPoly.setAttribute('points', '22,39 19.5,22 22,24 24.5,22')
    sPoly.setAttribute('fill', 'var(--color-text-muted)')
    g.appendChild(sPoly)

    svg.appendChild(g)

    const dot = document.createElementNS(ns, 'circle')
    dot.setAttribute('cx', '22'); dot.setAttribute('cy', '22'); dot.setAttribute('r', '2.5')
    dot.setAttribute('fill', 'var(--color-accent)')
    svg.appendChild(dot)

    return svg
  },

  destroyed() {},
}
