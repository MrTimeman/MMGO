// EventScrollHook — Renders a location-based narrative event with selectable options.
//
// Template usage:
//   <div id="event-display" phx-hook="EventScroll" phx-update="ignore"></div>
//
// Server → client events:
//   push_event(socket, "event_scroll_update", %{
//     title: "Прибытие в город",
//     body:  "Вы входите в ворота...",
//     options: [%{code: "shop", label: "Торговая улица"}, ...],
//     resolved_option: nil | "shop",
//     result_text: nil | "Вы направились к рынку..."
//   })
//
// Client → server events:
//   handle_event("event_option_select", %{"code" => "shop"}, socket)

import { h } from './utils'

export const EventScrollHook = {
  mounted() {
    this.handleEvent('event_scroll_update', data => this.render(data))
    this.pushEvent('hook_mounted', { hook: 'EventScroll' })
  },

  render({ title, body, options = [], resolved_option, result_text }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'evs'

    root.appendChild(h('div', { class: 'evs__title' }, title ?? ''))
    root.appendChild(h('div', { class: 'evs__body' }, body ?? ''))

    if (resolved_option && result_text) {
      root.appendChild(h('div', { class: 'evs__result' }, result_text))
    } else if (options.length > 0) {
      const grid = h('div', { class: 'evs__options' })
      for (const opt of options) {
        const btn = h('button', { class: 'evs__option', type: 'button' }, opt.label)
        btn.addEventListener('click', () => this.pushEvent('event_option_select', { code: opt.code }))
        grid.appendChild(btn)
      }
      root.appendChild(grid)
    }
  },

  destroyed() {},
}
