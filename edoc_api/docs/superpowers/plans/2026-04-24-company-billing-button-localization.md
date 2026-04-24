# Company Billing Button Localization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize both `/company` links to `/company/billing` so the subscription button and the outstanding-invoice CTA use the same Russian/Kazakh wording.

**Architecture:** Keep this as a template-only change. Add regression coverage in the existing `/company` controller test file, then replace the hardcoded `Billing` button label and the banner CTA label with the same `gettext("Billing")` call in the tenant company settings template.

**Tech Stack:** Elixir, Phoenix HEEx, Gettext, ExUnit

---

## File Map

- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
  - Replace the hardcoded `Billing` label and the `Open billing` CTA label with the shared `gettext("Billing")` label.
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
  - Add locale-aware regression coverage for both `/company/billing` links on `/company`.
- Reuse only: `priv/gettext/ru/LC_MESSAGES/default.po`
- Reuse only: `priv/gettext/kk/LC_MESSAGES/default.po`

## Chunk 1: Test And Implement The Shared Billing Label

### Task 1: Add failing `/company` localization coverage

**Files:**
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Reference: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`

- [ ] **Step 1: Add a failing Russian test for both billing links**

Add a test near the existing `/company` billing banner coverage. Build a company page with outstanding billing invoices and assert that:

- `/company` renders `Оплата`
- it does not render `Billing`
- it does not render `Open billing`
- the page contains at least two `href="/company/billing"` links

Use the existing `/company` page setup patterns in this test file. Reuse the current company + billing invoice fixtures rather than creating a new one-off test helper.

- [ ] **Step 2: Add a failing Kazakh test for the header billing button**

Add a second test that renders `/company` in Kazakh locale and asserts:

- the page contains `Төлем`
- it does not contain `Billing`

If the banner is not present in the Kazakh test fixture, only assert against the visible subscription-card billing button. Do not overbuild extra setup just to force the banner into this test.

- [ ] **Step 3: Run only the `/company` controller test file**

Run:

```bash
mix test test/edoc_api_web/controllers/companies_controller_test.exs
```

Expected: FAIL because the template still contains a hardcoded English `Billing` button and the banner CTA still uses `Open billing`.

### Task 2: Implement the shared localized billing label

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Reference: `priv/gettext/ru/LC_MESSAGES/default.po`
- Reference: `priv/gettext/kk/LC_MESSAGES/default.po`

- [ ] **Step 1: Replace the subscription-card button label**

In `edit.html.heex`, change the header-side billing button from:

```heex
<a href="/company/billing" ...>
  Billing
</a>
```

to:

```heex
<a href="/company/billing" ...>
  <%= gettext("Billing") %>
</a>
```

- [ ] **Step 2: Replace the outstanding-invoice banner CTA label**

In the same template, change the banner CTA from:

```heex
<%= gettext("Open billing") %>
```

to:

```heex
<%= gettext("Billing") %>
```

Do not change the href, styling, or surrounding banner logic.

- [ ] **Step 3: Confirm no new translation keys are needed**

Do not modify the gettext catalogs unless the existing `Billing` key is missing or incorrect. The current spec assumes the `Billing` entry already exists in both Russian and Kazakh and should be reused.

- [ ] **Step 4: Run the `/company` controller test file again**

Run:

```bash
mix test test/edoc_api_web/controllers/companies_controller_test.exs
```

Expected: PASS.

### Task 3: Verify final scope and commit

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Create: `docs/superpowers/plans/2026-04-24-company-billing-button-localization.md`

- [ ] **Step 1: Run full verification**

Run:

```bash
mix test
```

Expected: PASS. If unrelated pre-existing failures appear, stop and surface them instead of guessing.

- [ ] **Step 2: Review the exact diff**

Run:

```bash
git diff -- \
  lib/edoc_api_web/controllers/companies_html/edit.html.heex \
  test/edoc_api_web/controllers/companies_controller_test.exs
```

Confirm:

- only the two `/company` billing labels changed
- no controller logic changed
- tests prove Russian/Kazakh rendering

- [ ] **Step 3: Commit the finished change**

```bash
git add \
  lib/edoc_api_web/controllers/companies_html/edit.html.heex \
  test/edoc_api_web/controllers/companies_controller_test.exs \
  docs/superpowers/plans/2026-04-24-company-billing-button-localization.md
git commit -m "Localize company billing buttons"
```

## Notes For Execution

- Follow TDD: write the failing `/company` tests first.
- Reuse the existing `Billing` gettext key.
- Keep the scope strictly on the `/company` template and its controller tests.
