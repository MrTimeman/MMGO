# Testing

## Test stack and entry points

- Tests use ExUnit, started in `test/test_helper.exs`, with `MMGO.Repo` placed in manual SQL-sandbox mode before cases run.
- `mix.exs` compiles `test/support` in the test environment and defines `mix test` as an alias that creates the database quietly, migrates it quietly, then runs the ExUnit task.
- `README.md` documents `mix test`, `mix precommit`, and `mix format`; `justfile` supplies equivalent `just test`, `just check`, and `just fmt` wrappers.
- The required project validation command is `mix precommit` per `AGENTS.md`. In `mix.exs` it runs compile with warnings-as-errors, unused-dependency unlock, formatting, and the test alias.
- For diagnosis, `AGENTS.md` explicitly supports a focused file command such as `mix test test/mmgo/accounts_test.exs` and `mix test --failed`.

## Test configuration and isolation

- `config/test.exs` configures PostgreSQL through environment variables, uses `Ecto.Adapters.SQL.Sandbox`, and disables the endpoint server by default.
- The test database name incorporates `MIX_TEST_PARTITION` unless `MMGO_TEST_DB_NAME` is supplied, so the suite is configured for Mix test partitioning even though no repository CI workflow is checked in.
- `config/test.exs` sets Oban to `testing: :manual`, configures the AI default provider as `MMGO.AI.Providers.Mock`, and uses test-only endpoint/config values rather than production services.
- `MMGO.DataCase` in `test/support/data_case.ex` starts and stops a SQL sandbox owner for each case and exposes `errors_on/1` for changeset assertions.
- `MMGOWeb.ConnCase` in `test/support/conn_case.ex` layers Phoenix connection helpers and a built connection over the same sandbox setup.

## Organization and coverage shape

- At mapping time, `test/` contains 76 `*_test.exs` files: domain/context coverage is primarily under `test/mmgo/`, while controller and LiveView coverage is under `test/mmgo_web/controllers/` and `test/mmgo_web/live/`.
- Domain tests mirror the runtime namespaces, for example `test/mmgo/accounts_test.exs`, `test/mmgo/combat/engine_test.exs`, and `test/mmgo/world_map/path_test.exs`.
- Browser-facing flow tests cover routes, sessions, APIs, and LiveViews; `test/mmgo_web/play_demo_loop_test.exs` exercises the new/continue/reset loop and a map hook, while `test/mmgo_web/live/organizations_live_test.exs` exercises forms and navigation.
- Most cases opt into database concurrency: 59 files declare `async: true`, 9 declare `async: false`. Use `async: false` when modifying global application configuration or another shared process-level resource.

## Assertion and fixture conventions

- Tests create only the records they need in local `setup` blocks or private fixture functions, then assert both the returned tagged result and persisted state. `test/mmgo/accounts_test.exs` is a representative context test.
- Prefer outcome assertions such as `assert {:ok, value} = ...` or `assert {:error, reason} = ...`; this follows the domain error contracts rather than inspecting implementation internals.
- Connection tests build session state explicitly with `Plug.Test.init_test_session/2` and `Plug.Conn.put_session/3`, as in `test/mmgo_web/play_demo_loop_test.exs` and `test/mmgo_web/live/spellbook_live_test.exs`.
- LiveView tests import `Phoenix.LiveViewTest`, mount with `live/2`, then drive named elements/forms with `element/2`, `form/3`, `render_click/1`, `render_submit/1`, or `render_hook/3`.
- `AGENTS.md` requires stable DOM IDs and selector-based checks such as `has_element?/2` for new LiveView tests. Existing tests contain a mix of selector checks and legacy HTML text assertions, so follow the documented selector rule for additions.

## External and generative behavior

- `:bypass` is the HTTP isolation tool; six test files use it, including `test/mmgo/ai/providers/gemini_test.exs`, `test/mmgo/telegram/client_test.exs`, and `test/mmgo/federation_remote_test.exs`.
- Bypass tests restore changed application config with `on_exit/1` and run serially when they alter a provider endpoint; `test/mmgo/ai/providers/gemini_test.exs` demonstrates both practices.
- `:stream_data` is used for a property test in `test/mmgo/combat/engine_test.exs`, checking the bounded deterministic RNG across generated seeds and variances.
- There is no Mox usage in `lib/` or `test/`; test doubles are configuration-driven mocks, Bypass HTTP servers, or direct data fixtures.

## CI and validation gaps

- No `.github/` directory was present during mapping, so there is no checked-in GitHub Actions workflow to enforce the suite.
- `mix.exs` declares no coverage reporter, coverage threshold, Credo task, Dialyzer task, or property-test run configuration beyond the normal ExUnit invocation.
- Before handing off application changes, run `mix precommit` once the shared working tree is stable; use the focused file command or `mix test --failed` first when narrowing a failure.
