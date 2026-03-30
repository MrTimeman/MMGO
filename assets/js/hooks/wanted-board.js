// WantedBoardHook — Reputation profile. Score is the hero number.

import { h } from './utils'

const SEVERITY_LABEL  = { minor: 'Незначительное', moderate: 'Среднее', severe: 'Тяжкое' }
const CRIME_TYPE_LABEL = { black_market_default: 'Неисполнение сделки на чёрном рынке' }
const CRIME_STATUS_LABEL = { open: 'Открыто', resolved: 'Закрыто' }

export const WantedBoardHook = {
  mounted() {
    this._prevScore = null
    this.handleEvent('board_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'WantedBoard' })
  },

  render({ reputation_score, crimes = [], outstanding_fine, market_ban_until }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'board'

    // ── Hero score ─────────────────────────────────────────────────────────
    const hero = h('div', { class: 'board__hero' })
    const score = reputation_score ?? 0
    const tier  = score >= 80 ? 'good' : score >= 40 ? 'neutral' : 'bad'
    const changed = this._prevScore !== null && this._prevScore !== score

    const scoreEl = h('div', { class: `board__score-num board__score-num--${tier}` }, String(score))
    if (changed) scoreEl.classList.add('board__score-num--pulse')
    this._prevScore = score
    hero.appendChild(scoreEl)
    hero.appendChild(h('div', { class: 'board__score-label' }, 'РЕПУТАЦИЯ'))
    root.appendChild(hero)

    // ── Market ban ─────────────────────────────────────────────────────────
    if (market_ban_until) {
      root.appendChild(h('div', { class: 'board__ban' }, `Запрет торговли до: ${market_ban_until}`))
    }

    // ── Outstanding fine ───────────────────────────────────────────────────
    if (outstanding_fine > 0) {
      const fineRow = h('div', { class: 'board__fine' })
      fineRow.appendChild(h('span', {}, `Задолженность: ${outstanding_fine} зм`))
      const btn = h('button', { class: 'board__pay-btn', type: 'button' }, 'Оплатить')
      btn.addEventListener('click', () => {
        btn.classList.add('board__pay-btn--click')
        setTimeout(() => this.pushEvent('board_pay_fine', {}), 250)
      })
      fineRow.appendChild(btn)
      root.appendChild(fineRow)
    }

    // ── Crime list ─────────────────────────────────────────────────────────
    if (crimes.length > 0) {
      const list = h('div', { class: 'board__crimes' })
      for (let i = 0; i < crimes.length; i++) {
        const c = crimes[i]
        const row = h('div', { class: `board__crime board__crime--${c.status}` })
        row.style.animationDelay = `${i * 0.06}s`
        row.appendChild(h('div', { class: 'board__crime-type' }, CRIME_TYPE_LABEL[c.type] ?? c.type))
        const meta = h('div', { class: 'board__crime-meta' })
        meta.appendChild(h('span', { class: `board__crime-sev board__crime-sev--${c.severity}` },
          SEVERITY_LABEL[c.severity] ?? c.severity))
        meta.append(`  ${CRIME_STATUS_LABEL[c.status] ?? c.status}`)
        if (c.fine_amount) meta.append(`  ·  штраф: ${c.fine_amount} зм`)
        if (c.recorded_at)  meta.append(`  ·  ${c.recorded_at}`)
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
