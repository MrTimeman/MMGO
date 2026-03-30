// BaseInteriorHook — Base room view: header, storage grid, workshop tools.

import { h } from './utils'

const KIND_LABEL = { city_purchase: 'Городской дом', custom_build: 'Постройка' }

export const BaseInteriorHook = {
  mounted() {
    this.handleEvent('base_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'BaseInterior' })
  },

  render({ name, kind, status, build_days_remaining, storage, workshop }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'base'

    // ── Header ──────────────────────────────────────────────────────────────
    const header = h('div', { class: 'base__header' })
    const headerTop = h('div', { class: 'base__header-top' })
    headerTop.appendChild(h('div', { class: 'base__name' }, name ?? 'База'))
    headerTop.appendChild(h('div', { class: 'base__kind' }, KIND_LABEL[kind] ?? kind ?? ''))
    header.appendChild(headerTop)
    header.appendChild(h('div', {
      class: `base__status base__status--${status}`,
    }, status === 'active' ? '● Активна' : `⚒ Строительство · ${build_days_remaining ?? '—'} дн.`))
    root.appendChild(header)

    if (status === 'building') return

    // ── Storage ──────────────────────────────────────────────────────────────
    if (storage) {
      const section = h('div', { class: 'base__section' })
      const weightPct = Math.round((storage.used_weight / (storage.capacity || 1)) * 100)
      const barMod = weightPct > 90 ? 'danger' : weightPct > 70 ? 'warn' : ''

      const sHead = h('div', { class: 'base__section-head' })
      const sTitle = h('div', { class: 'base__section-title' })
      sTitle.appendChild(h('span', { class: 'base__section-icon' }, '⊞'))
      sTitle.appendChild(h('span', {}, 'Хранилище'))
      sHead.appendChild(sTitle)
      sHead.appendChild(h('span', { class: 'base__weight' }, `${storage.used_weight} / ${storage.capacity} ед.`))
      section.appendChild(sHead)

      const bar = h('div', { class: 'base__bar-wrap' })
      const fill = h('div', { class: `base__bar-fill${barMod ? ' base__bar-fill--' + barMod : ''}` })
      requestAnimationFrame(() => { fill.style.width = `${weightPct}%` })
      bar.appendChild(fill)
      section.appendChild(bar)

      if (storage.items?.length > 0) {
        const grid = h('div', { class: 'base__grid' })
        for (let i = 0; i < storage.items.length; i++) {
          const item = storage.items[i]
          const cell = h('div', { class: 'base__cell base__cell--enter' })
          cell.style.animationDelay = `${i * 0.05}s`
          cell.appendChild(h('div', { class: 'base__cell-dot' }))
          const info = h('div', { class: 'base__cell-info' })
          info.appendChild(h('div', { class: 'base__cell-name' }, item.name))
          const parts = []
          if (item.quantity > 1) parts.push(`×${item.quantity}`)
          if (item.durability != null) parts.push(`${item.durability}%`)
          if (parts.length) info.appendChild(h('div', { class: 'base__cell-meta' }, parts.join('  ·  ')))
          cell.appendChild(info)
          grid.appendChild(cell)
        }
        section.appendChild(grid)
      } else {
        section.appendChild(h('div', { class: 'base__empty' }, 'Хранилище пусто'))
      }

      root.appendChild(section)
    }

    // ── Workshop ─────────────────────────────────────────────────────────────
    if (workshop) {
      const section = h('div', { class: 'base__section' })
      const sHead = h('div', { class: 'base__section-head' })
      const sTitle = h('div', { class: 'base__section-title' })
      sTitle.appendChild(h('span', { class: 'base__section-icon' }, '⚙'))
      sTitle.appendChild(h('span', {}, 'Мастерская'))
      sHead.appendChild(sTitle)
      section.appendChild(sHead)

      if (workshop.tools?.length > 0) {
        const tools = h('div', { class: 'base__tools' })
        for (let i = 0; i < workshop.tools.length; i++) {
          const el = h('span', { class: 'base__tool base__tool--enter' }, workshop.tools[i])
          el.style.animationDelay = `${i * 0.06}s`
          tools.appendChild(el)
        }
        section.appendChild(tools)
      } else {
        section.appendChild(h('div', { class: 'base__empty' }, 'Инструменты не установлены'))
      }
      root.appendChild(section)
    }
  },

  destroyed() {},
}
