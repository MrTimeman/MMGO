# Phase 1: Telegram Access and Player Shell - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 01-Telegram Access and Player Shell
**Areas discussed:** Launch flow, Shell shape, Recovery states, Deep-link behavior

---

## Launch flow

| Option | Description | Selected |
|--------|-------------|----------|
| Bot-first | Player starts with `/start` in the Telegram bot, existing provisioning runs there, then the Mini App opens | |
| Mini-App-first | Opening the Mini App itself provisions or restores the player without requiring a bot command first | ✓ |
| Either path | Both `/start` and direct Mini App open work as first entry | |

**User's choice:** Mini-App-first
**Notes:** User explicitly wanted the Mini App to be the primary path.

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-provision and enter | Use Telegram app context to create/refresh account and starter character immediately, then land in the shell | |
| Welcome then confirm | Show a short intro screen with one clear CTA, then provision and enter | ✓ |
| Eligibility gate first | Show a pre-entry check screen before creating anything | |

**User's choice:** Welcome then confirm
**Notes:** User wanted the first screen to feel like a basic MMO login screen.

| Option | Description | Selected |
|--------|-------------|----------|
| Go straight into the player shell | Returning players skip any resume screen | |
| Show a quick resume screen | Returning players see a lightweight continue screen before entering | ✓ |
| Always show the welcome screen | Same entry screen every time | |

**User's choice:** Show a quick resume screen
**Notes:** User later clarified that notification-driven opens should not stop on this screen.

| Option | Description | Selected |
|--------|-------------|----------|
| Show preview + realm | Minimal MMO-style entry screen with account/character preview and realm label | ✓ |
| No preview | Keep entry screen to branding, atmosphere, CTA, and settings | |

**User's choice:** Show preview + realm
**Notes:** User wanted "no clutter" but still wanted it to feel like a basic MMO login screen.

## Shell shape

| Option | Description | Selected |
|--------|-------------|----------|
| Command center | Home-screen/dashboard-first shell with character summary and next actions | |
| Map-first | Overworld/map is the hero and status/actions are secondary | ✓ |
| Character-first | Character panel/status is the primary focus | |

**User's choice:** Map-first
**Notes:** This matches the project’s Mini App + world-map direction.

| Option | Description | Selected |
|--------|-------------|----------|
| Live map snapshot | Centered player map with key markers but no exploration | |
| Pan and zoom map | Player can move around visually and inspect markers, but not start travel yet | ✓ |
| Clickable location preview | Marker taps open lightweight location previews | |

**User's choice:** Pan and zoom map
**Notes:** User wanted map interaction, but this phase still avoids actual travel actions.

| Option | Description | Selected |
|--------|-------------|----------|
| Compact HUD | Slim persistent status panel with key identity/status info | ✓ |
| Minimal chrome | Map dominates, status only appears in overlays/drawers | |
| Right-side control stack | Visible side panel with summary + quick actions | |

**User's choice:** Compact HUD
**Notes:** The shell should still stay map-first.

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom action bar | Mobile-friendly dock for core actions | ✓ |
| Floating map buttons | MMO/HUD-style map-edge controls | |
| Collapsible side drawer | Slide-out action panel | |

**User's choice:** Bottom action bar
**Notes:** Keeps the shell mobile-friendly inside Telegram.

## Recovery states

| Option | Description | Selected |
|--------|-------------|----------|
| In-world but clear | Atmospheric error/recovery states with explicit next actions | ✓ |
| Pure utility | Plain operational screens optimized for clarity | |
| Mostly hidden | Terse errors with silent fallback to a safe home screen | |

**User's choice:** In-world but clear
**Notes:** Tone matters, but not at the expense of actionability.

| Option | Description | Selected |
|--------|-------------|----------|
| Single recovery screen | One clear failure screen with retry and bot fallback | ✓ |
| Hard redirect to bot | Send the player directly to `/start` recovery | |
| Limited guest shell | Enter a restricted shell with recovery instructions | |

**User's choice:** Single recovery screen
**Notes:** User wanted one clear path rather than a hidden redirect.

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-repair if safe, otherwise explain | Deterministic bootstrap fixes happen automatically; ambiguous failures get a recovery screen | ✓ |
| Always show recovery screen | No silent fixes at all | |
| Fail back to entry screen | Generic failure + entry-screen return | |

**User's choice:** Auto-repair if safe, otherwise explain
**Notes:** This aligns with the existing backend ability to ensure starter state in deterministic cases.

## Deep-link behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Direct resume | Open the exact destination/context the notification refers to whenever still valid | ✓ |
| Shell first | Always land in the main shell first | |
| Hybrid | Direct resume for actionable notifications, shell first for informational ones | |

**User's choice:** Direct resume
**Notes:** This explicitly overrides the returning-player resume-screen flow for notification opens.

| Option | Description | Selected |
|--------|-------------|----------|
| Closest valid context | Redirect to the nearest relevant valid screen with a short explanation | ✓ |
| Main shell only | Always fall back to the home shell | |
| Hard failure screen | Expired/invalid-link screen with manual navigation choice | |

**User's choice:** Closest valid context
**Notes:** User preferred graceful continuity over either a generic shell fallback or a hard-failure dead end.

## the agent's Discretion

- Exact settings cluster contents on the entry screen
- Exact HUD composition beyond the agreed compact summary direction
- Exact visual presentation of the entry/login mood
- Exact error-copy wording, as long as it remains atmospheric and actionable

## Deferred Ideas

None.
