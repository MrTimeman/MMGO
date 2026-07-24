# First Playable Loop — Implemented

This document records the original vertical slice. It is retained as a regression checklist; `docs/ALPHA_SCOPE.md` is the current release boundary.

## Local loop

1. In development and test only, `/demo/start` creates isolated local player/opponent characters, places and funds them, grants starter food and construction resources, and redirects into the real map loop. Production does not compile demo routes.
2. `/map` loads the scoped character, canonical clock, current location, reachable routes, journey/event state, nearby actors, realm data, notifications, and organisation overlays.
3. Journey actions resolve through `MMGO.Play` and `MMGO.Travel`, consume real supplies, persist arrival time, and schedule durable completion.
4. `/spellbook` reads the owned spell library and grimoires and compiles only at a valid Tower/base location.
5. `/pvp` creates and settles real scoped duel state using the shared combat engine.

The JSON `/api/play/state` and `/api/play/journeys` endpoints provide the compact hook/client boundary. LiveView remains the primary player surface and all authority is derived from the signed session.

## Regression expectations

- A missing or invalid game scope redirects to `/play`.
- Production cannot enable the shared local demo path.
- The browser never submits an authoritative character, realm, balance, outcome, or completion time.
- Starting a journey, spell compile, duel, base purchase/build, or workshop job produces durable domain state.
- Focused controller/LiveView tests use stable DOM IDs and owned session fixtures.
