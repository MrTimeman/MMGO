// GuildHallHook — Organization view: header, role list, member chips, pending invitations.
//
// Template usage:
//   <div id="guild-hall" phx-hook="GuildHall" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "guild_update", %{
//     org: %{name: "Орден Пепла", kind: "cult"},
//     roles: [%{code: "elder", title: "Старейшина", rank: 10}, ...],
//     members: [%{name: "Арториас", avatar_url: nil, role_title: "Старейшина"}, ...],
//     pending_invitations: 2,
//     viewer_permissions: ["invite_members", "manage_roles"]
//   })
//
// Client → server events:
//   handle_event("guild_invite_open", %{}, socket)
//   handle_event("guild_manage_roles", %{}, socket)

import { h, charChip, ORG_KIND_LABEL } from './utils'

export const GuildHallHook = {
  mounted() {
    this.handleEvent('guild_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'GuildHall' })
  },

  render({ org, roles = [], members = [], pending_invitations = 0, viewer_permissions = [] }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'hall'

    // Header
    const header = h('div', { class: 'hall__header' })
    header.appendChild(h('div', { class: 'hall__name' }, org?.name ?? ''))
    header.appendChild(h('div', { class: 'hall__kind' }, ORG_KIND_LABEL[org?.kind] ?? org?.kind ?? ''))
    root.appendChild(header)

    // Actions
    const canInvite      = viewer_permissions.includes('invite_members')
    const canManageRoles = viewer_permissions.includes('manage_roles')

    if (canInvite || canManageRoles) {
      const actions = h('div', { class: 'hall__actions' })
      if (canInvite) {
        const invBtn = h('button', { class: 'hall__btn', type: 'button' }, `Пригласить${pending_invitations > 0 ? ` (${pending_invitations})` : ''}`)
        invBtn.addEventListener('click', () => this.pushEvent('guild_invite_open', {}))
        actions.appendChild(invBtn)
      }
      if (canManageRoles) {
        const roleBtn = h('button', { class: 'hall__btn', type: 'button' }, 'Роли')
        roleBtn.addEventListener('click', () => this.pushEvent('guild_manage_roles', {}))
        actions.appendChild(roleBtn)
      }
      root.appendChild(actions)
    }

    // Roles list
    if (roles.length > 0) {
      const roleSection = h('div', { class: 'hall__section' })
      roleSection.appendChild(h('div', { class: 'hall__section-label' }, 'Иерархия'))
      const roleList = h('div', { class: 'hall__roles' })
      const sorted = [...roles].sort((a, b) => a.rank - b.rank)
      for (const role of sorted) {
        const row = h('div', { class: 'hall__role' })
        row.appendChild(h('span', { class: 'hall__role-rank' }, String(role.rank)))
        row.appendChild(h('span', { class: 'hall__role-title' }, role.title))
        roleList.appendChild(row)
      }
      roleSection.appendChild(roleList)
      root.appendChild(roleSection)
    }

    // Member grid
    if (members.length > 0) {
      const memberSection = h('div', { class: 'hall__section' })
      memberSection.appendChild(h('div', { class: 'hall__section-label' }, `Участники (${members.length})`))
      const grid = h('div', { class: 'hall__members' })
      for (const m of members) {
        const card = h('div', { class: 'hall__member' })
        card.appendChild(charChip(m.name, m.avatar_url ?? null, 'lg'))
        card.appendChild(h('div', { class: 'hall__member-name' }, m.name))
        if (m.role_title) card.appendChild(h('div', { class: 'hall__member-role' }, m.role_title))
        grid.appendChild(card)
      }
      memberSection.appendChild(grid)
      root.appendChild(memberSection)
    }
  },

  destroyed() {},
}
