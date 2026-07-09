# MMGO — UI Design Brief (design pass, July 2026)

This document governs every screen built in the frontend design pass.
Read it fully before writing any code. Deviations need a stated reason.

## What this pass is

We are designing **all player-facing screens** with rich, hardcoded demo
data — **no backend wiring**. Screens must look and feel finished: a
person opening any route should believe the game exists. Wiring comes
later; leave `# TODO: wire` comments at the seams (mount, handle_event).

Existing polished reference screens — study these before building:
- `lib/mmgo_web/live/map_live.ex` — the world shell aesthetic
- `lib/mmgo_web/live/spellbook_live.ex` + `.book` CSS in `assets/css/app.css` — the parchment/document aesthetic, ribbon tabs, book chrome
- `lib/mmgo_web/live/duel_live.ex` — parchment letter with ceremony
- `assets/js/hooks/spell-circle.js` — the quality bar for motion

## Hard rules (non-negotiable)

1. **Mobile-first, 375 px.** Target is a Telegram Mini App. Design at
   375×740; everything must be perfect there. Larger viewports just get
   centered content (max-width ~28rem) — do not design desktop layouts.
2. **No global navigation.** Never add nav bars, hamburger menus, tab
   bars linking to other places. Screens are physical places reached
   from the map. Every screen gets exactly one diegetic exit — a
   "← Вернуться" / "Выйти на карту" affordance styled as part of the
   scene (top-left, subtle), linking back to `/map` or its parent screen.
3. **Russian UI.** All player-visible text is Russian. Incantations and
   spell names are Latin. Tone: in-world, slightly archaic but readable —
   «Лавка торговца», not «Магазин». No emoji in UI copy (glyphs like ✦ ◆ ❧ are fine).
4. **Dual aesthetic, deliberately split:**
   - **World screens** (map, events, travel, combat, dungeon, base
     rooms): dark stone shell — `--color-bg/surface/border/accent`
     tokens. Amber is *magic and importance*; use it sparingly so it
     stays special.
   - **Document screens** (grimoires, ledgers, contracts, letters,
     academy records, notifications): parchment — `--parch-*` tokens,
     `.book`/`.book__page` chrome where a bound book fits.
   - A world screen may *contain* a document (e.g. a trade contract
     sliding up over the dark shop) — that contrast is the signature
     look of the game.
5. **Tokens only.** Use the CSS custom properties in `app.css` `:root`.
   Do not invent new hex colors; if a screen genuinely needs a new token
   (e.g. a poison green for alchemy), define it *in your own screen CSS
   file* with a comment, derived from the existing palette's warmth.
6. **Typography:** `--font-serif` (PT Serif) for all reading text;
   `--font-sans` (PT Sans, uppercase, letter-spaced) for micro-labels;
   `Great Vibes` only for ceremonial one-liners (letter salutations,
   diplomas); `--font-hand` (Caveat) for handwriting (margin notes,
   signatures, prices chalked on a board).

## Artwork placeholders

Human artists will draw all art later. **Do not** draw illustrations,
generate images, or spend effort on decorative SVG scenes. Wherever art
belongs, use the shared component (`import MMGOWeb.UIKit`):

```heex
<.art_slot kind="hero" label="Городские ворота" variant="dark" />
<.art_slot kind="icon" label="Зелье" variant="parchment" class="w-16" />
```

Kinds (export @2x px): `hero` 750×500 (full-width scene header),
`banner` 750×320, `scene` 600×600, `portrait` 300×400, `icon` 128×128.
Custom sizes via `w={}`/`h={}`. Pick the right kind and label each slot
specifically («Прилавок алхимика», not «картинка») — labels become the
artist brief.

## File conventions — strict, to allow parallel work

- One LiveView per screen family in `lib/mmgo_web/live/<name>_live.ex`,
  render inline (`~H`), demo data in module attributes or `mount/3`.
- Your CSS goes **only** in your assigned `assets/css/screens/<file>.css`.
  Prefix every class with your screen prefix (e.g. `.cbt-` for combat,
  `.trd-` for trade). Never edit `app.css`, `router.ex`,
  `core_components.ex`, `ui_kit.ex`, other batches' CSS, or `hooks/index.js`.
- Routes are already declared in `router.ex` — implement the module the
  route expects, including `live_action` variants where declared.
- Tailwind utilities are available and fine for layout/spacing; use
  custom classes for anything with personality (surfaces, glows,
  animations) so the look is centralized.
- JS hooks: prefer CSS-only animation. If a screen truly needs a hook
  (canvas, drag, complex sequencing), create
  `assets/js/hooks/<name>.js` exporting `<Name>Hook` following the style
  of existing hooks, **do not touch `index.js`** — report the hook name
  in your final summary and the orchestrator registers it.
- Mount must not touch the DB or session: no context calls, no
  `LocationGate`. Screens render for anyone. (Gating gets wired later.)
- **Never wrap a screen in `<Layouts.app>`** — that is the marketing-site
  chrome (white header with Health/LiveView links). The outermost element
  of every game screen must cover the viewport: use the shared
  `.game-screen` class (fixed, inset 0, scrollable) or your own
  equivalent fixed shell like `.game-root`/`.scene-desk`.
- **Render-test your screens.** `mix compile` does not catch HEEx
  runtime errors (e.g. `@foo` in a template reads an *assign*, not a
  module attribute). After building, run:
  `SMOKE_PORT=<unique port 4901-4989> mix run --no-start scripts/smoke_render.exs /yourroute /yourroute2`
  It prints the status per route and dumps the error on failure.
  A screen that 500s is not done.

## Demo data

Make it *lived-in*, specific and consistent across screens where cheap:
- Player: **Альберт Северин**, caster, level 12, schools Огонь + Хаос,
  balance 2 340 монет, base in city Врата Зари.
- World: realm «Княжество Эленвир», city «Врата Зари», the Tower «Башня»,
  game date 14-е Месяца Жатвы, 847 год (13 months × 28 days).
- Spells have Latin names + Russian descriptions; items have weight and
  price; NPCs/players have plausible Russian/fantasy names.
- Show *all* interesting states: filled and empty, rich and poor,
  success and failure. Use `phx-click` handlers mutating assigns so the
  screen is explorable (tabs switch, modals open, a demo action plays
  its animation). Fake latency with `Process.send_after` where a
  "working" state exists (AI thinking, travel tick).

## Quality bar — what "beautiful" means here

- **Atmosphere over chrome.** Vignettes, soft radial light, grain —
  never flat gray panels. Darkness with one warm light source.
- **Texture restraint.** Parchment gets grain and deckled edges; the
  dark shell stays clean, depth via shadow not borders.
- **Motion with meaning.** 150–250 ms eases for state changes; one
  slow ceremonial animation per screen maximum (a seal pressing, a
  circle charging). Everything else instant. `prefers-reduced-motion`
  respected for anything longer than 300 ms.
- **Touch targets ≥ 44 px**, generous line-height (1.5 for reading
  text), no font below 11 px.
- **Hierarchy in one glance:** each screen has exactly one focal point.
  If everything glows, nothing glows.

## Definition of done (per screen)

1. `mix compile` clean; page renders at its route with no console errors.
2. Looks intentional at 375×740 — no horizontal scroll, no overflow.
3. Uses tokens + correct aesthetic family; art via `<.art_slot>`.
4. Interactive demo states work via `phx-click`.
5. Diegetic exit present; no nav bars.
6. Final summary lists: routes, files touched, any new hooks, any new
   tokens added in your CSS file.
