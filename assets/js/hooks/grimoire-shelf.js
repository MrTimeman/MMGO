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
      root.appendChild(h('div', { class: 'grim__empty' }, 'Grimoire не найдены'))
      return
    }

    const shelf = h('div', { class: 'grim__shelf' })
    const booksRow = h('div', { class: 'grim__books' })

    for (const g of this._grimoires) {
      booksRow.appendChild(this._book(g))
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
    root.appendChild(shelf)

    const openGrim = this._grimoires.find(g => g.id === this._open)
    if (openGrim) root.appendChild(this._panel(openGrim))
  },

  _book(g) {
    const hash = strHash(g.name)
    const hue  = hash % 360
    const w    = 32 + (hash % 20)
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

    const panel = h('div', { class: 'grim__panel' })
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

      const slot = h('div', { class: `grim__slot${spell ? '' : ' grim__slot--empty'}` })
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
