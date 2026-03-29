// ExpeditionLogHook — Expedition journal: member chips, event log, supply bars.
//
// Template usage:
//   <div id="expedition-log" phx-hook="ExpeditionLog" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "expedition_update", %{
//     status: "active" | "completed" | "aborted" | "failed",
//     expedition_type: "dungeon" | "overworld",
//     members: [%{name: "Арториас", avatar_url: nil, status: "active"}, ...],
//     events: [%{text: "Столкновение с бандитами", kind: "encounter"}, ...],
//     supplies: %{
//       food_units: 12,
//       food_demand_per_day: 3,
//       carried_weight: 88,
//       carry_capacity: 120
//     }
//   })

import { h, charChip } from './utils'

const EVENT_KIND_CLASS = {
  encounter: 'exped__event--encounter',
  reward:    'exped__event--reward',
  narrative: 'exped__event--narrative',
}

const STATUS_LABEL = {
  active: 'В экспедиции', completed: 'Завершена',
  aborted: 'Прервана', failed: 'Провалена',
}

export const ExpeditionLogHook = {
  mounted() {
    this.handleEvent('expedition_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'ExpeditionLog' })
  },

  render({ status, members = [], events = [], supplies }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'exped'

    // Status
    root.appendChild(h('div', { class: `exped__status exped__status--${status}` }, STATUS_LABEL[status] ?? status))

    // Member chips
    if (members.length > 0) {
      const row = h('div', { class: 'exped__members' })
      for (const m of members) {
        const wrap = h('div', { class: `exped__member${m.status !== 'active' ? ' exped__member--inactive' : ''}` })
        wrap.appendChild(charChip(m.name, m.avatar_url ?? null, 'md'))
        wrap.appendChild(h('div', { class: 'exped__member-name' }, m.name))
        row.appendChild(wrap)
      }
      root.appendChild(row)
    }

    // Supplies
    if (supplies) {
      const foodPct   = Math.round((supplies.food_units / Math.max(supplies.food_demand_per_day * 14, 1)) * 100)
      const weightPct = Math.round((supplies.carried_weight / (supplies.carry_capacity || 1)) * 100)

      const supplyBlock = h('div', { class: 'exped__supplies' })

      const foodStat = h('div', { class: 'exped__supply-row' })
      foodStat.appendChild(h('span', { class: 'exped__supply-label' }, `Еда: ${supplies.food_units} ед. (${supplies.food_demand_per_day}/день)`))
      const fb = h('div', { class: 'exped__bar-wrap' })
      const ff = h('div', { class: 'exped__bar-fill exped__bar-fill--food' })
      ff.style.width = `${Math.min(foodPct, 100)}%`
      fb.appendChild(ff)
      foodStat.appendChild(fb)
      supplyBlock.appendChild(foodStat)

      const wStat = h('div', { class: 'exped__supply-row' })
      wStat.appendChild(h('span', { class: 'exped__supply-label' }, `Вес: ${supplies.carried_weight} / ${supplies.carry_capacity}`))
      const wb = h('div', { class: 'exped__bar-wrap' })
      const wf = h('div', { class: 'exped__bar-fill' })
      wf.style.width = `${Math.min(weightPct, 100)}%`
      if (weightPct > 90) wf.classList.add('exped__bar-fill--danger')
      wb.appendChild(wf)
      wStat.appendChild(wb)
      supplyBlock.appendChild(wStat)

      root.appendChild(supplyBlock)
    }

    // Event log (newest first)
    if (events.length > 0) {
      const log = h('div', { class: 'exped__log' })
      for (const ev of [...events].reverse()) {
        const line = h('div', { class: `exped__event ${EVENT_KIND_CLASS[ev.kind] ?? ''}` }, ev.text)
        log.appendChild(line)
      }
      root.appendChild(log)
    }
  },

  destroyed() {},
}
