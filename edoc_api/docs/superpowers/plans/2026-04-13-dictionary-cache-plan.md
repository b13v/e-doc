# Dictionary Cache (banks/KBE/KNP) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop repeated DB reads for `banks`, `kbe_codes`, and `knp_codes` across HTML/API requests by introducing a shared in-memory cache with explicit refresh.

**Architecture:** Add an ETS-backed cache service (`EdocApi.Payments.DictionaryCache`) owned by a supervised GenServer. `EdocApi.Payments.list_banks/0`, `list_kbe_codes/0`, and `list_knp_codes/0` become cache-first with DB fallback and periodic/background refresh. Controllers remain unchanged and benefit transparently.

**Tech Stack:** Elixir/OTP (GenServer + ETS), Ecto, Phoenix controllers, ExUnit.

---

## File map

- Create: `lib/edoc_api/payments/dictionary_cache.ex`
- Modify: `lib/edoc_api/application.ex`
- Modify: `lib/edoc_api/payments.ex`
- Modify: `config/runtime.exs` (or `config/config.exs`) for refresh interval + enable/disable flag
- Create: `test/edoc_api/payments/dictionary_cache_test.exs`
- Create: `test/edoc_api_web/controllers/dict_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs` (cache integration assertion where useful)

---

## Chunk 1: Add cache component (test-first)

### Task 1: Build ETS cache service for dictionary sets

**Files:**
- Create: `lib/edoc_api/payments/dictionary_cache.ex`
- Create: `test/edoc_api/payments/dictionary_cache_test.exs`

- [ ] **Step 1: Write failing unit tests**
  - cache miss loads from DB and stores in ETS
  - second read is served from ETS (no extra DB query)
  - explicit `refresh/0` replaces stale data
  - service survives refresh failures and keeps last good snapshot

- [ ] **Step 2: Run failing tests**
  - Run: `mix test test/edoc_api/payments/dictionary_cache_test.exs`
  - Expected: FAIL (module/functions missing)

- [ ] **Step 3: Implement minimal cache service**
  - ETS named table with keys: `:banks`, `:kbe_codes`, `:knp_codes`
  - Public API:
    - `get(:banks | :kbe_codes | :knp_codes)`
    - `refresh/0`
  - Initial load in `init/1`
  - optional periodic refresh via `Process.send_after`

- [ ] **Step 4: Run tests and ensure pass**
  - Run: `mix test test/edoc_api/payments/dictionary_cache_test.exs`

- [ ] **Step 5: Commit**
  - `git commit -m "feat(payments): add ETS dictionary cache service"`

---

## Chunk 2: Wire cache into Payments API

### Task 2: Make `Payments.list_*` cache-first

**Files:**
- Modify: `lib/edoc_api/payments.ex`
- Modify: `lib/edoc_api/application.ex`
- Modify: `config/runtime.exs` (or `config/config.exs`)

- [ ] **Step 1: Write/extend failing tests**
  - existing calls to `Payments.list_banks/0`, `list_kbe_codes/0`, `list_knp_codes/0` return same shape/order as before
  - when cache disabled by config, functions still read directly from DB (safe fallback)

- [ ] **Step 2: Run targeted tests**
  - Run: `mix test test/edoc_api/payments/dictionary_cache_test.exs`

- [ ] **Step 3: Implement wiring**
  - Start `EdocApi.Payments.DictionaryCache` under `EdocApi.Application` supervision tree
  - In `Payments`:
    - route list calls to cache when enabled
    - preserve current ordering semantics (`name` asc, `code` asc)
  - Add config:
    - `:dictionary_cache_enabled` (default true except maybe tests if needed)
    - `:dictionary_cache_refresh_ms` (e.g. 300_000)

- [ ] **Step 4: Verify tests**
  - Run relevant unit tests and ensure no behavior regressions.

- [ ] **Step 5: Commit**
  - `git commit -m "refactor(payments): use cache-first dictionary lookups"`

---

## Chunk 3: Controller-level regression tests

### Task 3: Validate API/UI dictionary endpoints still work

**Files:**
- Create: `test/edoc_api_web/controllers/dict_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**
  - `/v1/dicts/banks`, `/v1/dicts/kbe`, `/v1/dicts/knp` return expected payload with authenticated user
  - companies setup/edit actions still render successfully with dictionary data available

- [ ] **Step 2: Run tests to confirm failure**
  - Run:
    - `mix test test/edoc_api_web/controllers/dict_controller_test.exs`
    - `mix test test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 3: Implement/fix integration issues**
  - Ensure cache process is started in test and seeded correctly
  - Add fallback path for early startup race (DB read if cache empty)

- [ ] **Step 4: Re-run tests**
  - Same commands, expected PASS.

- [ ] **Step 5: Commit**
  - `git commit -m "test(payments): add dictionary endpoint cache regression coverage"`

---

## Chunk 4: Performance validation + full verification

### Task 4: Prove reduction in repeated dictionary queries

**Files:**
- Optional create: `test/support/dictionary_cache_benchmark.exs`

- [ ] **Step 1: Add lightweight telemetry/assertion test**
  - For repeated requests to a form page, assert dictionary DB query count is reduced after warm cache.

- [ ] **Step 2: Run targeted suite**
  - `mix test test/edoc_api/payments/dictionary_cache_test.exs`
  - `mix test test/edoc_api_web/controllers/dict_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 3: Run full suite**
  - `mix test`

- [ ] **Step 4: Commit**
  - `git commit -m "perf(payments): validate dictionary cache query reduction"`

---

## Design decisions (locked)

- Use **ETS + GenServer** (not `:persistent_term`) because:
  - refresh is cheap and safe without global GC penalties from frequent updates
  - operationally easier for periodic refresh + explicit invalidation
- Keep controllers unchanged to minimize risk and touch surface.
- Keep DB fallback if cache is unavailable/empty to avoid startup race failures.
- No schema migration required.

---

## Open implementation questions

1. Refresh interval: `5m` default or longer (`15m`)?
2. Should admin actions that create/update bank/KBE/KNP entries trigger immediate cache refresh hook?
3. Should cache be disabled in `test` by default, with explicit per-test enable?

---

## Execution order

1. Chunk 1 (cache service + tests)
2. Chunk 2 (Payments wiring + supervision/config)
3. Chunk 3 (controller regressions)
4. Chunk 4 (perf assertions + full suite)

