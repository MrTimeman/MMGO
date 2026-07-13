# Research Summary: Full-GDD MMGO Delivery

## Recommended strategy

MMGO does not need a new platform. Its Phoenix/Ecto/Oban monolith and broad domain contexts are the correct foundation; the missing work is secure player ownership, thin browser orchestration, and a limited set of unimplemented state machines.

## Non-negotiable sequencing

1. Secure Telegram Mini App identity and a `current_scope` before changing game pages.
2. Use a location/activity facade to replace map and action-hub demo data.
3. Wire spellbook/grimoire and make combat fully durable, timed, bounded, and readable.
4. Expose economy/base/crafting, party, dungeon, Academy, federation, and organisation systems as real vertical loops.
5. Add semantic audio/polish and audit every GDD requirement only after the core loops are playable.

## Architecture decisions

- Contexts own rules and transactions; facades own page-shaped read models and command composition; LiveViews own rendering and event translation.
- AI is a constrained service inside deterministic engine limits, with mock fixtures as the default test path.
- Timed work uses persisted timestamps + idempotent Oban jobs, with PubSub after commits.
- Semantic audio is a server-emitted cue vocabulary handled by a bundled JS hook, not a remote media system.

## Main risks to guard

- Shared demo identity and forged IDs
- Timer/worker races
- AI output exceeding rules
- Static UI mistaken for working gameplay
- Thesis defence and organisation governance state-machine holes
- Production credentials or copyrighted media leaking into source

## Roadmap implication

Use fine-grained dependency-ordered phases: identity; world/survival; spellbook/combat; economy/base/crafting; social/dungeon; Academy; realm/federation; organisations; ambience/quality. Each phase must prove a player-owned flow with focused tests before proceeding.
