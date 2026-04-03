# MMGO Client

Standalone Svelte + TypeScript frontend for the Telegram Mini App surface.

## Commands

- `pnpm dev`
- `pnpm check`
- `pnpm build`
- `pnpm preview`

## Current state

- The client renders the Telegram entry gate and a map-first shell.
- In development, if `/api/mini-app/bootstrap` is not available, it falls back to typed local fixture data.
- Preview modes can be switched with the floating dev panel or with `?mode=first_open|resume|deep_link|invalid_target|recovery`.

## Expected backend contract

The client is prepared to consume a JSON bootstrap payload at:

- `GET /api/mini-app/bootstrap`

Shape:

- `view`: `"entry"` or `"shell"`
- `entry`: entry-gate state for first open, resume, deep-link, or recovery
- `shell`: map-first world shell state with HUD, markers, and panel data

That endpoint is not implemented yet in Phoenix.
