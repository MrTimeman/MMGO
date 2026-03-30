// StudyDeskHook — Academy enrollment and specialization display.
//
// Template usage:
//   <div id="study-desk" phx-hook="StudyDesk" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "study_desk_update", %{
//     enrollment: %{
//       program_type: "academy_core",
//       track: "wizardry",
//       primary_school: "fire",
//       secondary_school: "water",
//       expected_completion_at: "2026-05-10",
//       progress_pct: 34
//     } | nil,
//     specialization: %{track: "wizardry", primary_school: "fire", secondary_school: "water"} | nil
//   })

import { h, PROGRAM_LABEL, TRACK_LABEL, SCHOOL_LABEL, SCHOOL_HUE } from './utils'

function schoolBadge(school) {
  const hue = SCHOOL_HUE[school] ?? 0
  const badge = h('span', { class: 'std__badge' }, SCHOOL_LABEL[school] ?? school)
  badge.style.cssText = `background:hsl(${hue},40%,18%);color:hsl(${hue},70%,70%);border-color:hsl(${hue},40%,28%)`
  return badge
}

export const StudyDeskHook = {
  mounted() {
    this.handleEvent('study_desk_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'StudyDesk' })
  },

  render({ enrollment, specialization }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'std'

    // Active specialization strip
    if (specialization) {
      const spec = h('div', { class: 'std__spec std__spec--enter' })
      spec.appendChild(h('span', { class: 'std__spec-label' }, 'Специализация'))
      const badges = h('div', { class: 'std__badges' })
      const b1 = schoolBadge(specialization.primary_school)
      b1.classList.add('std__badge--enter')
      b1.style.animationDelay = '0.15s'
      badges.appendChild(b1)
      if (specialization.secondary_school) {
        const b2 = schoolBadge(specialization.secondary_school)
        b2.classList.add('std__badge--enter')
        b2.style.animationDelay = '0.25s'
        badges.appendChild(b2)
      }
      spec.appendChild(h('strong', {}, TRACK_LABEL[specialization.track] ?? specialization.track))
      spec.appendChild(badges)
      root.appendChild(spec)
    }

    // Enrollment block
    if (enrollment) {
      const block = h('div', { class: 'std__block std__block--enter' })
      block.appendChild(h('div', { class: 'std__program' }, PROGRAM_LABEL[enrollment.program_type] ?? enrollment.program_type))
      block.appendChild(h('div', { class: 'std__track' }, TRACK_LABEL[enrollment.track] ?? enrollment.track))

      if (enrollment.primary_school) {
        const badges = h('div', { class: 'std__badges' })
        badges.appendChild(schoolBadge(enrollment.primary_school))
        if (enrollment.secondary_school) badges.appendChild(schoolBadge(enrollment.secondary_school))
        block.appendChild(badges)
      }

      // Progress bar
      const pct = enrollment.progress_pct ?? 0
      const bar = h('div', { class: 'std__bar-wrap' })
      const fill = h('div', { class: 'std__bar-fill' })
      requestAnimationFrame(() => { fill.style.width = `${pct}%` })
      bar.appendChild(fill)
      block.appendChild(bar)
      block.appendChild(h('div', { class: 'std__completion' }, `Завершение: ${enrollment.expected_completion_at ?? '—'}`))

      root.appendChild(block)
    } else {
      root.appendChild(h('div', { class: 'std__empty' }, 'Нет активного обучения'))
    }
  },

  destroyed() {},
}
