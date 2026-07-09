// GrimoireShelfHook — A bookshelf of grimoires. Click to open, drag to reorder.

import { h, SCHOOL_HUE, SCHOOL_LABEL } from './utils'

function strHash(s) {
  let h = 0
  for (let i = 0; i < s.length; i++) h = s.charCodeAt(i) + ((h << 5) - h)
  return Math.abs(h)
}

const STATUS_LABEL = { active: 'Активен', sealed: 'Запечатан', locked: 'Заблокирован' }

export const GrimoireShelfHook = {
  mounted() {
    this._open       = null
    this._dragId     = null
    this._dropTarget = null
    // Snapshots from the previous render — used so a server round-trip
    // after e.g. inscribing one spell doesn't replay every entrance
    // animation on the whole shelf, only on what actually changed.
    this._prevIds     = new Set()
    this._prevOpenId  = null
    this._prevEntries = new Map() // grimoireId -> Set("slot:spellId")
    this.handleEvent('shelf_update', ({ grimoires }) => {
      this._grimoires = grimoires
      this.render()
    })
    this.pushEvent('hook_mounted', { hook: 'GrimoireShelf' })
  },

  render() {
    const root = this.el
    root.innerHTML = ''
    root.className = 'grim'

    if (!this._grimoires?.length) {
      root.appendChild(h('div', { class: 'grim__empty' }, 'Гримуары не найдены'))
      return
    }

    // A real shelf has a fixed width per tier — once one row of spines is
    // full, the rest sit on another shelf below it, not squeezed into the
    // same row or spilling off the edge. Group books into rows by their
    // actual (known-in-advance) spine width before rendering anything.
    const shelvesWrap = h('div', { class: 'grim__shelves' })
    const rowWidth = Math.max((this.el.clientWidth || 320) - 12, 100)
    const gap = 3
    const rows = [[]]
    let rowFill = 0
    for (const g of this._grimoires) {
      const bw = this._bookWidth(g)
      const addition = rowFill === 0 ? bw : bw + gap
      if (rowFill > 0 && rowFill + addition > rowWidth) {
        rows.push([])
        rowFill = 0
      }
      rows[rows.length - 1].push(g)
      rowFill += rowFill === 0 ? bw : bw + gap
    }

    let bookIndex = 0
    for (const rowGrimoires of rows) {
      const shelf = h('div', { class: 'grim__shelf' })
      const booksRow = h('div', { class: 'grim__books' })

      for (const g of rowGrimoires) {
        const bookEl = this._book(g)
        if (!this._prevIds.has(g.id)) {
          bookEl.classList.add('grim__book--enter')
          bookEl.style.animationDelay = `${bookIndex * 0.08}s`
        }
        booksRow.appendChild(bookEl)
        bookIndex += 1
      }

      // Allow drop on empty shelf area
      booksRow.addEventListener('dragover', e => e.preventDefault())
      booksRow.addEventListener('drop', e => {
        e.preventDefault()
        // Drop after last book if not on a specific book
        if (this._dragId && !this._dropTarget) {
          const fromIdx = this._grimoires.findIndex(b => b.id === this._dragId)
          if (fromIdx !== -1 && fromIdx !== this._grimoires.length - 1) {
            const moved = this._grimoires.splice(fromIdx, 1)[0]
            this._grimoires.push(moved)
            this.pushEvent('grimoire_reorder', { id: this._dragId, before_id: null })
          }
          this._dragId = null
          this._dropTarget = null
          this.render()
        }
      })

      shelf.appendChild(booksRow)
      shelf.appendChild(h('div', { class: 'grim__plank' }))
      shelvesWrap.appendChild(shelf)
    }

    root.appendChild(shelvesWrap)

    const openGrim = this._grimoires.find(g => g.id === this._open)
    if (openGrim) root.appendChild(this._panel(openGrim))

    this._prevIds = new Set(this._grimoires.map(g => g.id))
    this._prevOpenId = this._open
  },

  _bookWidth(g) {
    return 32 + (strHash(g.name) % 20)
  },

  _book(g) {
    const hash = strHash(g.name)
    const hue  = hash % 360
    const w    = this._bookWidth(g)
    const h_px = 64 + ((g.capacity ?? 6) * 5)

    const book = h('div', {
      class: [
        'grim__book',
        g.status === 'active' ? 'grim__book--active' : '',
        g.status === 'sealed' ? 'grim__book--sealed' : '',
        g.status === 'locked' ? 'grim__book--locked' : '',
        this._open       === g.id ? 'grim__book--open'        : '',
        this._dropTarget === g.id ? 'grim__book--drop-before' : '',
      ].filter(Boolean).join(' '),
    })

    book.draggable = true
    book.dataset.id = g.id

    book.style.cssText = [
      `width:${w}px`,
      `height:${h_px}px`,
      `background:hsl(${hue},${g.status === 'sealed' ? 15 : 30}%,${g.status === 'sealed' ? 12 : 18}%)`,
      `border-color:hsl(${hue},${g.status === 'sealed' ? 15 : 35}%,${g.status === 'sealed' ? 16 : 25}%)`,
    ].join(';')

    if (g.status === 'active') book.style.boxShadow = `0 0 8px hsl(${hue},50%,30%)`

    book.appendChild(h('span', { class: 'grim__book-title' }, g.name))

    if (g.status === 'sealed') book.appendChild(h('span', { class: 'grim__book-badge' }, '🔒'))
    else if (g.status === 'locked') book.appendChild(h('span', { class: 'grim__book-badge' }, '⛓'))

    book.addEventListener('click', () => {
      this._open = this._open === g.id ? null : g.id
      this.render()
    })

    // ── Drag events ──────────────────────────────────────────────────────────
    book.addEventListener('dragstart', e => {
      this._dragId = g.id
      e.dataTransfer.effectAllowed = 'move'
      // Delay class add so the ghost image doesn't show the dimmed state
      setTimeout(() => book.classList.add('grim__book--dragging'), 0)
    })

    book.addEventListener('dragend', () => {
      this._dragId = null
      this._dropTarget = null
      this.render()
    })

    book.addEventListener('dragover', e => {
      if (!this._dragId || this._dragId === g.id) return
      e.preventDefault()
      e.stopPropagation()
      e.dataTransfer.dropEffect = 'move'
      if (this._dropTarget !== g.id) {
        this._dropTarget = g.id
        // Lightweight indicator update — avoid full re-render during drag
        this.el.querySelectorAll('.grim__book--drop-before').forEach(el =>
          el.classList.remove('grim__book--drop-before'))
        book.classList.add('grim__book--drop-before')
      }
    })

    book.addEventListener('dragleave', () => {
      book.classList.remove('grim__book--drop-before')
      if (this._dropTarget === g.id) this._dropTarget = null
    })

    book.addEventListener('drop', e => {
      e.preventDefault()
      e.stopPropagation()
      if (!this._dragId || this._dragId === g.id) return

      const fromIdx = this._grimoires.findIndex(b => b.id === this._dragId)
      const toIdx   = this._grimoires.findIndex(b => b.id === g.id)

      if (fromIdx !== -1 && toIdx !== -1) {
        const [moved] = this._grimoires.splice(fromIdx, 1)
        this._grimoires.splice(toIdx, 0, moved)
        this.pushEvent('grimoire_reorder', { id: this._dragId, before_id: g.id })
      }

      this._dragId = null
      this._dropTarget = null
      this.render()
    })

    return book
  },

  _panel(g) {
    const hash = strHash(g.name)
    const hue  = hash % 360
    const justOpened = this._prevOpenId !== g.id
    const prevEntries = this._prevEntries.get(g.id) ?? new Set()
    const nextEntries = new Set(
      (g.entries ?? []).filter(e => e.spell).map(e => `${e.slot}:${e.spell.id}`)
    )
    this._prevEntries.set(g.id, nextEntries)

    const panel = h('div', { class: `grim__panel${justOpened ? ' grim__panel--enter' : ''}` })
    panel.style.borderColor = `hsl(${hue},30%,22%)`

    const head = h('div', { class: 'grim__panel-head' })
    head.appendChild(h('span', { class: 'grim__panel-name' }, g.name))

    const meta = h('div', { class: 'grim__panel-meta' })
    meta.append(STATUS_LABEL[g.status] ?? g.status)
    meta.append(`  ·  вес: ${g.weight ?? 0}`)
    meta.append(`  ·  ${(g.entries?.filter(e => e.spell).length ?? 0)} / ${g.capacity ?? 0} ячеек`)
    head.appendChild(meta)

    if (g.status === 'sealed') {
      const btn = h('button', { class: 'grim__panel-btn', type: 'button' }, 'Активировать')
      btn.addEventListener('click', e => {
        e.stopPropagation()
        this.pushEvent('grimoire_activate', { id: g.id })
      })
      head.appendChild(btn)
    }

    panel.appendChild(head)

    const grid = h('div', { class: 'grim__slots' })
    for (let i = 0; i < (g.capacity ?? 8); i++) {
      const entry = g.entries?.find(e => e.slot === i)
      const spell = entry?.spell
      const entryKey = spell ? `${i}:${spell.id}` : null
      const isNew = justOpened || (entryKey && !prevEntries.has(entryKey))

      const slot = h('div', {
        class: `grim__slot${spell ? '' : ' grim__slot--empty'}${isNew ? ' grim__slot--enter' : ''}`,
      })
      if (isNew) slot.style.animationDelay = `${i * 0.04}s`
      slot.appendChild(h('span', { class: 'grim__slot-num' }, String(i + 1)))

      if (spell) {
        const hue2 = SCHOOL_HUE[spell.school] ?? 0
        const dot = h('span', { class: 'grim__slot-dot' })
        dot.style.background = `hsl(${hue2},60%,45%)`
        slot.appendChild(dot)
        slot.appendChild(h('span', { class: 'grim__slot-name' }, spell.name))
        if (spell.cooldown) slot.appendChild(h('span', { class: 'grim__slot-cd' }, `${spell.cooldown} хода`))
      } else {
        slot.appendChild(h('span', { class: 'grim__slot-empty-lbl' }, '— пусто —'))
        slot.addEventListener('click', () => this.pushEvent('grimoire_inscribe', { id: g.id, slot: i }))
      }

      grid.appendChild(slot)
    }

    panel.appendChild(grid)
    return panel
  },

  destroyed() {},
}
