// BaseInteriorHook — Base room view: info, storage grid, workshop tools.
//
// Template usage:
//   <div id="base-interior" phx-hook="BaseInterior" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "base_update", %{
//     name: "Логово Арториаса",
//     kind: "city_purchase" | "custom_build",
//     status: "building" | "active",
//     build_days_remaining: 12 | nil,
//     storage: %{
//       used_weight: 40,
//       capacity: 250,
//       items: [%{name: "Зелье лечения", quantity: 3, durability: nil}, ...]
//     },
//     workshop: %{tools: ["кузнечный молот", "алхимический стол"]} | nil
//   })

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

    // Header
    const header = h('div', { class: 'base__header' })
    header.appendChild(h('div', { class: 'base__name' }, name ?? 'База'))
    header.appendChild(h('div', { class: 'base__kind' }, KIND_LABEL[kind] ?? kind))
    root.appendChild(header)

    // Building state
    if (status === 'building') {
      root.appendChild(h('div', { class: 'base__building' },
        `Строительство... осталось дней: ${build_days_remaining ?? '—'}`
      ))
      return
    }

    // Storage section
    if (storage) {
      const section = h('div', { class: 'base__section' })
      const weightPct = Math.round((storage.used_weight / (storage.capacity || 1)) * 100)

      const sectionHead = h('div', { class: 'base__section-head' })
      sectionHead.appendChild(h('span', {}, 'Хранилище'))
      sectionHead.appendChild(h('span', { class: 'base__weight' }, `${storage.used_weight} / ${storage.capacity}`))
      section.appendChild(sectionHead)

      const bar = h('div', { class: 'base__bar-wrap' })
      const fill = h('div', { class: 'base__bar-fill' })
      fill.style.width = `${weightPct}%`
      bar.appendChild(fill)
      section.appendChild(bar)

      if (storage.items?.length > 0) {
        const grid = h('div', { class: 'base__grid' })
        for (const item of storage.items) {
          const cell = h('div', { class: 'base__cell' })
          cell.appendChild(h('div', { class: 'base__cell-name' }, item.name))
          const meta = h('div', { class: 'base__cell-meta' })
          if (item.quantity > 1) meta.append(`×${item.quantity}`)
          if (item.durability != null) {
            if (meta.textContent) meta.append('  ')
            meta.append(`${item.durability}%`)
          }
          cell.appendChild(meta)
          grid.appendChild(cell)
        }
        section.appendChild(grid)
      } else {
        section.appendChild(h('div', { class: 'base__empty' }, 'Хранилище пусто'))
      }

      root.appendChild(section)
    }

    // Workshop section
    if (workshop) {
      const section = h('div', { class: 'base__section' })
      section.appendChild(h('div', { class: 'base__section-head' }, 'Мастерская'))
      if (workshop.tools?.length > 0) {
        const tools = h('div', { class: 'base__tools' })
        for (const tool of workshop.tools) {
          tools.appendChild(h('span', { class: 'base__tool' }, tool))
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
