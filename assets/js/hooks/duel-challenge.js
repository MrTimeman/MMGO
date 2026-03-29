// DuelChallengeHook — Parchment letter with signature reveal.
// Single document: salutation in Great Vibes, A vs B chips, stake + question.
// Accept → cursive signature appears. Reject/cancel → parchment discards.

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
    this.handleEvent('duel_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'DuelChallenge' })
  },

  render(data) {
    const { duel_id, status, challenger, opponent, stake, pot, winner_name, viewer_role } = data
    const root = this.el
    root.innerHTML = ''
    root.className = 'duel'

    const discarded = status === 'rejected' || status === 'cancelled'
    const accepted  = status === 'active' || status === 'resolved'

    const parchment = h('div', { class: [
      'duel__parchment',
      discarded ? 'duel__parchment--discarded' : '',
      accepted  ? 'duel__parchment--accepted'  : '',
    ].filter(Boolean).join(' ') })

    // Salutation
    parchment.appendChild(h('div', { class: 'duel__salutation' },
      `Дорогой ${opponent?.name ?? '—'},`))

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

    // Winner
    if (status === 'resolved' && winner_name) {
      parchment.appendChild(h('div', { class: 'duel__winner' }, `Победитель: ${winner_name}`))
    }

    // Status badge (not for pending)
    if (status !== 'pending') {
      parchment.appendChild(h('div', { class: `duel__badge duel__badge--${status}` },
        STATUS_LABEL[status] ?? status))
    }

    // Signature (when accepted/active)
    if (accepted) {
      parchment.appendChild(h('div', { class: 'duel__signature' }, 'Принято'))
    }

    // Question + actions (pending only)
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
        const cancel = h('button', { class: 'duel__btn duel__btn--reject', type: 'button' }, 'Отозвать вызов')
        cancel.addEventListener('click', () => this.pushEvent('duel_cancel', { duel_id }))
        parchment.appendChild(cancel)
      }
    }

    // Ministry footer
    parchment.appendChild(h('div', { class: 'duel__ministry' }, '— Министерство Магии'))

    root.appendChild(parchment)
  },

  destroyed() {},
}
