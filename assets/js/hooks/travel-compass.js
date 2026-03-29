// TravelCompassHook — Journey status overlay with a rotating compass needle.
// Mount this as an overlay inside or beside the map container.
//
// Template usage:
//   <div id="travel-compass" phx-hook="TravelCompass" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "compass_update", %{
//     bearing: 45,          # degrees 0–360, 0 = north
//     journey: %{
//       from_name: "Камнедол",
//       to_name: "Башня Ордена",
//       days_remaining: 3,
//       travel_days: 7,
//       food_units: 8,
//       food_capacity: 20
//     } | nil
//   })

import { h } from './utils'

const COMPASS_SVG = (bearing) => {
  // N S E W labels + rotating needle
  return `<svg viewBox="0 0 80 80" fill="none" xmlns="http://www.w3.org/2000/svg" class="cmp__svg">
    <circle cx="40" cy="40" r="38" stroke="var(--color-border)" stroke-width="1.5"/>
    <circle cx="40" cy="40" r="2" fill="var(--color-accent)"/>
    <text x="40" y="10" text-anchor="middle" class="cmp__label">С</text>
    <text x="40" y="75" text-anchor="middle" class="cmp__label">Ю</text>
    <text x="8"  y="44" text-anchor="middle" class="cmp__label">З</text>
    <text x="72" y="44" text-anchor="middle" class="cmp__label">В</text>
    <g transform="rotate(${bearing}, 40, 40)">
      <polygon points="40,8 36.5,40 40,37 43.5,40" fill="var(--color-danger)"/>
      <polygon points="40,72 36.5,40 40,43 43.5,40" fill="var(--color-text-muted)"/>
    </g>
  </svg>`
}

export const TravelCompassHook = {
  mounted() {
    this.el.className = 'cmp'
    this.handleEvent('compass_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'TravelCompass' })
  },

  render({ bearing = 0, journey }) {
    const root = this.el
    root.innerHTML = ''

    // Compass rose
    const rose = h('div', { class: 'cmp__rose' })
    rose.innerHTML = COMPASS_SVG(bearing)
    root.appendChild(rose)

    if (!journey) {
      root.appendChild(h('div', { class: 'cmp__idle' }, 'В пути нет'))
      return
    }

    // Route label
    root.appendChild(h('div', { class: 'cmp__route' },
      h('span', {}, journey.from_name ?? '—'),
      h('span', { class: 'cmp__arrow' }, '→'),
      h('span', {}, journey.to_name ?? '—'),
    ))

    // Days remaining bar
    const total = journey.travel_days ?? 1
    const remaining = journey.days_remaining ?? 0
    const donePct = Math.round(((total - remaining) / total) * 100)

    const dayWrap = h('div', { class: 'cmp__stat' })
    dayWrap.appendChild(h('span', { class: 'cmp__stat-label' }, `Осталось дней: ${remaining}`))
    const bar = h('div', { class: 'cmp__bar-wrap' })
    const fill = h('div', { class: 'cmp__bar-fill' })
    fill.style.width = `${donePct}%`
    bar.appendChild(fill)
    dayWrap.appendChild(bar)
    root.appendChild(dayWrap)

    // Food units
    const foodPct = Math.round(((journey.food_units ?? 0) / (journey.food_capacity ?? 1)) * 100)
    const foodStat = h('div', { class: 'cmp__stat' })
    foodStat.appendChild(h('span', { class: 'cmp__stat-label' }, `Припасы: ${journey.food_units ?? 0} / ${journey.food_capacity ?? 0}`))
    const foodBar = h('div', { class: 'cmp__bar-wrap' })
    const foodFill = h('div', { class: 'cmp__bar-fill cmp__bar-fill--food' })
    foodFill.style.width = `${foodPct}%`
    foodBar.appendChild(foodFill)
    foodStat.appendChild(foodBar)
    root.appendChild(foodStat)
  },

  destroyed() {},
}
