// DuelChallengeHook — Parchment letter with signature reveal.
// Single document: salutation in Great Vibes, A vs B chips, stake + question.
// Accept → signature appears, reject/cancel → parchment discards.
// Parchment renders once; status changes mutate in place (no re-animation).

import { h, charChip } from './utils'

const STATUS_LABEL = {
  pending:   'Ожидает ответа',
  active:    'Идёт поединок',
  resolved:  'Завершён',
  rejected:  'Отклонён',
  cancelled: 'Отменён',
}

export const DuelChallengeHook = {
  mounted() {
    this._status = null
    this._parchment = null
    this.handleEvent('duel_update', data => this._update(data))
    this.pushEvent('hook_mounted', { hook: 'DuelChallenge' })
  },

  _update(data) {
    const { duel_id, status, challenger, opponent, stake, pot, winner_name, viewer_role } = data

    // First render or new duel — build the whole parchment
    if (!this._parchment || this._duelId !== duel_id) {
      this._duelId = duel_id
      this._status = null
      this._buildParchment(data)
    }

    // Status unchanged — nothing to do
    if (this._status === status) return
    const prevStatus = this._status
    this._status = status

    // ── Mutate in place based on status transition ─────────────────────
    const parchment = this._parchment

    const discarded = status === 'rejected' || status === 'cancelled'
    const accepted  = status === 'active' || status === 'resolved'

    parchment.classList.toggle('duel__parchment--discarded', discarded)
    parchment.classList.toggle('duel__parchment--accepted', accepted)

    // Remove actions area on any transition from pending
    if (prevStatus === 'pending' || prevStatus === null) {
      const actions = parchment.querySelector('.duel__actions')
      if (actions && status !== 'pending') actions.remove()
      const cancel = parchment.querySelector('.duel__btn--cancel-solo')
      if (cancel && status !== 'pending') cancel.remove()
      const question = parchment.querySelector('.duel__question')
      if (question && status !== 'pending') question.remove()
    }

    // Add badge
    if (status !== 'pending' && !parchment.querySelector('.duel__badge')) {
      const badge = h('div', { class: `duel__badge duel__badge--${status}` },
        STATUS_LABEL[status] ?? status)
      // Insert before ministry footer
      const ministry = parchment.querySelector('.duel__ministry')
      parchment.insertBefore(badge, ministry)
    }

    // Add signature on accept
    if (accepted && !parchment.querySelector('.duel__signature')) {
      const sig = h('div', { class: 'duel__signature' }, 'Принято')
      const ministry = parchment.querySelector('.duel__ministry')
      parchment.insertBefore(sig, ministry)
    }

    // Add winner on resolve
    if (status === 'resolved' && winner_name && !parchment.querySelector('.duel__winner')) {
      const winner = h('div', { class: 'duel__winner' }, `Победитель: ${winner_name}`)
      const ministry = parchment.querySelector('.duel__ministry')
      parchment.insertBefore(winner, ministry)
    }
  },

  _buildParchment({ duel_id, status, challenger, opponent, stake, pot, winner_name, viewer_role }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'duel'

    const parchment = h('div', { class: 'duel__parchment' })
    this._parchment = parchment

    // Salutation — gender-aware (m/f/nil)
    const salut = opponent?.gender === 'f' ? 'Дорогая'
                : opponent?.gender === 'm' ? 'Дорогой'
                : null
    parchment.appendChild(h('div', { class: 'duel__salutation' },
      salut ? `${salut} ${opponent?.name ?? '—'},` : `${opponent?.name ?? '—'},`))

    // Vs section
    const vsRow = h('div', { class: 'duel__vs-row' })

    const cCol = h('div', { class: 'duel__vs-side' })
    cCol.appendChild(charChip(challenger?.name ?? '?', challenger?.avatar_url ?? null, 'lg'))
    cCol.appendChild(h('span', { class: 'duel__vs-name' }, challenger?.name ?? '—'))
    vsRow.appendChild(cCol)

    vsRow.appendChild(h('div', { class: 'duel__vs-sep' }, 'vs'))

    const oCol = h('div', { class: 'duel__vs-side' })
    oCol.appendChild(charChip(opponent?.name ?? '?', opponent?.avatar_url ?? null, 'lg'))
    oCol.appendChild(h('span', { class: 'duel__vs-name' }, opponent?.name ?? '—'))
    vsRow.appendChild(oCol)

    parchment.appendChild(vsRow)

    // Body
    parchment.appendChild(h('div', { class: 'duel__text' },
      `${challenger?.name ?? '—'} вызывает вас на поединок чести.`))

    parchment.appendChild(h('div', { class: 'duel__stake' },
      `Ставка: ${stake ?? 0} золотых монет`))

    // Question + actions (pending)
    if (status === 'pending') {
      parchment.appendChild(h('div', { class: 'duel__question' }, 'Ваш ответ?'))

      if (viewer_role === 'opponent') {
        const actions = h('div', { class: 'duel__actions' })
        const accept = h('button', { class: 'duel__btn duel__btn--accept', type: 'button' }, 'Принять')
        const reject = h('button', { class: 'duel__btn duel__btn--reject', type: 'button' }, 'Отклонить')
        accept.addEventListener('click', () => this.pushEvent('duel_accept', { duel_id }))
        reject.addEventListener('click', () => this.pushEvent('duel_reject', { duel_id }))
        actions.appendChild(accept)
        actions.appendChild(reject)
        parchment.appendChild(actions)
      } else if (viewer_role === 'challenger') {
        const cancel = h('button', { class: 'duel__btn duel__btn--reject duel__btn--cancel-solo', type: 'button' }, 'Отозвать вызов')
        cancel.addEventListener('click', () => this.pushEvent('duel_cancel', { duel_id }))
        parchment.appendChild(cancel)
      }
    }

    // Ministry footer (always last)
    parchment.appendChild(h('div', { class: 'duel__ministry' }, '— Министерство Магии'))

    root.appendChild(parchment)
  },

  destroyed() {},
}
