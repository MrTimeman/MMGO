// SpellCircleHook — 8 orbital slot buttons around a runic circle.
// Slots are editable text inputs (human-written words).
// All 7 required slots filled → circle charges (cyan glow, rune rings animate).

const NS = 'http://www.w3.org/2000/svg'

// Default slot definitions (server can override)
const DEFAULT_SLOTS = [
  { key: 'school',  label: 'Школа',   required: true  },
  { key: 'type',    label: 'Тип',     required: true  },
  { key: 'element', label: 'Элемент', required: true  },
  { key: 'aspect',  label: 'Аспект',  required: true  },
  { key: 'effect',  label: 'Эффект',  required: true  },
  { key: 'time',    label: 'Время',   required: true  },
  { key: 'mana',    label: 'Мана',    required: true  },
  { key: 'base',    label: 'Основа',  required: false },
]

const RUNE_STR = 'ᚠ ᚢ ᚦ ᚨ ᚱ ᚲ ᚹ ᚺ ᛊ ᛏ ᛒ ᛖ ᛗ ᛚ ᛜ ᛞ ᛟ · '

function svgEl(tag, attrs = {}) {
  const el = document.createElementNS(NS, tag)
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
  return el
}

function slotPos(i) {
  const a = i * 45 * (Math.PI / 180)
  return {
    left: `calc(${50 + 37.5 * Math.sin(a)}% - 8.125%)`,
    top:  `calc(${50 - 37.5 * Math.cos(a)}% - 8.125%)`,
  }
}

function orbitCenter(i) {
  const a = i * 45 * (Math.PI / 180)
  return { left: `${50 + 37.5 * Math.sin(a)}%`, top: `${50 - 37.5 * Math.cos(a)}%` }
}

function buildRingsSVG(charged) {
  const svg = svgEl('svg', { viewBox: '0 0 340 340', class: 'sc__rings' })

  const defs = svgEl('defs')
  ;[155, 125, 95].forEach((r, i) => {
    defs.appendChild(svgEl('path', {
      id: `sc-rp-${i}`,
      d: `M 170,${170 - r} A ${r},${r} 0 1 1 ${170 - 0.001},${170 - r}`,
    }))
  })
  svg.appendChild(defs)

  // Connector lines
  const lc = charged ? 'rgba(0,212,255,0.35)' : 'rgba(0,212,255,0.07)'
  const lw = charged ? '1' : '0.6'
  for (const [x1,y1,x2,y2] of [[170,25,170,315],[25,170,315,170],[55,55,285,285],[285,55,55,285]]) {
    svg.appendChild(svgEl('line', { x1, y1, x2, y2, stroke: lc, 'stroke-width': lw }))
  }

  // 3 concentric rune rings
  ;[155, 125, 95].forEach((r, i) => {
    svg.appendChild(svgEl('circle', {
      cx: 170, cy: 170, r,
      fill: 'none',
      stroke: charged ? 'rgba(0,212,255,0.28)' : 'rgba(0,212,255,0.06)',
      'stroke-width': '0.8',
    }))

    const text = svgEl('text', { class: `sc__ring-text sc__ring-text--${i}` })
    const tp   = svgEl('textPath', { href: `#sc-rp-${i}` })
    const repeats = Math.ceil((2 * Math.PI * r) / 14) + 4
    tp.textContent = (RUNE_STR.repeat(Math.ceil(repeats / RUNE_STR.length) + 1)).slice(0, repeats)
    text.appendChild(tp)
    svg.appendChild(text)
  })

  // Center circle
  svg.appendChild(svgEl('circle', {
    cx: 170, cy: 170, r: 44,
    fill: charged ? 'rgba(0,212,255,0.05)' : 'rgba(8,10,22,0.95)',
    stroke: charged ? 'rgba(0,212,255,0.65)' : 'rgba(0,212,255,0.14)',
    'stroke-width': charged ? '1.5' : '0.8',
  }))

  return svg
}

export const SpellCircleHook = {
  mounted() {
    this._sel  = {}        // { [key]: value }
    this._name = ''
    this._activeSlot = null
    this._slots  = DEFAULT_SLOTS

    this.handleEvent('spell_circle_init', data => {
      if (data.slots) {
        this._slots = data.slots.map(s => ({ key: s.key, label: s.label, required: s.required }))
      }
      if (data.current) Object.assign(this._sel, data.current)
      this.render()
    })
    this.pushEvent('hook_mounted', { hook: 'SpellCircle' })
  },

  render() {
    const root = this.el
    root.innerHTML = ''
    root.className = 'sc'

    const charged = this._slots.filter(s => s.required).every(s => this._sel[s.key])

    // ── Circle ───────────────────────────────────────────────────────────────
    const circle = document.createElement('div')
    circle.className = `sc__circle${charged ? ' sc__circle--charged' : ''}`

    circle.appendChild(buildRingsSVG(charged))

    // 8 slot buttons
    this._slots.forEach((slot, i) => {
      const pos   = slotPos(i)
      const value = this._sel[slot.key] ?? ''

      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = [
        'sc__slot',
        value ? 'sc__slot--filled' : '',
        this._activeSlot === slot.key ? 'sc__slot--active' : '',
        !slot.required ? 'sc__slot--optional' : '',
      ].filter(Boolean).join(' ')
      btn.style.left = pos.left
      btn.style.top  = pos.top

      const lbl = document.createElement('span')
      lbl.className = 'sc__slot-label'
      lbl.textContent = slot.label

      const val = document.createElement('span')
      val.className = 'sc__slot-value'
      val.textContent = value ? value.slice(0, 6) : '—'

      btn.appendChild(lbl)
      btn.appendChild(val)

      btn.addEventListener('click', () => {
        this._activeSlot = this._activeSlot === slot.key ? null : slot.key
        this.render()
      })

      circle.appendChild(btn)
    })

    // Center rune (when charged)
    const center = document.createElement('div')
    center.className = 'sc__center'
    if (charged) {
      const rune = document.createElement('span')
      rune.className = 'sc__center-rune'
      rune.textContent = 'ᚨ'
      center.appendChild(rune)
    }
    circle.appendChild(center)

    // Particles (charged state)
    if (charged) {
      for (let i = 0; i < 8; i++) {
        const c = orbitCenter(i)
        const p = document.createElement('div')
        p.className = 'sc__particle'
        p.style.left = c.left
        p.style.top  = c.top
        p.style.animationDelay = `${-(i * 0.375)}s`
        circle.appendChild(p)
      }
    }

    root.appendChild(circle)

    // ── Input sheet ─────────────────────────────────────────────────────────
    if (this._activeSlot) {
      root.appendChild(this._buildInputSheet(this._activeSlot))
    }

    // ── Footer (name + cast) ─────────────────────────────────────────────────
    const footer = document.createElement('div')
    footer.className = 'sc__footer'

    const inp = document.createElement('input')
    inp.className  = 'sc__name-input'
    inp.type       = 'text'
    inp.placeholder = 'Название заклинания...'
    inp.value      = this._name
    inp.addEventListener('input', e => { this._name = e.target.value })
    footer.appendChild(inp)

    const btn = document.createElement('button')
    btn.className = `sc__compile${charged ? ' sc__compile--ready' : ''}`
    btn.type      = 'button'
    btn.disabled  = !charged
    btn.textContent = 'Сотворить заклинание'
    btn.addEventListener('click', () => {
      if (!charged) return
      btn.classList.add('sc__compile--flash')
      setTimeout(() => this.pushEvent('spell_compile', { ...this._sel, name: this._name }), 300)
    })
    footer.appendChild(btn)

    root.appendChild(footer)
  },

  _buildInputSheet(key) {
    const slot = this._slots.find(s => s.key === key)
    const sheet = document.createElement('div')
    sheet.className = 'sc__sheet'

    const title = document.createElement('div')
    title.className  = 'sc__sheet-title'
    title.textContent = slot?.label ?? key
    sheet.appendChild(title)

    const input = document.createElement('input')
    input.type = 'text'
    input.className = 'sc__sheet-input'
    input.placeholder = 'Введите значение...'
    input.value = this._sel[key] ?? ''
    input.addEventListener('input', e => {
      this._sel[key] = e.target.value
    })
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter') {
        this._activeSlot = null
        this.render()
      }
    })
    sheet.appendChild(input)

    const actions = document.createElement('div')
    actions.className = 'sc__sheet-actions'

    const accept = document.createElement('button')
    accept.type = 'button'
    accept.className = 'sc__sheet-btn sc__sheet-btn--ok'
    accept.textContent = 'ОК'
    accept.addEventListener('click', () => {
      this._activeSlot = null
      this.render()
    })

    const clear = document.createElement('button')
    clear.type = 'button'
    clear.className = 'sc__sheet-btn'
    clear.textContent = 'Очистить'
    clear.addEventListener('click', () => {
      delete this._sel[key]
      this._activeSlot = null
      this.render()
    })

    actions.appendChild(accept)
    actions.appendChild(clear)
    sheet.appendChild(actions)

    return sheet
  },

  destroyed() {},
}
