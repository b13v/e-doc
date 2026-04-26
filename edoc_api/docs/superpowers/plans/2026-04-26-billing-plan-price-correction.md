# Billing Plan Price Correction Implementation Plan

> **For agentic workers:** REQUIRED: Use `superpowers:subagent-driven-development` (if subagents available) or `superpowers:executing-plans` to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change canonical billing prices to `2900 KZT` for `Starter` and `5900 KZT` for `Basic`, and reconcile all existing draft billing invoices to those prices.

**Architecture:** Keep plan price as the single source of truth in the billing plan seed/upsert path, then apply a one-time data migration that updates only draft billing invoices whose plan snapshots reference `starter` or `basic`. UI and invoice-generation paths should continue reading from plan-backed data rather than hardcoded amounts.

**Tech Stack:** Elixir, Phoenix, Ecto, PostgreSQL, ExUnit

---

## File Map

- Modify: `lib/edoc_api/billing.ex`
  - Update the default seeded plan prices for `starter` and `basic`.
- Create: `priv/repo/migrations/20260426195000_correct_billing_plan_prices.exs`
  - Reconcile persisted billing plan rows and existing draft billing invoices.
- Modify: `test/edoc_api/billing/schema_test.exs`
  - Update plan seed expectations and add coverage for corrected seeded prices.
- Modify: `test/edoc_api/billing/service_test.exs`
  - Confirm renewal/upgrade invoice creation picks up the corrected plan prices.
- Optionally modify: `test/support/...`
  - Only if a helper is needed for concise draft invoice setup. Avoid if existing fixtures suffice.

## Chunk 1: Canonical Plan Price Source

### Task 1: Update seeded billing plan prices with TDD

**Files:**
- Modify: `test/edoc_api/billing/schema_test.exs`
- Modify: `lib/edoc_api/billing.ex`

- [ ] **Step 1: Write the failing test**

Update the existing seeded-plan test in `test/edoc_api/billing/schema_test.exs` so it asserts:

```elixir
assert Repo.get_by!(Plan, code: "starter").price_kzt == 2_900
assert Repo.get_by!(Plan, code: "basic").price_kzt == 5_900
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/edoc_api/billing/schema_test.exs`

Expected: FAIL because seeded plans still use `9_900` / `29_900`.

- [ ] **Step 3: Write minimal implementation**

In `lib/edoc_api/billing.ex`, update the default plan seed definitions:

- `starter.price_kzt` from `9_900` to `2_900`
- `basic.price_kzt` from `29_900` to `5_900`

Do not change limits, plan codes, names, or any unrelated billing logic.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/edoc_api/billing/schema_test.exs`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/edoc_api/billing/schema_test.exs lib/edoc_api/billing.ex
git commit -m "Correct seeded billing plan prices"
```

## Chunk 2: Existing Draft Invoice Reconciliation

### Task 2: Add migration that corrects persisted plan prices and draft invoice amounts

**Files:**
- Create: `priv/repo/migrations/20260426195000_correct_billing_plan_prices.exs`

- [ ] **Step 1: Write the failing migration-oriented test**

Prefer the repo’s existing migration/data-change testing pattern if one exists. If the project does not test migrations directly, add a service/schema test that seeds old data explicitly and proves the reconciliation semantics expected from the migration:

```elixir
starter = insert_plan!(code: "starter", price_kzt: 9_900)
basic = insert_plan!(code: "basic", price_kzt: 29_900)

draft_starter = insert_billing_invoice!(status: "draft", plan_snapshot_code: "starter", amount_kzt: 9_900)
draft_basic = insert_billing_invoice!(status: "draft", plan_snapshot_code: "basic", amount_kzt: 29_900)
sent_basic = insert_billing_invoice!(status: "sent", plan_snapshot_code: "basic", amount_kzt: 29_900)
```

Assert after reconciliation:

```elixir
assert reloaded_starter_plan.price_kzt == 2_900
assert reloaded_basic_plan.price_kzt == 5_900
assert reloaded_draft_starter.amount_kzt == 2_900
assert reloaded_draft_basic.amount_kzt == 5_900
assert reloaded_sent_basic.amount_kzt == 29_900
```

- [ ] **Step 2: Run test to verify it fails**

Run the narrowest relevant test file, for example:

`mix test test/edoc_api/billing/schema_test.exs`

or the specific migration/data test file you created.

Expected: FAIL because old persisted amounts are not reconciled.

- [ ] **Step 3: Write minimal implementation**

Create `priv/repo/migrations/20260426195000_correct_billing_plan_prices.exs` that:

- updates `plans.price_kzt` for `starter` to `2900`
- updates `plans.price_kzt` for `basic` to `5900`
- updates `billing_invoices.amount_kzt` only where:
  - `status = 'draft'`
  - `plan_snapshot_code = 'starter'` then `amount_kzt = 2900`
  - `plan_snapshot_code = 'basic'` then `amount_kzt = 5900`

Keep the migration idempotent in practical effect:
- safe to run once in normal migration flow
- no touch to non-draft invoices
- no touch to unrelated plans

- [ ] **Step 4: Run test to verify it passes**

Run the narrow test file again.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/20260426195000_correct_billing_plan_prices.exs test/edoc_api/billing/schema_test.exs
git commit -m "Reconcile billing plan prices and draft invoices"
```

## Chunk 3: Invoice Generation Uses Corrected Prices

### Task 3: Prove renewal and upgrade invoice creation now uses `2900` / `5900`

**Files:**
- Modify: `test/edoc_api/billing/service_test.exs`
- Modify: `lib/edoc_api/billing.ex` only if service behavior still bypasses plan price data

- [ ] **Step 1: Write the failing tests**

Add or update narrow service tests around invoice creation:

```elixir
assert {:ok, starter_invoice} = Billing.create_renewal_invoice(subscription, "starter", due_at: now)
assert starter_invoice.amount_kzt == 2_900

assert {:ok, basic_invoice} = Billing.create_upgrade_invoice(subscription, "basic", due_at: now)
assert basic_invoice.amount_kzt == 5_900
```

Use existing service test patterns and helpers already present in `test/edoc_api/billing/service_test.exs`.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/edoc_api/billing/service_test.exs`

Expected: FAIL if any path still uses stale hardcoded or persisted old prices.

- [ ] **Step 3: Write minimal implementation**

If the tests fail after Chunk 1 and Chunk 2, update only the smallest necessary service path in `lib/edoc_api/billing.ex` so invoice amounts derive from the corrected plan record.

Expected likely outcome: no additional production changes needed beyond the canonical plan price correction.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/edoc_api/billing/service_test.exs`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/edoc_api/billing/service_test.exs lib/edoc_api/billing.ex
git commit -m "Cover corrected billing prices in invoice generation"
```

## Chunk 4: Full Verification

### Task 4: Run focused and full verification

**Files:**
- No production file changes expected

- [ ] **Step 1: Run focused billing tests**

Run:

```bash
mix test test/edoc_api/billing/schema_test.exs test/edoc_api/billing/service_test.exs
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
mix test
```

Expected: PASS with no new failures. If unrelated warnings appear, note them in the execution summary only if they indicate risk.

- [ ] **Step 3: Verify no hardcoded old prices remain**

Run:

```bash
rg -n "9_900|29_900|9900|29900" lib priv test -g '!deps'
```

Expected:
- old price literals removed from canonical billing code
- any remaining matches are either historical test fixtures intentionally covering old data, or migration tests explicitly proving reconciliation from stale values

- [ ] **Step 4: Final commit**

```bash
git add lib/edoc_api/billing.ex priv/repo/migrations/20260426195000_correct_billing_plan_prices.exs test/edoc_api/billing/schema_test.exs test/edoc_api/billing/service_test.exs
git commit -m "Correct billing plan prices"
```

## Notes For Executor

- The approved design called for reconciling existing draft billing invoices, not rewriting historical sent/paid invoices. Preserve that boundary.
- Do not change monetization document/seat limits. This task is price-only.
- Do not introduce UI copy changes unless you discover a numeric plan price is hardcoded in a rendered template. Current code search suggests billing UI labels are plan-name-based, not amount-literal-based.
- The spec file referenced in prior discussion was not present in the working tree during plan writing. Execute this plan against the approved design intent captured above unless the user requests a spec rewrite first.
