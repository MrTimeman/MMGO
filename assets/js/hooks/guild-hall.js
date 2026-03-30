// GuildHallHook — Organization view with visual rank ladder and optional identity obscuring.

import { h, charChip, ORG_KIND_LABEL } from './utils'

export const GuildHallHook = {
  mounted() {
    this.handleEvent('guild_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'GuildHall' })
  },

  render({ org, roles = [], members = [], pending_invitations = 0,
           viewer_permissions = [], viewer_rank = 999 }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'hall'

    // Header
    const header = h('div', { class: 'hall__header' })
    header.appendChild(h('div', { class: 'hall__name' }, org?.name ?? ''))
    header.appendChild(h('div', { class: 'hall__kind' }, ORG_KIND_LABEL[org?.kind] ?? org?.kind ?? ''))
    root.appendChild(header)

    // Actions
    const canInvite = viewer_permissions.includes('invite_members')
    const canManage = viewer_permissions.includes('manage_roles')
    if (canInvite || canManage) {
      const actions = h('div', { class: 'hall__actions' })
      if (canInvite) {
        const btn = h('button', { class: 'hall__btn', type: 'button' },
          `Пригласить${pending_invitations > 0 ? ` (${pending_invitations})` : ''}`)
        btn.addEventListener('click', () => this.pushEvent('guild_invite_open', {}))
        actions.appendChild(btn)
      }
      if (canManage) {
        const btn = h('button', { class: 'hall__btn', type: 'button' }, 'Роли')
        btn.addEventListener('click', () => this.pushEvent('guild_manage_roles', {}))
        actions.appendChild(btn)
      }
      root.appendChild(actions)
    }

    // ── Rank ladder ────────────────────────────────────────────────────────
    if (roles.length > 0) {
      const sorted = [...roles].sort((a, b) => a.rank - b.rank)
      const section = h('div', { class: 'hall__section' })
      section.appendChild(h('div', { class: 'hall__section-label' }, 'Иерархия'))

      const ladder = h('div', { class: 'hall__ladder' })
      const maxRank = Math.max(...sorted.map(r => r.rank))

      for (let ri = 0; ri < sorted.length; ri++) {
        const role = sorted[ri]
        const rung = h('div', { class: `hall__rung${role.rank === viewer_rank ? ' hall__rung--viewer' : ''}` })
        rung.style.animationDelay = `${ri * 0.08}s`

        const barPct = Math.round(100 - (role.rank / maxRank) * 75)
        const bar = h('div', { class: 'hall__rung-bar' })
        // Animate bar from 0 to target width
        requestAnimationFrame(() => { bar.style.width = `${barPct}%` })
        rung.appendChild(bar)

        const label = h('div', { class: 'hall__rung-label' })
        label.appendChild(h('span', { class: 'hall__rung-title' }, role.title))
        label.appendChild(h('span', { class: 'hall__rung-rank' }, `#${role.rank}`))
        rung.appendChild(label)

        // Members in this role
        const roleMembers = members.filter(m => m.role_title === role.title)
        if (roleMembers.length > 0) {
          const chips = h('div', { class: 'hall__rung-chips' })
          for (let ci = 0; ci < roleMembers.length; ci++) {
            const m = roleMembers[ci]
            const obscured = m.identity_obscured && m.rank < viewer_rank
            const chip = obscured
              ? this._obscuredChip()
              : charChip(m.name, m.avatar_url ?? null, 'sm')
            chip.title = obscured ? '???' : m.name
            chip.style.animationDelay = `${ri * 0.08 + ci * 0.05}s`
            chip.classList.add('hall__chip-enter')
            chips.appendChild(chip)
          }
          rung.appendChild(chips)
        }

        ladder.appendChild(rung)
      }

      section.appendChild(ladder)
      root.appendChild(section)
    }

    // ── Unranked members ──────────────────────────────────────────────────
    const unranked = members.filter(m => !roles.find(r => r.title === m.role_title))
    if (unranked.length > 0) {
      const section = h('div', { class: 'hall__section' })
      section.appendChild(h('div', { class: 'hall__section-label' }, `Участники (${members.length})`))
      const grid = h('div', { class: 'hall__members' })
      for (const m of unranked) {
        const obscured = m.identity_obscured && (m.rank ?? 999) < viewer_rank
        const card = h('div', { class: 'hall__member' })
        card.appendChild(obscured
          ? this._obscuredChip('lg')
          : charChip(m.name, m.avatar_url ?? null, 'lg'))
        card.appendChild(h('div', { class: 'hall__member-name' }, obscured ? '???' : m.name))
        if (m.role_title) card.appendChild(h('div', { class: 'hall__member-role' }, m.role_title))
        grid.appendChild(card)
      }
      section.appendChild(grid)
      root.appendChild(section)
    }
  },

  _obscuredChip(size = 'sm') {
    const el = document.createElement('div')
    el.className = `char-chip char-chip--${size} char-chip--obscured`
    el.textContent = '?'
    return el
  },

  destroyed() {},
}
