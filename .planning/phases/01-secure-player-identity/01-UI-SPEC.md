---
phase: 1
slug: secure-player-identity
status: approved
shadcn_initialized: false
preset: MMGO world-entry shell
created: 2026-07-09
---

# Phase 1 — UI Design Contract

> Visual and interaction contract for the Mini App authorization handoff and protected-game redirect states.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none |
| Preset | Existing MMGO dark world-shell tokens from `assets/css/app.css` |
| Component library | Phoenix core components only |
| Icon library | Built-in Heroicons via `<.icon>` |
| Font | `var(--font-serif)` for reading; `var(--font-sans)` for labels |

The authorization handoff is a world screen: dark stone, one warm amber point of focus, 375px-first, and no global navigation. It may use the existing `Layouts.app` wrapper required by `AGENTS.md`; the game shell inside it remains full-height and diegetic.

---

## Spacing Scale

Declared values (must be multiples of 4):

| Token | Value | Usage |
|------|-------|-------|
| xs | 4px | Icon-to-label gaps |
| sm | 8px | Status-line and compact control spacing |
| md | 16px | Default card and form spacing |
| lg | 24px | Panel padding and grouped controls |
| xl | 32px | Vertical separation between title, message, and action |
| 2xl | 48px | Small-screen top/bottom breathing room |
| 3xl | 64px | Large-screen centering buffer only |

Exceptions: none.

---

## Typography

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 16px | 400 | 1.5 |
| Label | 12px | 700 | 1.3 |
| Heading | 24px | 700 | 1.2 |
| Display | 32px | 700 | 1.1 |

Labels use uppercase `var(--font-sans)` with restrained letter spacing. Player-facing messages are Russian, concrete, and no smaller than 12px. `Great Vibes` is not used in the security/authorization state.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `var(--color-bg)` | Full-height game-entry background |
| Secondary (30%) | `var(--color-surface)` / `var(--color-surface-2)` | Centered authorization panel and quiet status area |
| Accent (10%) | `var(--color-accent)` | One readiness seal/spinner, successful entry state, and the primary retry/open action only |
| Destructive | `var(--color-danger)` | Invalid, expired, or unavailable authorization state only |

Accent reserved for: entry-ready seal, loading indicator, and the one primary action. Standard links and incidental controls use `var(--color-text-muted)`; amber must not become general navigation chrome.

---

## Interaction and State Contract

- **Entry/loading**: A centered card says `Открываем путь в Эленвир` with a short neutral loading line. No account-specific data appears before server verification succeeds.
- **Authorized**: The card confirms `Личность подтверждена` and immediately transfers to the map; if a redirect is delayed, show a compact non-interactive progress line.
- **Normal browser**: The card explains `Откройте игру из Telegram` and exposes one clearly labelled local/demo option only when the server marks it available in development/test.
- **Invalid or expired data**: The card says `Подтверждение Telegram не удалось` and tells the player to reopen the Mini App. It does not offer a bypass, reveal hash details, or create a demo account.
- **Service configuration failure**: The card says `Вход временно недоступен` and gives the same safe reopen/retry guidance; diagnostics stay server-side.
- **Protected route redirect**: An unauthenticated game route returns to this entry contract with a short `Нужно подтвердить вход` context message, not a blank page or generic 500 response.
- **Motion**: a single 180–220ms opacity/scale transition for state changes; respect `prefers-reduced-motion` by removing transform animation.
- **Touch**: every actionable control has a minimum 44px target and a stable unique DOM ID for tests.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | `Открыть в Telegram` |
| Local development CTA | `Войти в учебный мир` |
| Empty state heading | `Откройте игру из Telegram` |
| Empty state body | `Мини-приложение передаёт подтверждение входа. Вернитесь в бот и откройте игру оттуда.` |
| Error state | `Подтверждение Telegram не удалось. Закройте это окно и снова откройте игру из бота.` |
| Destructive confirmation | `Сброс учебного мира`: `Учебные данные будут пересозданы только в локальной среде.` |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Phoenix built-in | `<.icon>`, existing layout/core components | not required |
| Third-party UI registry | none | no third-party blocks permitted |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved 2026-07-09
