// ExpeditionLogHook — Expedition journal with supply bars and flavor micro-events.

import { h, charChip } from './utils'

const STATUS_LABEL = {
  active: 'В экспедиции', completed: 'Завершена',
  aborted: 'Прервана', failed: 'Провалена',
}

const FLAVOR = [
  'Дор споткнулся о корень и выронил флягу.',
  'Кто-то слышал смех в темноте. Наверное ветер.',
  'Белка украла сухарь прямо из руки Лиры.',
  'Арториас утверждает, что видел привидение. Мелисандра говорит — это был фонарь.',
  'Найдена монета с профилем неизвестного короля.',
  'Запах жареного мяса. Источник не установлен.',
  'На стене выцарапано: «Здесь был Грот. И пожалел».',
  'Дор и Лира поспорили, существуют ли гоблины-вегетарианцы. Спор не разрешён.',
  'Странный гриб. Никто его не трогал. На всякий случай.',
  'В углу нашли чьи-то очки. Стёкла целые.',
  'Мелисандра насвистела мотив. Никто не знает, откуда он.',
  'Летучая мышь залетела в шлем Дора. Все сделали вид, что не заметили.',
  'На полу — отпечатки копыт. Маленьких. Очень маленьких.',
  'Дор клянётся, что один из камней подмигнул. Камень отрицает.',
]

function pickFlavor(seed) {
  return FLAVOR[(seed + Math.floor(Date.now() / 1000)) % FLAVOR.length]
}

export const ExpeditionLogHook = {
  mounted() {
    this._localEvents = []
    this._flavorSeed  = Math.floor(Math.random() * FLAVOR.length)
    this._flavorTimer = null

    this.handleEvent('expedition_update', data => {
      this._data = data
      if (data.status === 'active' && !this._flavorTimer) {
        this._flavorTimer = setInterval(() => {
          this._flavorSeed++
          this._localEvents.unshift({ text: pickFlavor(this._flavorSeed), kind: 'flavor' })
          if (this._localEvents.length > 6) this._localEvents.pop()
          this._renderLog()
        }, 240000) // every 4 real minutes ≈ 1 game day
      }
      this.render(data)
    })
    this.pushEvent('hook_mounted', { hook: 'ExpeditionLog' })
  },

  render({ status, members = [], events = [], supplies }) {
    const root = this.el
    root.innerHTML = ''
    root.className = 'exped'

    root.appendChild(h('div', { class: `exped__status exped__status--${status}` }, STATUS_LABEL[status] ?? status))

    if (members.length > 0) {
      const row = h('div', { class: 'exped__members' })
      for (let i = 0; i < members.length; i++) {
        const m = members[i]
        const wrap = h('div', { class: `exped__member${m.status !== 'active' ? ' exped__member--inactive' : ''}` })
        wrap.style.animationDelay = `${i * 0.07}s`
        wrap.appendChild(charChip(m.name, m.avatar_url ?? null, 'md'))
        wrap.appendChild(h('div', { class: 'exped__member-name' }, m.name))
        row.appendChild(wrap)
      }
      root.appendChild(row)
    }

    if (supplies) {
      const block = h('div', { class: 'exped__supplies' })

      const foodPct = Math.round(((supplies.food_units ?? 0) /
        Math.max((supplies.food_demand_per_day ?? 1) * 14, 1)) * 100)
      block.appendChild(this._supplyRow(
        `Еда: ${supplies.food_units} ед. (${supplies.food_demand_per_day}/день)`, foodPct, 'food'))

      const wPct = Math.round(((supplies.carried_weight ?? 0) / (supplies.carry_capacity || 1)) * 100)
      block.appendChild(this._supplyRow(
        `Вес: ${supplies.carried_weight} / ${supplies.carry_capacity}`, wPct, wPct > 90 ? 'danger' : ''))

      root.appendChild(block)
    }

    this._logEl = h('div', { class: 'exped__log', id: 'exped-log-inner' })
    root.appendChild(this._logEl)
    this._allEvents = [...this._localEvents, ...[...events].reverse()]
    this._renderLog()
  },

  _renderLog() {
    if (!this._logEl) return
    const existing = this._logEl.childElementCount
    this._logEl.innerHTML = ''
    for (let i = 0; i < Math.min(this._allEvents.length, 20); i++) {
      const ev = this._allEvents[i]
      const kindCls = {
        encounter: 'exped__event--encounter',
        reward:    'exped__event--reward',
        narrative: 'exped__event--narrative',
        flavor:    'exped__event--flavor',
      }[ev.kind] ?? ''
      const el = h('div', { class: `exped__event ${kindCls}` }, ev.text)
      // New events at the top get entrance animation
      if (i === 0 && existing > 0) el.classList.add('exped__event--new')
      this._logEl.appendChild(el)
    }
  },

  _supplyRow(label, pct, mod) {
    const row = h('div', { class: 'exped__supply-row' })
    row.appendChild(h('span', { class: 'exped__supply-label' }, label))
    const bar = h('div', { class: 'exped__bar-wrap' })
    const fill = h('div', { class: `exped__bar-fill${mod ? ' exped__bar-fill--' + mod : ''}` })
    requestAnimationFrame(() => { fill.style.width = `${Math.min(pct, 100)}%` })
    bar.appendChild(fill)
    row.appendChild(bar)
    return row
  },

  destroyed() {
    if (this._flavorTimer) clearInterval(this._flavorTimer)
  },
}
