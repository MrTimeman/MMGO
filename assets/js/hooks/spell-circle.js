// SpellCircleHook — variable-count orbital slot medallions around a runic
// circle. Slots are either free-text (words the caster writes themselves)
// or a constrained choice (school, base spell) offered as a picker.
// A trained wizard gets the full circle; a self-taught caster gets a
// smaller one — the slot list is entirely server-driven, this hook just
// lays out however many it's given. Filling a slot is a quiet moment —
// ink catching gold leaf — and filling every required slot lights the
// whole circle, ready to create.

const NS = 'http://www.w3.org/2000/svg'

const RESULT_VERTEX_SHADER = `
attribute vec2 aPos;
varying vec2 vUv;

void main() {
  vUv = aPos * 0.5 + 0.5;
  gl_Position = vec4(aPos, 0.0, 1.0);
}
`

const RESULT_FRAGMENT_SHADER = `
precision highp float;

varying vec2 vUv;
uniform vec2 uSize;
uniform float uTime;
uniform float uExcitation;
uniform float uLegendaryTint;
uniform float uWhiteout;

const float ppi = 96.0;
const float tau = 6.28318530718;

float angularDistance(float a, float b) {
  return abs(atan(sin(a - b), cos(a - b)));
}

void main() {
  vec2 fragCoord = vUv * uSize;
  vec2 center = uSize * 0.5;
  vec2 p = (fragCoord - center) / (1.5 * ppi);
  p.x *= uSize.x / max(uSize.y, 1.0);

  float a = atan(p.x, p.y);
  float r = length(p);

  float time = uTime / 200.0;
  vec3 tint = vec3(0.25);
  tint.r += 1.0 * uLegendaryTint;
  tint.g += 0.6 * uLegendaryTint;
  tint.b += 0.25 * (1.0 - uLegendaryTint);

  float radialFade = smoothstep(1.35, 0.06, r);
  float outerFade = 1.0 - smoothstep(1.05, 1.46, r);
  float beamA = angularDistance(a, time * 2.6);
  float beamB = angularDistance(a, time * -1.7 + 2.18);
  float beamC = angularDistance(a, time * 1.2 + 4.35);
  float spokes =
    pow(1.0 - smoothstep(0.0, 0.095, beamA), 2.4) +
    pow(1.0 - smoothstep(0.0, 0.075, beamB), 2.0) * 0.72 +
    pow(1.0 - smoothstep(0.0, 0.06, beamC), 1.8) * 0.52;
  spokes *= radialFade * outerFade * (0.35 + uExcitation * 0.9);

  float core = smoothstep(0.34, 0.0, r) * (0.35 + uExcitation * 0.85);
  float halo = smoothstep(1.2, 0.0, r) * (0.08 + 0.28 * uExcitation);
  float white = smoothstep(0.68, 1.0, uWhiteout);

  vec3 color = tint * (spokes * 1.25 + halo * 0.65 + core * 0.9);
  color += vec3(1.0) * pow(clamp(spokes, 0.0, 1.0), 2.0) * uExcitation;
  color += vec3(1.0, 0.94, 0.76) * core * uExcitation;
  color = mix(color, vec3(1.0), white);

  float alpha = clamp(spokes + core * 0.82 + halo * 0.3 + white * 0.85, 0.0, 1.0);
  gl_FragColor = vec4(color, alpha);
}
`

const DEFAULT_SLOTS = [
  { key: 'actio',   label: 'Actio',   required: true,  kind: 'text' },
  { key: 'vis',     label: 'Vis',     required: false, kind: 'text' },
  { key: 'pretium', label: 'Pretium', required: false, kind: 'text' },
]

const RUNE_STR = 'ᚠ ᚢ ᚦ ᚨ ᚱ ᚲ ᚹ ᚺ ᛊ ᛏ ᛒ ᛖ ᛗ ᛚ ᛜ ᛞ ᛟ · '

function svgEl(tag, attrs = {}) {
  const el = document.createElementNS(NS, tag)
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
  return el
}

function smoothstep(edge0, edge1, value) {
  const x = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)))
  return x * x * (3 - 2 * x)
}

// Medallions are round hand-inked seals — the fewer the slots, the more
// room each one gets to breathe. Required slots (actio, schola) render a
// touch bigger, matching their heavier border weight in CSS.
function tileSize(total, required) {
  let base
  if (total <= 3) base = 30
  else if (total <= 5) base = 24
  else base = 19
  const w = required ? base * 1.15 : base
  return { w, h: w }
}

function slotPos(i, total, size) {
  const a = i * (360 / total) * (Math.PI / 180)
  const radius = 38
  return {
    left: `calc(${50 + radius * Math.sin(a)}% - ${size.w / 2}%)`,
    top:  `calc(${50 - radius * Math.cos(a)}% - ${size.h / 2}%)`,
  }
}

function orbitCenter(i, total) {
  const a = i * (360 / total) * (Math.PI / 180)
  return { left: `${50 + 37.5 * Math.sin(a)}%`, top: `${50 - 37.5 * Math.cos(a)}%` }
}

function svgOrbitPoint(i, total, radius = 112) {
  const a = i * (360 / total) * (Math.PI / 180)
  return { x: 170 + radius * Math.sin(a), y: 170 - radius * Math.cos(a) }
}

function polygonPoints(total, step, radius = 108) {
  const points = []
  let index = 0

  for (let i = 0; i < total; i++) {
    const a = index * (360 / total) * (Math.PI / 180)
    points.push(`${170 + radius * Math.sin(a)},${170 - radius * Math.cos(a)}`)
    index = (index + step) % total
  }

  return points.join(' ')
}

function buildRingsSVG(charged, usedSlots = [], centerUsed = false, totalSlots = 7) {
  const svg = svgEl('svg', { viewBox: '0 0 340 340', class: 'sc__rings' })

  const defs = svgEl('defs')
  ;[155, 125, 95].forEach((r, i) => {
    defs.appendChild(svgEl('path', {
      id: `sc-rp-${i}`,
      d: `M 170,${170 - r} A ${r},${r} 0 1 1 ${170 - 0.001},${170 - r}`,
    }))
  })
  svg.appendChild(defs)

  const lc = charged ? 'rgba(169,121,31,0.5)' : 'rgba(55,43,25,0.14)'
  const lw = charged ? '1' : '0.6'
  for (const [x1,y1,x2,y2] of [[170,25,170,315],[25,170,315,170],[55,55,285,285],[285,55,55,285]]) {
    svg.appendChild(svgEl('line', {
      class: 'sc__geometry-line',
      x1, y1, x2, y2,
      stroke: lc,
      'stroke-width': lw,
      'pathLength': 100,
    }))
  }

  svg.appendChild(svgEl('polygon', {
    class: 'sc__geometry-star sc__geometry-star--outer',
    points: polygonPoints(7, 2, 118),
    fill: 'none',
    stroke: charged ? 'rgba(169,121,31,0.36)' : 'rgba(55,43,25,0.10)',
    'stroke-width': charged ? '1' : '0.55',
    'pathLength': 100,
  }))

  svg.appendChild(svgEl('polygon', {
    class: 'sc__geometry-star sc__geometry-star--inner',
    points: polygonPoints(7, 3, 82),
    fill: 'none',
    stroke: charged ? 'rgba(169,121,31,0.32)' : 'rgba(55,43,25,0.08)',
    'stroke-width': charged ? '0.9' : '0.5',
    'pathLength': 100,
  }))

  ;[155, 125, 95].forEach((r, i) => {
    svg.appendChild(svgEl('circle', {
      class: `sc__geometry-ring sc__geometry-ring--${i}`,
      cx: 170, cy: 170, r,
      fill: 'none',
      stroke: charged ? 'rgba(169,121,31,0.4)' : 'rgba(55,43,25,0.12)',
      'stroke-width': '0.8',
      'pathLength': 100,
    }))

    const text = svgEl('text', { class: `sc__ring-text sc__ring-text--${i}` })
    const tp   = svgEl('textPath', { class: `sc__ring-path sc__ring-path--${i}`, href: `#sc-rp-${i}` })
    const repeats = Math.ceil((2 * Math.PI * r) / 14) + 4
    tp.textContent = (RUNE_STR.repeat(Math.ceil(repeats / RUNE_STR.length) + 1)).slice(0, repeats)
    text.appendChild(tp)
    svg.appendChild(text)
  })

  svg.appendChild(svgEl('circle', {
    class: 'sc__core-ring',
    cx: 170, cy: 170, r: 44,
    fill: charged ? 'rgba(217,169,54,0.08)' : 'rgba(205,183,135,0.35)',
    stroke: charged ? 'rgba(169,121,31,0.75)' : 'rgba(55,43,25,0.25)',
    'stroke-width': charged ? '1.5' : '0.8',
    'pathLength': 100,
  }))

  const active = svgEl('g', { class: 'sc__active-circuit' })
  const usedPoints = usedSlots.map(({ index }) => svgOrbitPoint(index, totalSlots))

  usedPoints.forEach((point, i) => {
    active.appendChild(svgEl('line', {
      class: `sc__active-link sc__active-link--${i}`,
      x1: 170,
      y1: 170,
      x2: point.x,
      y2: point.y,
      'pathLength': 100,
    }))
  })

  if (usedPoints.length > 1) {
    active.appendChild(svgEl('polyline', {
      class: 'sc__active-weave',
      points: usedPoints.map(point => `${point.x},${point.y}`).join(' '),
      fill: 'none',
      'pathLength': 100,
    }))
  }

  usedPoints.forEach((point, i) => {
    active.appendChild(svgEl('circle', {
      class: `sc__active-node sc__active-node--${i}`,
      cx: point.x,
      cy: point.y,
      r: 4.5,
    }))
  })

  svg.appendChild(active)

  const flow = svgEl('g', { class: 'sc__active-flow' })

  usedPoints.forEach((point, i) => {
    flow.appendChild(svgEl('line', {
      class: `sc__flow-link sc__flow-link--${i}`,
      x1: 170,
      y1: 170,
      x2: point.x,
      y2: point.y,
      'pathLength': 100,
    }))
  })

  if (usedPoints.length > 1) {
    flow.appendChild(svgEl('polyline', {
      class: 'sc__flow-weave',
      points: usedPoints.map(point => `${point.x},${point.y}`).join(' '),
      fill: 'none',
      'pathLength': 100,
    }))
  }

  if (centerUsed || usedPoints.length > 0) {
    flow.appendChild(svgEl('circle', {
      class: 'sc__flow-core',
      cx: 170,
      cy: 170,
      r: 15,
    }))
  }

  svg.appendChild(flow)

  return svg
}

export const SpellCircleHook = {
  mounted() {
    this._sel     = {}
    this._prevSel = {}
    this._activeSlot = null
    this._slots  = DEFAULT_SLOTS
    this._wasCharged = false
    this._firstRender = true
    // Casting is a distinct phase from entry: while filling in slots the
    // circle stays plain and the room stays lit — the ritual (blackout +
    // ignition) only happens once the incantation is actually spoken, and
    // holds for exactly as long as the AI takes to resolve it.
    this._casting = false
    this._castPhase = 'idle'
    this._castOutcome = null
    this._castStartedAt = 0
    this._castTimers = []
    this._resultPortals = []

    this.handleEvent('spell_circle_init', data => {
      if (data.slots) {
        this._slots = data.slots.map(s => ({
          key: s.key,
          label: s.label,
          required: s.required,
          kind: s.kind || 'text',
          options: s.options || [],
        }))
      }
      if (data.current) Object.assign(this._sel, data.current)
      this.render()
    })

    // The server tells us the AI has resolved (or failed) — that's the
    // signal to end the ritual and reset for the next spell.
    this.handleEvent('spell_result', data => {
      this._finishCastingAfterMinimum(data?.ok === false ? 'failure' : 'success')
    })

    this.pushEvent('hook_mounted', { hook: 'SpellCircle' })
  },

  // `.book__page` is a normal LiveView-managed element (not phx-update
  // "ignore"), so a diff triggered by anything else on the page — even
  // something unrelated — can silently wipe the inline --sc-dim we set on
  // it. While casting we reassert it a few times a second so the blackout
  // can't flicker back to lit mid-ritual regardless of what causes that.
  _startDimKeepalive() {
    this._stopDimKeepalive()
    this._dimInterval = setInterval(() => {
      const page = this.el.closest('.book__page')
      if (page) {
        page.style.setProperty('--sc-dim', this._casting ? 1 : 0)
        page.classList.toggle('book__page--ritual', this._casting)
      }
    }, 250)
  },

  _stopDimKeepalive() {
    if (this._dimInterval) {
      clearInterval(this._dimInterval)
      this._dimInterval = null
    }
  },

  _startRuneMotion() {
    this._stopRuneMotion()

    const startedAt = performance.now()
    const tick = now => {
      if (!this.el.isConnected) {
        this._stopRuneMotion()
        return
      }

      const elapsed = (now - startedAt) / 1000
      const phaseMultiplier =
        this._casting
          ? this._castPhase === 'finishing' ? 3.2 : this._castPhase === 'building' ? 0.6 : 1
          : 0.16
      const paths = this.el.querySelectorAll('.sc__ring-path')

      paths.forEach((path, i) => {
        const direction = i === 1 ? -1 : 1
        const speed = [7.5, 10.5, 14][i] || 9
        const offset = (i * 17 + direction * elapsed * speed * phaseMultiplier) % 100
        path.setAttribute('startOffset', `${offset < 0 ? offset + 100 : offset}%`)
      })

      this._runeFrame = requestAnimationFrame(tick)
    }

    this._runeFrame = requestAnimationFrame(tick)
  },

  _stopRuneMotion() {
    if (this._runeFrame) {
      cancelAnimationFrame(this._runeFrame)
      this._runeFrame = null
    }
  },

  _setCastTimer(callback, delay) {
    const timer = setTimeout(() => {
      this._castTimers = this._castTimers.filter(t => t !== timer)
      callback()
    }, delay)

    this._castTimers.push(timer)
    return timer
  },

  _clearCastTimers() {
    this._castTimers.forEach(timer => clearTimeout(timer))
    this._castTimers = []
  },

  _beginCasting() {
    this._clearCastTimers()
    this._casting = true
    this._castPhase = 'building'
    this._castOutcome = null
    this._castStartedAt = Date.now()
    this._startDimKeepalive()
    this._setCastTimer(() => {
      if (!this._casting || this._castPhase !== 'building') return
      this._castPhase = 'weaving'
      this.render()
    }, 2800)
  },

  _finishCastingAfterMinimum(outcome = 'success') {
    const elapsed = Date.now() - this._castStartedAt
    const wait = Math.max(6200 - elapsed, 0)

    this._setCastTimer(() => {
      if (!this._casting) return
      this._castPhase = 'finishing'
      this._castOutcome = outcome
      this.render()

      this._setCastTimer(() => {
        this._casting = false
        this._castPhase = 'idle'
        this._castOutcome = null
        this._sel = {}
        this._prevSel = {}
        this._activeSlot = null
        this._wasCharged = false
        this._stopDimKeepalive()
        this.render()
      }, outcome === 'failure' ? 3600 : 2800)
    }, wait)
  },

  render() {
    this._clearResultPortals()

    const root = this.el
    root.innerHTML = ''
    root.className = [
      'sc',
      this._casting ? 'sc--casting' : '',
      this._castPhase === 'finishing' && this._castOutcome ? `sc--result-${this._castOutcome}` : '',
    ].filter(Boolean).join(' ')

    // Fundamen (the base-spell picker) sits still in the center, not as a
    // point on the ring — the ring itself is the seven Latin/Schola slots,
    // a proper heptagram.
    const centerSlot = this._slots.find(s => s.key === 'base')
    const ringSlots  = this._slots.filter(s => s.key !== 'base')

    const total = ringSlots.length
    const usedRingSlots =
      ringSlots
        .map((slot, index) => ({ slot, index, value: this._sel[slot.key] }))
        .filter(({ value }) => !!value)
    const centerUsed = !!(centerSlot && this._sel[centerSlot.key])
    const charged = this._slots.filter(s => s.required).every(s => this._sel[s.key])
    const justCharged = charged && !this._wasCharged
    this._wasCharged = charged

    // ── School hue ───────────────────────────────────────────────────────────
    // Retint the circle's gold accents to the chosen school's color; default
    // to gold's own hue (45 == "order") when nothing is picked yet, or for
    // the untrained circle, which has no school slot at all.
    const schoolSlot = this._slots.find(s => s.key === 'school')
    let hue = 45
    if (schoolSlot) {
      const schoolValue = this._sel[schoolSlot.key]
      const opt = schoolSlot.options.find(o => String(o.value) === String(schoolValue))
      if (opt && opt.hue != null) hue = opt.hue
    }
    root.style.setProperty('--sc-hue', hue)

    // ── Dim the room ─────────────────────────────────────────────────────────
    // Entry stays plain and lit, no matter how much of the circle is
    // filled in — the room only goes dark once the incantation is actually
    // spoken (see the compile button below), and holds until the AI answers.
    const page = this.el.closest('.book__page')
    if (page) {
      page.style.setProperty('--sc-dim', this._casting ? 1 : 0)
      page.classList.toggle('book__page--ritual', this._casting)
    }

    // ── Circle ───────────────────────────────────────────────────────────────
    const circle = document.createElement('div')
    circle.className = [
      'sc__circle',
      charged ? 'sc__circle--charged' : '',
      this._casting ? 'sc__circle--casting' : '',
      this._casting ? `sc__circle--${this._castPhase}` : '',
      this._castPhase === 'finishing' && this._castOutcome ? `sc__circle--${this._castOutcome}` : '',
    ].filter(Boolean).join(' ')
    if (justCharged && !this._casting) {
      circle.classList.add('sc__circle--ignite')
    }

    circle.appendChild(buildRingsSVG(charged, usedRingSlots, centerUsed, total))

    // Ring slot medallions, spaced evenly around the heptagram — staggered
    // entrance. Each is a wrapper (position + label caption) around the
    // round button itself, so the Latin caption can sit outside the
    // medallion like a label under a diagram.
    ringSlots.forEach((slot, i) => {
      const size  = tileSize(total, slot.required)
      const pos   = slotPos(i, total, size)
      const value = this._sel[slot.key] ?? ''
      const displayValue = this._displayValue(slot, value)
      const isActive = this._activeSlot === slot.key
      const wasFilled = !!this._prevSel[slot.key]
      const justFilled = !!value && !wasFilled

      const wrap = document.createElement('div')
      wrap.className = 'sc__slot-wrap'
      wrap.style.left = pos.left
      wrap.style.top  = pos.top
      wrap.style.width = `${size.w}%`
      wrap.style.height = `${size.h}%`
      wrap.style.setProperty('--sc-i', i)

      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = [
        'sc__slot',
        value ? 'sc__slot--filled' : '',
        isActive ? 'sc__slot--active' : '',
        !slot.required ? 'sc__slot--optional' : 'sc__slot--required',
        justFilled ? 'sc__slot--catch' : '',
      ].filter(Boolean).join(' ')
      if (this._firstRender) {
        btn.style.animationDelay = `${i * 0.06}s`
        btn.classList.add('sc__slot--enter')
      }

      const val = document.createElement('span')
      val.className = 'sc__slot-value'
      val.textContent = displayValue || '—'
      btn.appendChild(val)

      btn.disabled = this._casting
      btn.addEventListener('click', () => {
        if (this._casting) return
        this._activeSlot = this._activeSlot === slot.key ? null : slot.key
        this.render()
      })

      const lbl = document.createElement('span')
      lbl.className = 'sc__slot-label'
      lbl.textContent = slot.label

      wrap.appendChild(btn)
      wrap.appendChild(lbl)

      if (justFilled) {
        wrap.appendChild(this._buildMotes())
      }

      circle.appendChild(wrap)
    })

    // Center — the Fundamen (base spell) foundation stone when the caster
    // has one, sitting still in the middle; otherwise today's empty center
    // with a decorative lit rune once charged.
    if (centerSlot) {
      const value = this._sel[centerSlot.key] ?? ''
      const displayValue = this._displayValue(centerSlot, value)
      const isActive = this._activeSlot === centerSlot.key

      const centerBtn = document.createElement('button')
      centerBtn.type = 'button'
      centerBtn.className = [
        'sc__slot',
        'sc__slot--center',
        value ? 'sc__slot--filled' : '',
        isActive ? 'sc__slot--active' : '',
        'sc__slot--optional',
      ].filter(Boolean).join(' ')

      const val = document.createElement('span')
      val.className = 'sc__slot-value'
      val.textContent = displayValue || '—'
      centerBtn.appendChild(val)

      centerBtn.disabled = this._casting
      centerBtn.addEventListener('click', () => {
        if (this._casting) return
        this._activeSlot = this._activeSlot === centerSlot.key ? null : centerSlot.key
        this.render()
      })

      const lbl = document.createElement('span')
      lbl.className = 'sc__center-label'
      lbl.textContent = centerSlot.label

      const centerWrap = document.createElement('div')
      centerWrap.className = 'sc__center sc__center--slot'
      centerWrap.appendChild(centerBtn)
      centerWrap.appendChild(lbl)
      circle.appendChild(centerWrap)
    } else {
      const center = document.createElement('div')
      center.className = 'sc__center'
      if (charged) {
        const rune = document.createElement('span')
        rune.className = 'sc__center-rune'
        rune.textContent = 'ᚨ'
        center.appendChild(rune)
      }
      circle.appendChild(center)
    }

    // Particles
    if (charged) {
      for (let i = 0; i < total; i++) {
        const c = orbitCenter(i, total)
        const p = document.createElement('div')
        p.className = 'sc__particle'
        p.style.left = c.left
        p.style.top  = c.top
        p.style.animationDelay = `${-(i * (3 / total))}s`
        circle.appendChild(p)
      }
    }

    root.appendChild(circle)

    // ── Input sheet ─────────────────────────────────────────────────────────
    if (this._activeSlot) {
      root.appendChild(this._buildInputSheet(this._activeSlot))
    }

    // ── Footer ──────────────────────────────────────────────────────────────
    const footer = document.createElement('div')
    footer.className = 'sc__footer'

    const btn = document.createElement('button')
    btn.className = [
      'sc__compile',
      charged ? 'sc__compile--ready' : '',
      this._casting ? 'sc__compile--casting' : '',
    ].filter(Boolean).join(' ')
    btn.type      = 'button'
    btn.disabled  = !charged || this._casting
    btn.textContent = this._casting ? 'Заклинание творится…' : 'Сотворить заклинание'
    btn.addEventListener('click', () => {
      if (!charged || this._casting) return
      // Speaking the incantation is the trigger — the room goes dark and
      // the circle ignites right now, and holds in that state (not a fixed
      // timer) until the server tells us the AI has actually resolved it.
      this._beginCasting()
      this.pushEvent('spell_compile', { ...this._sel })
      this.render()
    })
    footer.appendChild(btn)

    root.appendChild(footer)

    if (this._castPhase === 'finishing' && this._castOutcome) {
      this._mountResultPortals(this._castOutcome)
    }

    this._prevSel = { ...this._sel }
    this._firstRender = false

    this._startRuneMotion()
  },

  // A word catching gold leaf: a few tiny motes of gold dust drift down
  // and settle as the ink finishes turning gold. Purely decorative — the
  // wrapper removes itself after the animation runs once.
  _buildMotes() {
    const wrap = document.createElement('div')
    wrap.className = 'sc__motes'
    for (let i = 0; i < 4; i++) {
      const m = document.createElement('span')
      m.className = 'sc__mote'
      m.style.left = `${20 + i * 20 + (Math.random() * 10 - 5)}%`
      m.style.animationDelay = `${i * 0.06}s`
      wrap.appendChild(m)
    }
    setTimeout(() => wrap.remove(), 700)
    return wrap
  },

  _buildShatterOverlay() {
    const overlay = document.createElement('div')
    overlay.className = 'sc__shatter'

    const cols = 8
    const rows = 6
    const cellW = 100 / cols
    const cellH = 100 / rows

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const seed = row * cols + col
        const jitterX = ((seed * 17) % 9) - 4
        const jitterY = ((seed * 23) % 9) - 4
        const width = cellW + 2 + ((seed * 11) % 4)
        const height = cellH + 2 + ((seed * 13) % 5)
        const cutA = 3 + ((seed * 7) % 18)
        const cutB = 4 + ((seed * 5) % 22)
        const cutC = 80 + ((seed * 3) % 15)
        const cutD = 76 + ((seed * 19) % 18)

        const shard = document.createElement('span')
        shard.className = 'sc__shard'
        shard.style.left = `${col * cellW + jitterX * 0.18}%`
        shard.style.top = `${row * cellH + jitterY * 0.18}%`
        shard.style.width = `${width}%`
        shard.style.height = `${height}%`
        shard.style.setProperty('--dx', `${(col - 3) * 8 + (row % 2 ? 10 : -10)}vw`)
        shard.style.setProperty('--dy', `${52 + row * 11 + (col % 3) * 8}vh`)
        shard.style.setProperty('--r', `${(col - 3) * 8 + (row - 2) * 5}deg`)
        shard.style.animationDelay = `${2.45 + seed * 0.008}s`
        shard.style.clipPath =
          `polygon(${cutA}% 0, 100% ${cutB}%, ${cutC}% 100%, 0 ${cutD}%)`
        overlay.appendChild(shard)
      }
    }

    return overlay
  },

  _buildWhiteoutOverlay(outcome) {
    const overlay = document.createElement('div')
    overlay.className = `sc__whiteout sc__whiteout--${outcome}`
    return overlay
  },

  _mountResultPortals(outcome) {
    // Order matters: the shader's radial burst sits under the whiteout
    // flash, so the beams are what the eye finds when the flash fades.
    const overlays = [this._buildShaderOverlay(outcome), this._buildWhiteoutOverlay(outcome)]
    if (outcome === 'failure') overlays.push(this._buildShatterOverlay())

    overlays.forEach(overlay => {
      document.body.appendChild(overlay)
      this._resultPortals.push(overlay)
    })
  },

  _clearResultPortals() {
    this._resultPortals.forEach(overlay => overlay.remove())
    this._resultPortals = []
  },

  _buildShaderOverlay(outcome) {
    const canvas = document.createElement('canvas')
    canvas.className = `sc__shader sc__shader--${outcome}`
    requestAnimationFrame(() => this._runResultShader(canvas, outcome))
    return canvas
  },

  _runResultShader(canvas, outcome) {
    if (!canvas.isConnected) return

    const gl = canvas.getContext('webgl', {
      alpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      premultipliedAlpha: true,
    })

    if (!gl) {
      canvas.classList.add('sc__shader--fallback')
      return
    }

    const program = this._createResultProgram(gl)
    if (!program) {
      canvas.classList.add('sc__shader--fallback')
      return
    }

    const buffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      gl.STATIC_DRAW
    )

    const pos = gl.getAttribLocation(program, 'aPos')
    const uSize = gl.getUniformLocation(program, 'uSize')
    const uTime = gl.getUniformLocation(program, 'uTime')
    const uExcitation = gl.getUniformLocation(program, 'uExcitation')
    const uLegendaryTint = gl.getUniformLocation(program, 'uLegendaryTint')
    const uWhiteout = gl.getUniformLocation(program, 'uWhiteout')
    const hue = Number.parseFloat(getComputedStyle(this.el).getPropertyValue('--sc-hue')) || 45
    const tint = Math.max(0.15, Math.min(1, 1 - Math.abs(hue - 45) / 220))
    const startedAt = performance.now()
    const duration = outcome === 'failure' ? 3000 : 2200

    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      const width = Math.max(1, Math.floor(window.innerWidth * dpr))
      const height = Math.max(1, Math.floor(window.innerHeight * dpr))
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width
        canvas.height = height
      }
      gl.viewport(0, 0, width, height)
      return { width, height }
    }

    const frame = now => {
      if (!canvas.isConnected) return

      const elapsed = now - startedAt
      const t = Math.min(elapsed / duration, 1)
      const whiteout = outcome === 'failure'
        ? smoothstep(0.42, 0.62, t)
        : smoothstep(0.48, 0.76, t) * (1 - smoothstep(0.82, 1.0, t))
      const excitation = Math.min(1, 0.08 + smoothstep(0.26, 0.58, t) * 1.05)
      const size = resize()

      gl.useProgram(program)
      gl.enableVertexAttribArray(pos)
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0)
      gl.uniform2f(uSize, size.width, size.height)
      gl.uniform1f(uTime, elapsed)
      gl.uniform1f(uExcitation, excitation)
      gl.uniform1f(uLegendaryTint, tint)
      gl.uniform1f(uWhiteout, whiteout)
      gl.clearColor(0, 0, 0, 0)
      gl.clear(gl.COLOR_BUFFER_BIT)
      gl.drawArrays(gl.TRIANGLES, 0, 6)

      if (t < 1) requestAnimationFrame(frame)
    }

    requestAnimationFrame(frame)
  },

  _createResultProgram(gl) {
    const vertex = this._compileResultShader(gl, gl.VERTEX_SHADER, RESULT_VERTEX_SHADER)
    const fragment = this._compileResultShader(gl, gl.FRAGMENT_SHADER, RESULT_FRAGMENT_SHADER)
    if (!vertex || !fragment) return null

    const program = gl.createProgram()
    gl.attachShader(program, vertex)
    gl.attachShader(program, fragment)
    gl.linkProgram(program)

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return null
    return program
  },

  _compileResultShader(gl, type, source) {
    const shader = gl.createShader(type)
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    return gl.getShaderParameter(shader, gl.COMPILE_STATUS) ? shader : null
  },

  // For select-kind slots the stored value is often an id (spell) or a
  // raw enum string (school) — show the human label on the medallion.
  _displayValue(slot, value) {
    if (!value) return ''
    if (slot.kind === 'select') {
      const opt = slot.options.find(o => String(o.value) === String(value))
      return opt ? opt.label : value
    }
    return value
  },

  _buildInputSheet(key) {
    const slot = this._slots.find(s => s.key === key)
    const sheet = document.createElement('div')
    sheet.className = 'sc__sheet'

    const title = document.createElement('div')
    title.className  = 'sc__sheet-title'
    title.textContent = slot?.label ?? key
    sheet.appendChild(title)

    if (slot?.kind === 'select') {
      sheet.appendChild(this._buildSelectField(slot, key))
    } else {
      sheet.appendChild(this._buildTextField(key))
    }

    const actions = document.createElement('div')
    actions.className = 'sc__sheet-actions'

    const accept = document.createElement('button')
    accept.type = 'button'
    accept.className = 'sc__sheet-btn sc__sheet-btn--ok'
    accept.textContent = 'ОК'
    accept.addEventListener('click', () => { this._activeSlot = null; this.render() })

    const clear = document.createElement('button')
    clear.type = 'button'
    clear.className = 'sc__sheet-btn'
    clear.textContent = 'Очистить'
    clear.addEventListener('click', () => { delete this._sel[key]; this._activeSlot = null; this.render() })

    actions.appendChild(accept)
    actions.appendChild(clear)
    sheet.appendChild(actions)

    return sheet
  },

  _buildTextField(key) {
    const input = document.createElement('input')
    input.type = 'text'
    input.className = 'sc__sheet-input'
    input.placeholder = 'Введите значение...'
    input.value = this._sel[key] ?? ''
    input.addEventListener('input', e => { this._sel[key] = e.target.value })
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter') { this._activeSlot = null; this.render() }
    })
    requestAnimationFrame(() => input.focus())
    return input
  },

  _buildSelectField(slot, key) {
    if (!slot.options.length) {
      const empty = document.createElement('p')
      empty.className = 'sc__sheet-empty'
      empty.textContent = 'Пока нечего выбрать.'
      return empty
    }

    const select = document.createElement('select')
    select.className = 'sc__sheet-select'

    const blank = document.createElement('option')
    blank.value = ''
    blank.textContent = '— выбрать —'
    select.appendChild(blank)

    for (const opt of slot.options) {
      const o = document.createElement('option')
      o.value = opt.value
      o.textContent = opt.label
      if (String(this._sel[key]) === String(opt.value)) o.selected = true
      select.appendChild(o)
    }

    select.addEventListener('change', e => {
      if (e.target.value) this._sel[key] = e.target.value
      else delete this._sel[key]
    })

    return select
  },

  destroyed() {
    // Don't leak the blackout into other tabs — clear it the moment this
    // leaf is torn down (e.g. switching to Grimoires/Spells).
    this._stopDimKeepalive()
    this._clearCastTimers()
    this._clearResultPortals()
    this._stopRuneMotion()
    const page = this.el.closest('.book__page')
    if (page) {
      page.style.setProperty('--sc-dim', 0)
      page.classList.remove('book__page--ritual')
    }
  },
}
