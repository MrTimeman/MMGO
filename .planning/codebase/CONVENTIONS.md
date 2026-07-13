# Code Conventions

## Sources of truth

- Repository-specific implementation rules live in `AGENTS.md`; treat them as stricter than an incidental pattern in an older module.
- `.formatter.exs` is the formatting authority: it imports Ecto/Phoenix formatting rules and enables `Phoenix.LiveView.HTMLFormatter` for `.heex`, `.ex`, and `.exs` sources.
- `mix.exs` targets Elixir `~> 1.15` and the application uses the `MMGO` / `MMGOWeb` namespace split consistently.

## Module and naming style

- Keep one focused module per file, with domain contexts in `lib/mmgo/*.ex` and schemas/implementation helpers in matching subdirectories (for example `lib/mmgo/worlds.ex` and `lib/mmgo/worlds/realm.ex`).
- Context modules import `Ecto.Query`, alias the local schemas and `MMGO.Repo`, and expose verb-led APIs such as `list_realms/0`, `create_realm/1`, and `change_realm/2` in `lib/mmgo/worlds.ex`.
- Use guards and multiple clauses to make accepted inputs explicit; `lib/mmgo/accounts.ex` distinguishes binary and integer input forms before normalizing Telegram data.
- Predicate names end in `?` (for example `magic_allowed_for_combat?/1` in `lib/mmgo/worlds.ex` and `operator_handle?/1` in `lib/mmgo/operator.ex`).
- Bang retrieval functions intentionally delegate to raising Repo calls (for example `get_realm!/1`); non-bang lookup functions return a record or `nil` (`get_realm_by_slug/1`).
- Typespecs and module documentation are applied selectively to public algorithmic or cross-cutting APIs, such as `MMGOWeb.LocationGate` in `lib/mmgo_web/live/location_gate.ex` and world-map modules under `lib/mmgo/world_map/`.

## Ecto and domain boundaries

- Persisted schemas generally declare binary primary/foreign keys and UTC microsecond timestamps; representative definitions are `lib/mmgo/accounts/account.ex`, `lib/mmgo/worlds/realm.ex`, and `lib/mmgo/combat/combat.ex`.
- Schemas own their changesets: cast only permitted fields, validate shape/business constraints, then add database constraints. `Realm.changeset/2` validates the ruleset and unique indexes in `lib/mmgo/worlds/realm.ex`.
- Context functions construct schemas and call Repo; callers receive `{:ok, value}` / `{:error, changeset_or_reason}` rather than handling raw Ecto operations.
- Multi-record workflows use `Ecto.Multi` plus `Repo.transaction/1`. `lib/mmgo/accounts.ex` provisions account, Telegram identity, and character atomically; `lib/mmgo/combat.ex` locks and resolves a combat inside a transaction.
- Preload relations before consuming them across a boundary or template. `MMGO.Combat.get_combat!/1` preloads participants and their required nested relations in `lib/mmgo/combat.ex`.
- Normalize string/atom-keyed input deliberately instead of atomizing user data; `lib/mmgo/accounts.ex` uses known Telegram keys and map conversion helpers.

## Failure handling

- Expected business failures are explicit tagged values: `MMGO.Accounts.provision_from_telegram/1` returns `{:error, :invalid_update}`, while `MMGO.Combat.submit_action/3` returns domain atoms such as `:participant_not_found`.
- Use `with` and `case` to propagate or translate these results. `lib/mmgo/combat.ex` rolls back a transaction on a resolution error; `lib/mmgo/accounts.ex` translates a missing default realm into `{:error, :default_realm_not_found}`.
- Changeset-oriented failures remain changesets when user input should be corrected; several contexts normalize `Ecto.Multi` error shapes before returning them (for example `lib/mmgo/pvp.ex` and `lib/mmgo/reputation.ex`).
- Oban workers turn invalid domain outcomes into intentional job outcomes; `lib/mmgo/alchemy/complete_brew_job_worker.ex` returns `{:discard, :invalid_brew_job}` for an invalid completed brew.
- Controllers convert failures at the HTTP boundary. `lib/mmgo_web/controllers/play_demo_controller.ex` uses a flash plus redirect for browser startup errors and a 500 JSON response for reset failures; generic protocol errors live in `lib/mmgo_web/controllers/error_json.ex` and `lib/mmgo_web/controllers/error_html.ex`.

## Phoenix and LiveView

- Web modules use the shared macros in `lib/mmgo_web.ex`; those provide verified `~p` routes, core components, `MMGOWeb.Layouts`, and Gettext helpers to controllers, LiveViews, and HTML modules.
- Follow the strict LiveView rules in `AGENTS.md` for new or revised templates: wrap content with `<Layouts.app flash={@flash} ...>`, pass `current_scope` when applicable, and keep `<.flash_group>` inside `lib/mmgo_web/components/layouts.ex`.
- Use `@impl true` callbacks, socket assigns, `push_navigate`/`push_patch`, and verified routes rather than deprecated LiveView redirects/patches. `lib/mmgo_web/live/location_gate.ex` is a compact example of returning an updated socket or a redirected halt.
- Assign stable DOM IDs to interactive controls and forms. Existing tests target IDs such as `#org-create-form` in `test/mmgo_web/live/organizations_live_test.exs` and `#map-character-panel` in `test/mmgo_web/play_demo_loop_test.exs`.
- Keep client behavior in the bundled assets or permitted LiveView hooks; `AGENTS.md` forbids raw inline scripts and specifies colocated/external hook conventions.

## UI and incomplete seams

- UI code uses HEEx and Phoenix components, with Tailwind/custom CSS guidance defined in `AGENTS.md`; do not add external script/style tags to layouts.
- Some design-pass LiveViews intentionally hold demo state in assigns and mark persistence seams with `# TODO: wire`, notably `lib/mmgo_web/live/organizations_live.ex`, `lib/mmgo_web/live/action_hub_live.ex`, and `lib/mmgo_web/live/combat_live.ex`. Preserve that distinction until backend wiring is explicitly in scope.
