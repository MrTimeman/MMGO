// Shared utilities for all game hooks

// Generate a stable hue from a string — gives each character a consistent colour
function nameHue(name) {
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash)
  return Math.abs(hash) % 360
}

// Circular character chip — supports an image URL or falls back to coloured initials.
// Works correctly with Cyrillic (spreads string by codepoint).
export function charChip(name, avatarUrl, size = 'md') {
  const el = document.createElement('div')
  el.className = `char-chip char-chip--${size}`
  el.title = name

  if (avatarUrl) {
    const img = document.createElement('img')
    img.src = avatarUrl
    img.alt = name
    el.appendChild(img)
  } else {
    const hue = nameHue(name)
    el.style.cssText = `background:hsl(${hue},35%,22%);color:hsl(${hue},70%,72%);border-color:hsl(${hue},35%,32%)`
    el.textContent = [...name].slice(0, 2).join('').toUpperCase()
  }
  return el
}

// Minimal DOM builder. Keeps hook code readable without a framework.
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag)
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v
    else if (k === 'style') el.style.cssText = v
    else if (k.startsWith('data-')) el.dataset[k.slice(5)] = v
    else el[k] = v
  }
  for (const child of children.flat()) {
    if (child == null) continue
    el.append(typeof child === 'string' ? child : child)
  }
  return el
}

export const SCHOOL_LABEL = {
  fire: 'Огонь', water: 'Вода', earth: 'Земля', air: 'Воздух',
  life: 'Жизнь', death: 'Смерть', chaos: 'Хаос', order: 'Порядок',
}

export const SCHOOL_HUE = {
  fire: 18, water: 210, earth: 80, air: 190,
  life: 140, death: 270, chaos: 320, order: 45,
}

export const ORG_KIND_LABEL = {
  cult: 'Культ', company: 'Компания', council: 'Совет', guild: 'Гильдия',
}

export const TRACK_LABEL = {
  wizardry: 'Волшебство', alchemy: 'Алхимия', mastery: 'Мастерство',
}

export const PROGRAM_LABEL = {
  basic_education: 'Базовое образование',
  academy_core: 'Академический курс',
  extended_study: 'Расширенное обучение',
  academia: 'Академия',
}
