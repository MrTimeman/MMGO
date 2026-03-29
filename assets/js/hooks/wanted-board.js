// WantedBoardHook — Reputation profile: score, crime records, fines, market ban.
//
// Template usage:
//   <div id="wanted-board" phx-hook="WantedBoard" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "board_update", %{
//     reputation_score: 100,
//     crimes: [
//       %{type: "black_market_default", severity: "minor",
//         fine_amount: 200, status: "open", recorded_at: "2026-03-01"}
//     ],
//     outstanding_fine: 200,
//     market_ban_until: "2026-04-15" | nil
//   })
//
// Client → server events:
//   handle_event("board_pay_fine", %{}, socket)

import { h } from './utils'

const SEVERITY_LABEL = { minor: 'Незначительное', moderate: 'Среднее', severe: 'Тяжкое' }
const CRIME_TYPE_LABEL = { black_market_default: 'Неисполнение сделки на чёрном рынке' }
const CRIME_STATUS_LABEL = { open: 'Открыто', resolved: 'Закрыто' }

function scoreClass(score) {
  if (score >= 80) return 'board__score--good'
  if (score >= 40) return 'board__score--neutral'
  return 'board__score--bad'
}

export const WantedBoardHook = {
  mounted() {
    this.handleEvent('board_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'WantedBoard' })
  },

  render({ reputation_score, crimes = [], outstanding_fine, market_ban_until }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'board'

    // Score
    const scoreRow = h('div', { class: 'board__score-row' })
    scoreRow.appendChild(h('span', { class: 'board__score-label' }, 'Репутация'))
    scoreRow.appendChild(h('span', { class: `board__score ${scoreClass(reputation_score)}` }, String(reputation_score)))
    root.appendChild(scoreRow)

    // Market ban
    if (market_ban_until) {
      root.appendChild(h('div', { class: 'board__ban' }, `Запрет торговли до: ${market_ban_until}`))
    }

    // Outstanding fine
    if (outstanding_fine > 0) {
      const fineRow = h('div', { class: 'board__fine' })
      fineRow.appendChild(h('span', {}, `Задолженность: ${outstanding_fine} зм`))
      const btn = h('button', { class: 'board__pay-btn', type: 'button' }, 'Оплатить')
      btn.addEventListener('click', () => this.pushEvent('board_pay_fine', {}))
      fineRow.appendChild(btn)
      root.appendChild(fineRow)
    }

    // Crime list
    if (crimes.length > 0) {
      const list = h('div', { class: 'board__crimes' })
      for (const c of crimes) {
        const row = h('div', { class: `board__crime board__crime--${c.status}` })
        row.appendChild(h('div', { class: 'board__crime-type' }, CRIME_TYPE_LABEL[c.type] ?? c.type))
        const meta = h('div', { class: 'board__crime-meta' })
        meta.appendChild(h('span', { class: `board__crime-sev board__crime-sev--${c.severity}` }, SEVERITY_LABEL[c.severity] ?? c.severity))
        meta.append(`  ${CRIME_STATUS_LABEL[c.status] ?? c.status}`)
        if (c.fine_amount) meta.append(`  ·  штраф: ${c.fine_amount} зм`)
        if (c.recorded_at) meta.append(`  ·  ${c.recorded_at}`)
        row.appendChild(meta)
        list.appendChild(row)
      }
      root.appendChild(list)
    } else {
      root.appendChild(h('div', { class: 'board__clean' }, 'Нарушений не зафиксировано'))
    }
  },

  destroyed() {},
}
