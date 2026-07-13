# Concerns

## Product-completion risks

- The browser does not yet identify real players. `lib/mmgo_web/controllers/play_demo_controller.ex` and `lib/mmgo/play.ex` bootstrap fixed demo characters, while the GDD calls for Telegram Mini App identity.
- `lib/mmgo_web/router.ex` still labels many primary routes as design-pass screens; several LiveViews hold hard-coded assigns instead of querying a context.
- The real player loop currently covers map travel, inventory, and a local bot duel. High-value systems such as spell authoring, dungeon expeditions, parties, markets, workshops, bases, and organisations have backend support but incomplete player-facing flows.
- `lib/mmgo_web/live/map_live.ex` displays static calendar/profile/notification data and sends `others: []` to the map hook, so social world state and multi-realm play are not live.
- The `MMGO.Play` facade is a healthy seam, but it has only begun to expose read models and commands for the broader game. New LiveViews must use it or another narrow orchestration boundary instead of composing contexts themselves.

## Correctness and gameplay risks

- `lib/mmgo/combat/turn.ex` does not persist a turn deadline and no worker resolves expired turns. The combat engine can synthesize waits only when another caller triggers resolution.
- The GDD specifies runtime AI spell interpretation/orchestration, whereas `README.md` documents author-time compilation plus deterministic combat. `lib/mmgo/combat/narrator.ex` has no production integration. This is a product decision that must be reconciled in implementation and documentation.
- `lib/mmgo/academia.ex` appears to move a thesis defense to `:under_review` after a vote, while `run_thesis_defense/2` accepts only `:pending_defense`; a panel-vote path needs regression coverage and repair.
- `lib/mmgo/survival.ex` consumes all journey food at departure, leaving no player-facing gradual starvation and mid-journey recovery loop as described by the GDD.
- `lib/mmgo/organizations.ex` covers a useful v1 membership/role layer, but organisation treasury, shared ownership, governance enforcement, territory, and diplomacy remain absent despite being defined in the GDD roadmap.

## Security and operations risks

- `lib/mmgo/telegram.ex` accepts webhook updates when `TELEGRAM_WEBHOOK_SECRET` is unset. Production configuration should fail closed or make the development exception explicit.
- `config/runtime.exs` selects DeepSeek when its credential exists. This can unintentionally change test/runtime behavior from the Gemini/mock path; focused verification should control the provider deliberately.
- `lib/mmgo_web/router.ex` has no authenticated LiveView session/current scope for browser gameplay. Introducing identity must protect character ownership across every command path, not only controllers.
- There is no checked-in CI workflow or coverage threshold, as noted by the map in `TESTING.md`. `mix precommit` remains the main local quality gate.

## Planning guidance

- Prioritize a complete vertical path before cosmetic screens: identity -> location-gated activity -> persisted command -> updated LiveView -> focused integration test.
- Treat external Telegram production credentials, a deployed Mini App URL, and live AI keys as deployment configuration, never test fixtures or committed values.
- Keep potentially destructive migration/data changes reversible and validate existing demo fixtures while real-player sessions are introduced.
