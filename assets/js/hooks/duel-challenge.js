// DuelChallengeHook — Challenge card with two sides, wager amounts, and accept/reject actions.
//
// Template usage:
//   <div id="duel-challenge" phx-hook="DuelChallenge" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "duel_update", %{
//     duel_id: "uuid",
//     status: "pending" | "active" | "resolved" | "rejected" | "cancelled",
//     challenger: %{name: "Арториас", avatar_url: nil},
//     opponent:   %{name: "Мелисандра", avatar_url: nil},
//     stake: 500,
//     pot: 1000,
//     winner_name: nil | "Арториас",
//     viewer_role: "challenger" | "opponent" | "spectator"
//   })
//
// Client → server events:
//   handle_event("duel_accept",  %{"duel_id" => id}, socket)
//   handle_event("duel_reject",  %{"duel_id" => id}, socket)
//   handle_event("duel_cancel",  %{"duel_id" => id}, socket)

import { h, charChip } from './utils'

const STATUS_LABEL = {
  pending:   'Ожидает ответа',
  active:    'Идёт поединок',
  resolved:  'Завершён',
  rejected:  'Отклонён',
  cancelled: 'Отменён',
}

function side(player, amountLabel) {
  const col = h('div', { class: 'duel__side' })
  col.appendChild(charChip(player.name, player.avatar_url ?? null, 'lg'))
  col.appendChild(h('div', { class: 'duel__side-name' }, player.name))
  col.appendChild(h('div', { class: 'duel__side-stake' }, amountLabel))
  return col
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

    // Status banner
    const banner = h('div', { class: `duel__status duel__status--${status}` }, STATUS_LABEL[status] ?? status)
    root.appendChild(banner)

    // Two sides
    const sides = h('div', { class: 'duel__sides' })
    sides.appendChild(side(challenger, `${stake} зм`))
    sides.appendChild(h('div', { class: 'duel__vs' }, 'vs'))
    sides.appendChild(side(opponent, `${stake} зм`))
    root.appendChild(sides)

    // Pot
    root.appendChild(h('div', { class: 'duel__pot' }, `Банк: ${pot} зм`))

    // Winner
    if (status === 'resolved' && winner_name) {
      root.appendChild(h('div', { class: 'duel__winner' }, `Победитель: ${winner_name}`))
    }

    // Actions
    const actions = h('div', { class: 'duel__actions' })

    if (status === 'pending' && viewer_role === 'opponent') {
      const accept = h('button', { class: 'duel__btn duel__btn--accept', type: 'button' }, 'Принять')
      const reject = h('button', { class: 'duel__btn duel__btn--reject', type: 'button' }, 'Отклонить')
      accept.addEventListener('click', () => this.pushEvent('duel_accept', { duel_id }))
      reject.addEventListener('click', () => this.pushEvent('duel_reject', { duel_id }))
      actions.appendChild(accept)
      actions.appendChild(reject)
    } else if (status === 'pending' && viewer_role === 'challenger') {
      const cancel = h('button', { class: 'duel__btn duel__btn--reject', type: 'button' }, 'Отменить вызов')
      cancel.addEventListener('click', () => this.pushEvent('duel_cancel', { duel_id }))
      actions.appendChild(cancel)
    }

    if (actions.childElementCount > 0) root.appendChild(actions)
  },

  destroyed() {},
}
