// GrimoireBookHook — the grimoire as a bound volume you turn with your thumb.
//
// The flip itself is StPageFlip (vendored in assets/vendor/page-flip.js): real
// paper physics — the leaf follows the drag, bends, casts a shadow into the
// gutter, and falls when released. Writing that convincingly by hand is weeks
// of work, and a page that merely fades is the thing this rework exists to
// stop being.
//
// Mobile first: portrait, one leaf at a time, sized to the viewport. A wide
// screen gets the spread for free because the library switches on width.
//
// The book is a reference and nothing else. Nothing in it is tappable: you
// read your own formula and you type it. A book you can press is a menu, and a
// menu is the thing this whole rework exists to stop being.

import {PageFlip} from "../../vendor/page-flip"

const SPELLS_PER_PAGE = 5

function parseBook(el) {
  try {
    return JSON.parse(el.dataset.book || "{}")
  } catch (_error) {
    return {}
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => {
    return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[character]
  })
}

function chunk(list, size) {
  const pages = []
  for (let index = 0; index < list.length; index += size) {
    pages.push(list.slice(index, index + size))
  }
  return pages
}

function spellMarkup(spell) {
  const note = spell.note ? `<span class="gb-entry__note">${escapeHtml(spell.note)}</span>` : ""

  return `
    <span class="gb-entry${spell.spent ? " is-spent" : ""}">
      <span class="gb-entry__seal" style="background:${escapeHtml(spell.colour || "#7a6a5c")}">
        ${escapeHtml(spell.glyph || "•")}
      </span>
      <span class="gb-entry__text">
        <span class="gb-entry__formula">${escapeHtml(spell.formula)}</span>
        <span class="gb-entry__meta">${escapeHtml(spell.name)} · ${escapeHtml(spell.cost)}</span>
        ${note}
      </span>
    </span>`
}

export const GrimoireBookHook = {
  mounted() {
    this.build()
    this.onResize = () => this.rebuild()
    window.addEventListener("resize", this.onResize)
  },

  updated() {
    // Only rebind when the contents genuinely changed: rebuilding on every
    // LiveView patch would slam the book shut mid-turn.
    const signature = this.el.dataset.book
    if (signature !== this.signature) this.rebuild()
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize)
    this.teardown()
  },

  teardown() {
    if (this.flip) {
      try {
        this.flip.destroy()
      } catch (_error) {
        // A book torn down mid-animation is still torn down.
      }
      this.flip = null
    }
  },

  rebuild() {
    const page = this.flip ? this.flip.getCurrentPageIndex() : 0
    this.teardown()
    this.build(page)
  },

  build(startPage = 0) {
    const book = parseBook(this.el)
    this.signature = this.el.dataset.book

    const spells = book.spells || []
    const capacity = Math.max(book.capacity || spells.length, spells.length, SPELLS_PER_PAGE)
    const leaves = Math.max(1, Math.ceil(capacity / SPELLS_PER_PAGE))
    const written = chunk(spells, SPELLS_PER_PAGE)

    this.el.innerHTML = `
      <div class="gb gb-desk">
        <div class="gb-stage"></div>
      </div>`

    const stage = this.el.querySelector(".gb-stage")

    for (let index = 0; index < leaves; index++) {
      const leaf = document.createElement("div")
      leaf.className = "gb-leaf"
      leaf.dataset.density = "soft"
      leaf.innerHTML = `
        ${index === 0 && book.note ? `<p class="gb-leaf__margin">${escapeHtml(book.note)}</p>` : ""}
        ${(written[index] || []).map(spellMarkup).join("")}
        <span class="gb-leaf__folio">${index + 1}</span>`
      stage.appendChild(leaf)
    }

    const {width, height} = this.leafSize()

    this.flip = new PageFlip(stage, {
      width,
      height,
      size: "fixed",
      maxShadowOpacity: 0.4,
      showCover: false,
      // Always open, always two leaves. The volume lies along the foot of the
      // screen: a single portrait page there would be a tall column in a short
      // strip, which is the wrong shape for the space it lives in.
      usePortrait: false,
      mobileScrollSupport: true,
      drawShadow: true,
      flippingTime: 600,
      swipeDistance: 24,
      useMouseEvents: true
    })

    this.flip.loadFromHTML(stage.querySelectorAll(".gb-leaf"))
    if (startPage > 0) this.flip.turnToPage(Math.min(startPage, leaves - 1))

    this.leaves = leaves
    this.bind()
  },

  // The volume lies along the foot of the screen, so it is sized by the strip
  // it lives in rather than by the page: two leaves wide, and short enough that
  // the chronicle above it keeps the room that matters.
  leafSize() {
    const available = this.el.clientWidth || window.innerWidth
    const width = Math.max(120, Math.floor(available / 2) - 10)
    const height = Math.round(window.innerHeight * 0.2)

    return {width, height: Math.max(height, 120)}
  },

  bind() {
    // Nothing to bind: the book is turned by dragging its paper, and nothing
    // written on it is pressable.
  },



}
