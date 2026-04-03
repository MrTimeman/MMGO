# Phase 1: Telegram Access and Player Shell - Research

**Researched:** 2026-04-03
**Domain:** Phoenix LiveView Telegram Mini App entry, session bootstrap, and map-first shell delivery
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The Mini App is the primary first-entry path. Players should not need to run `/start` in the bot just to begin using MMGO.
- **D-02:** A first-time Mini App open should show a lightweight MMO-style entry screen before provisioning and entering the world.
- **D-03:** Returning players should see a quick resume screen on normal app open.
- **D-04:** Notification-driven deep links must bypass the resume screen and open directly into the linked context when possible.
- **D-05:** The first-entry screen should feel like a basic MMO login screen, but without clutter.
- **D-06:** The first-entry screen must include branding/atmosphere, a realm label, a character/account preview, one strong `Enter World` CTA, and a small settings cluster.
- **D-07:** The Phase 1 in-game shell should be map-first rather than dashboard-first or character-first.
- **D-08:** The Phase 1 map should support pan and zoom plus marker inspection-level interaction, but must not expose travel actions yet.
- **D-09:** A compact persistent HUD should remain visible alongside the map.
- **D-10:** Core shell navigation should use a bottom action bar optimized for mobile Telegram usage.
- **D-11:** Recovery screens should stay in-world and atmospheric, but must still clearly explain what happened and what the player can do next.
- **D-12:** If MMGO cannot identify or restore the player from Telegram context, show a single recovery screen with one primary retry path and a secondary bot fallback.
- **D-13:** If starter world state is missing or partially broken, auto-repair when the fix is deterministic; otherwise show an explanatory recovery screen with guidance.
- **D-14:** Notification links should resume directly into the relevant destination whenever that destination/context is still valid.
- **D-15:** If the target destination is no longer valid, redirect to the closest valid context and explain briefly that the original target is no longer available.

### the agent's Discretion
- Exact structure of the settings cluster on the entry screen
- Exact compact HUD contents beyond the locked essentials
- Visual treatment, animation, and typography details within the "basic MMO login screen" direction
- Exact copy for retry/fallback messaging, provided it stays atmospheric and actionable

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<project_constraints>
## Project Constraints (from AGENTS.md)

- Run `mix precommit` when implementation work for the phase is done.
- Use the existing `Req` dependency for HTTP work; do not introduce `HTTPoison`, `Tesla`, or `:httpc`.
- Phoenix v1.8 layout rules apply: LiveView templates start with `<Layouts.app ...>` unless intentionally using the dedicated full-screen game shell; never call `<.flash_group>` outside `layouts.ex`.
- Use `MMGOWeb.Layouts` and core components already imported by `MMGOWeb`.
- Use `<.icon>` for icons and `<.input>` for form inputs when relevant.
- Tailwind v4 stays in `assets/css/app.css`; keep the existing import syntax; do not use `@apply`.
- Only `app.js` and `app.css` bundles are supported; do not add inline `<script>` tags in templates.
- Preserve a high-quality, distinctive UI rather than generic scaffolding.
- Prefer LiveView over client-heavy SPA state; use hooks only for targeted interactive surfaces.
- LiveView routes should use the router aliases and modern navigation APIs.
- Tests should prefer `Phoenix.LiveViewTest`, `element/2`, `has_element?/2`, and unique DOM IDs.
</project_constraints>

<research_summary>
## Summary

The current codebase already solves the hardest bootstrap primitive for Phase 1: `MMGO.Accounts.provision_from_telegram/1` creates or refreshes an account, Telegram identity, and starter character from Telegram user data, and `MMGO.Telegram.UpdateHandler` already routes bot updates through that provisioning path. The missing Phase 1 work is the Mini App-facing side: a browser/LiveView entrypoint, a trusted Telegram session bootstrap path, shell routing, and recovery/deep-link behavior that turns those existing account primitives into a player-facing experience.

The standard fit for this phase is Phoenix LiveView plus a small amount of JS interop. The app already uses Phoenix 1.8, LiveView 1.1, Tailwind v4, and a reusable Leaflet map hook. That means Phase 1 should not introduce a parallel SPA or a second design system. Instead, it should add one entry/resume LiveView and one map-first shell LiveView, backed by a server-owned session/bootstrap layer and covered by focused LiveView tests plus the existing accounts/webhook tests.

**Primary recommendation:** Implement Phase 1 as a LiveView-first Telegram entry pipeline: signed Mini App bootstrap -> account/character restore -> entry or resume gate -> map-first shell, with deterministic auto-repair and explicit fallback screens.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix | `~> 1.8.5` | Routing, controller/session plumbing, LiveView integration | Already the application framework and the correct place to attach Telegram browser entry |
| Phoenix LiveView | `~> 1.1.0` | Entry gate, quick resume, shell HUD, recovery screens | Matches the project architecture and keeps authoritative state on the server |
| Ecto / PostgreSQL | `ecto_sql ~> 3.13` | Account, identity, character, and restore queries | Existing account provisioning logic already lives here |
| Tailwind CSS v4 | bundled | MMO entry, shell HUD, bottom nav, recovery treatments | Existing app styling pipeline and tokens already exist in `assets/css/app.css` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Leaflet hook (`assets/js/hooks/map.js`) | existing local asset | Map pan/zoom and marker inspection | Reuse for Phase 1 map-first shell instead of replacing map tech |
| Phoenix.LiveViewTest | bundled with LiveView | Route, LiveView state, and interaction tests | Use for entry/resume/shell/recovery coverage |
| LazyHTML | `>= 0.1.0` test-only | Selector-focused HTML assertions | Use when rendered fragments need targeted verification |
| Bypass | `~> 2.1` test-only | Telegram API stubbing | Keep for webhook or outbound bot fallback scenarios |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| LiveView entry and shell | Client SPA or large custom JS app | Conflicts with the LiveView-first architecture and adds unnecessary client complexity |
| Existing Leaflet hook | Custom canvas/Pixi renderer | Not needed for Phase 1 because marker inspection and pan/zoom are already solved |
| Root controller page | Continue rendering static marketing/controller HTML | Cannot satisfy restore, quick resume, or deep-link state without re-implementing LiveView behavior later |

**Installation:** none — the required stack is already present in `mix.exs` and assets.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```text
lib/mmgo/
├── accounts.ex                         # extend restore/bootstrap helpers
├── telegram/                          # keep bot-side deep-link composition and webhook flows
└── mini_app/ or web-facing helper     # signed entry/deep-link/session bootstrap logic

lib/mmgo_web/
├── router.ex
├── live/
│   ├── telegram_entry_live.ex
│   └── player_shell_live.ex
└── components/
    └── layouts.ex

test/mmgo_web/live/
├── telegram_entry_live_test.exs
└── player_shell_live_test.exs
```

### Pattern 1: Split entry gate and in-world shell
**What:** Use one LiveView for first-open/resume/recovery/deep-link resolution and a second LiveView for the map-first shell.
**When to use:** When the shell depends on successful session restoration and the entry surface has different states from the in-world surface.
**Why:** Keeps D-02/D-03/D-04/D-12/D-15 logic isolated from the in-world HUD/map rendering.

### Pattern 2: Server-issued bootstrap context
**What:** Accept Telegram-origin browser entry params, verify/sign them into server-owned session state, then load account/character context on the server before rendering player UI.
**When to use:** Any Mini App entry or bot deep link that should restore player state without trusting arbitrary browser state.
**Why:** Matches the project’s server-authoritative constraint and reuses existing account provisioning safely.

### Pattern 3: Deterministic restore with safe auto-repair
**What:** On restore, attempt identity lookup, ensure the default character exists, and repair deterministic starter-state gaps before showing a blocking error.
**When to use:** ACCESS-02/03/04 flows where data may be partially present because the bot-side path already provisioned some records.
**Why:** The existing `ensure_default_character/3` behavior proves this style already fits the codebase.

### Pattern 4: Hook reuse under a LiveView-owned shell
**What:** Keep the map hook as a focused DOM island under `phx-hook="Map"` with `phx-update="ignore"` while LiveView owns surrounding HUD/nav/recovery state.
**When to use:** Rich map surfaces that still need server-led shell transitions.
**Why:** Avoids duplicating map logic and aligns with the project’s “minimal custom JavaScript” direction.

### Anti-Patterns to Avoid
- **Controller-first shell delivery:** rendering static controller HTML for entry or shell would make restore and LiveView state transitions harder in the next phase.
- **Client-trusted restore state:** do not let the browser be the source of account, character, or deep-link validity.
- **Horizontal plan slices:** avoid separate “all backend first, all UI later” execution; the phase needs vertically complete entry and shell slices.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Map interaction | A brand-new map renderer | Existing Leaflet hook in `assets/js/hooks/map.js` | Pan/zoom and marker events already exist |
| Shell realtime state | Client-side store / SPA hydration layer | Phoenix LiveView assigns + push events | Matches server-authoritative architecture |
| Telegram bootstrap persistence | Ad hoc unsigned browser params | Signed server session and explicit restore helpers | Prevents trust drift and broken refresh behavior |
| UI primitives | Second component system | Existing layouts, core components, app.css tokens | Reduces visual and maintenance drift |

**Key insight:** Phase 1 is an integration and shell-delivery phase, not a “new platform” phase. Reuse the existing Phoenix, LiveView, and hook foundation.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Root route converted without preserving recovery states
**What goes wrong:** `/` is changed to a LiveView shell, but restore failures fall through to generic errors or dead-end redirects.
**Why it happens:** The happy path is implemented first and ACCESS-04 is treated as polish.
**How to avoid:** Plan entry routing and recovery copy together; require a single recovery screen with retry and bot fallback per D-12.
**Warning signs:** Tests cover successful restore only; no invalid or expired bootstrap cases exist.

### Pitfall 2: Deep links implemented as a special-case URL only
**What goes wrong:** Notification links open the app but land on the generic resume screen or a broken state.
**Why it happens:** Deep-link routing is treated as pure frontend navigation instead of part of server-side restore.
**How to avoid:** Model deep-link context resolution as part of the bootstrap pipeline and test both valid and invalid target fallback per D-14/D-15.
**Warning signs:** No task or test mentions “closest valid context” behavior.

### Pitfall 3: UI shell added without authoritative player context
**What goes wrong:** The shell renders map/HUD chrome before account and character context are fully loaded.
**Why it happens:** The UI is built first and restore logic is bolted on afterward.
**How to avoid:** Make account/character resolution a prerequisite of shell mount and keep the shell LiveView dependent on an already resolved restore result.
**Warning signs:** Shell assigns are placeholder-only or depend on client-provided identity values.
</common_pitfalls>

<code_examples>
## Code Examples

### Existing restore primitive
```elixir
# Source: lib/mmgo/accounts.ex
with {:ok, telegram_attrs} <- normalize_telegram_attrs(attrs) do
  case Repo.get_by(TelegramIdentity, telegram_user_id: telegram_attrs.telegram_user_id) do
    nil -> create_telegram_account(telegram_attrs)
    identity -> refresh_telegram_account(identity, telegram_attrs)
  end
end
```

### Existing full-screen shell primitive
```elixir
# Source: lib/mmgo_web/components/layouts.ex
def game(assigns) do
  ~H"""
  <div id="game-root" class="game-root">
    <.flash_group flash={@flash} />
    {render_slot(@inner_block)}
  </div>
  """
end
```

### Existing map hook integration pattern
```javascript
// Source: assets/js/hooks/map.js
this.handleEvent("map_marker_add", ({ id, lat, lng, label }) => {
  if (this._markers[id]) this._markers[id].remove()
  const marker = L.marker([lat, lng], { title: label })
  if (label) marker.bindTooltip(label, { permanent: false, direction: "top" })
  marker.addTo(map)
  this._markers[id] = marker
})
```
</code_examples>

<validation_architecture>
## Validation Architecture

- Test infrastructure already exists: ExUnit, `Phoenix.LiveViewTest`, `LazyHTML`, and `Bypass`.
- Quick feedback should run focused files for this phase rather than the full suite.
- Phase 1 needs new LiveView tests for:
  - first-open entry screen
  - quick resume for returning players
  - invalid identity / recovery screen
  - deep-link bypass and invalid-target fallback
  - map-first shell HUD and bottom navigation rendering
- Existing `AccountsTest` should continue proving deterministic provisioning and default-character repair behavior.
- Existing webhook tests should stay narrow to webhook acceptance; Mini App flow verification belongs in LiveView tests.
</validation_architecture>

<open_questions>
## Open Questions

1. **Exact Telegram Mini App bootstrap verification boundary**
   - What we know: bot-side provisioning exists and the browser entry path does not.
   - What's unclear: whether Phase 1 will verify raw Telegram init data directly or accept an app-issued signed bootstrap token first.
   - Recommendation: decide during execution based on the current Telegram entry contract, but keep the browser session server-signed either way.

2. **Where deep-link target resolution should live**
   - What we know: D-14/D-15 require direct resume and graceful fallback.
   - What's unclear: whether target resolution belongs in a dedicated Mini App module or inside the entry LiveView mount path.
   - Recommendation: keep validation and parsing in a small domain/helper module, and let the LiveView consume a resolved target struct.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- `AGENTS.md` — Phoenix, LiveView, testing, and styling constraints
- `.planning/phases/01-telegram-access-and-player-shell/01-CONTEXT.md` — locked product decisions
- `.planning/phases/01-telegram-access-and-player-shell/01-UI-SPEC.md` — approved visual and interaction contract
- `.planning/ROADMAP.md` — phase goal, success criteria, and roadmap plan split
- `.planning/REQUIREMENTS.md` — ACCESS-01 through ACCESS-04
- `lib/mmgo/accounts.ex` — provisioning and deterministic starter-character repair
- `lib/mmgo/telegram/update_handler.ex` — Telegram provisioning trigger path
- `lib/mmgo_web/router.ex` — current browser and API routes
- `lib/mmgo_web/components/layouts.ex` — `Layouts.app/1` and `Layouts.game/1`
- `assets/js/hooks/map.js` and `assets/js/hooks/index.js` — reusable map and hook registration
- `test/mmgo/accounts_test.exs` and `test/mmgo_web/controllers/page_controller_test.exs` — current coverage baseline

### Secondary (MEDIUM confidence)
- `docs/MMGO_GDD.md` — product tone and Telegram Mini App framing
- `docs/TECH_ARCHITECTURE.md` — LiveView-first Mini App direction

### Tertiary (LOW confidence - needs validation)
- None
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: Phoenix LiveView + Telegram Mini App bootstrap
- Ecosystem: existing project stack only
- Patterns: entry gating, shell routing, map hook reuse, recovery flows
- Pitfalls: restore failure, deep-link validity, shell-before-context

**Confidence breakdown:**
- Standard stack: HIGH - all required libraries are already in the repo
- Architecture: HIGH - roadmap, context, and current code point to the same LiveView-first approach
- Pitfalls: HIGH - derived directly from phase requirements and current gaps
- Code examples: HIGH - pulled from current project files

**Research date:** 2026-04-03
**Valid until:** 2026-05-03
</metadata>

---

*Phase: 01-telegram-access-and-player-shell*
*Research completed: 2026-04-03*
*Ready for planning: yes*
