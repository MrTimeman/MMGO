---
phase: 3
slug: real-spellbook-and-loadouts
status: approved
shadcn_initialized: false
preset: none
created: 2026-07-10
reviewed_at: 2026-07-10
---

# Phase 3 — UI Design Contract

> Visual and interaction contract for the scoped spell library and grimoire loadout workflow.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — Phoenix HEEx components and Tailwind/CSS only |
| Preset | not applicable |
| Component library | existing `MMGOWeb.UIKit` and core Phoenix components |
| Icon library | existing `<.icon>` / text glyphs only |
| Font | `PT Serif` for parchment headings/body; `PT Sans` only for compact controls |

---

## Spacing Scale

Declared values (must be multiples of 4):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Inline stat and icon gaps |
| sm | 8px | Label-to-control and compact row gaps |
| md | 16px | Form fields and card padding |
| lg | 24px | Leaf section spacing |
| xl | 32px | Major form/result separation |
| 2xl | 48px | Primary leaf break on larger screens |
| 3xl | 64px | Not used inside the book; reserved for page-level layout |

Exceptions: none. Touch controls are at least 44px tall through padding/min-height, not a new spacing token.

---

## Typography

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Label | 14px | 400 | 1.5 |
| Body | 16px | 400 | 1.5 |
| Heading | 20px | 600 | 1.2 |
| Display | 28px | 600 | 1.2 |

Only weights 400 and 600 are used. Latin incantation input retains readable body-size text and does not depend on decorative handwriting for legibility.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `--parch-paper` / `#ece0bd` | Book page, form surface, library rows |
| Secondary (30%) | `--parch-paper-dark` / `#cdb787` and `--parch-ink-faint` / `#6b5a3a` | Boundaries, inactive tabs, secondary cards |
| Accent (10%) | `--parch-gold` / `#a9791f` | “Сотворить заклинание” CTA, active grimoire badge, selected base-spell control, focus ring |
| Destructive | `--parch-red` / `#7c2b22` | Compilation failure, unavailable/error panel only; no destructive spellbook command is introduced |

Accent reserved for: primary compile CTA, the currently selected base spell, the active grimoire marker, and keyboard focus. It is never applied to every button or every library row.

---

## Screen and Interaction Contract

### Primary focal point

The composition leaf is the focal surface: a visible “Основа заклинания” selector immediately followed by the “Латинская формула” input and one gold “Сотворить заклинание” button. The current active grimoire/capacity is secondary context, never more prominent than the composition controls.

### Composition leaf

- Render a regular `<.form id="spell-compose-form">` with stable IDs: `spell-compose-base`, `spell-compose-school`, `spell-compose-formula`, `spell-compose-submit`, and `spell-compose-error`.
- The input hint states “От 1 до 6 латинских слов”; a live non-authoritative count may be shown, but server validation owns acceptance.
- Show a short success panel at `#spell-compose-result-<spell-id>` with name, formula, school, and lineage after persistence.
- Show no spinner that implies AI certainty; pending state says “Формула проверяется” and disables only the submit button.

### Library and loadouts leaf

- Use stable row IDs: `spell-library-<spell-id>`, `grimoire-<grimoire-id>`, and `grimoire-entry-<entry-id>`.
- Draft grimoires show an explicit spell picker plus `#grimoire-inscribe-<grimoire-id>`; sealed/active books show the write-once status and no inscription control.
- Activation uses a labeled “Сделать боевым гримуаром” control with an explicit pending/success/error state; it has no browser-side reorder or implicit spell choice.
- A loadout summary names the active grimoire, used slots/capacity, and weight so the trade-off is visible before combat.

### States

- Empty library: heading “Библиотека ещё пуста”; body “Изучите начальное заклинание или вернитесь к обучению, затем выберите основу для новой формулы.”
- No writable grimoire: “Нет чистого переплёта”; body explains that active/sealed books cannot be rewritten and that new physical grimoires are purchased on the market. No free-create control is rendered.
- Wrong place: “Здесь магию не составить”; body “Доберитесь до Башни или своей базы.” Include the map link.
- Travelling: “Вы в пути”; body “Дождитесь прибытия, чтобы открыть гримуар.” Include the journey link.
- Ownership/validation error: show concise Russian cause plus the next corrective action; never leak a foreign spell/grimoire name or identifier.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | `Сотворить заклинание` |
| Secondary CTA | `Записать выбранное заклинание` |
| Active loadout CTA | `Сделать боевым гримуаром` |
| Empty state heading | `Библиотека ещё пуста` |
| Empty state body | `Изучите начальное заклинание или вернитесь к обучению, затем выберите основу для новой формулы.` |
| Error state | `Формула не сложилась. Проверьте основу, школу и от 1 до 6 латинских слов, затем попробуйте снова.` |
| Destructive confirmation | No destructive action exists in this phase; write-once status is communicated before inscription rather than offering deletion. New books are purchase-only, not created from this screen. |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| none | none | no third-party registry or component source |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved 2026-07-10
