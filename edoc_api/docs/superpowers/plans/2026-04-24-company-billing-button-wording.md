# Company Billing Button Wording Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the two `/company` billing buttons to context-specific wording in Russian and Kazakh while keeping both links pointed at `/company/billing`.

**Architecture:** This is a wording-only UI change. Update the `/company` template so the outstanding-invoice alert CTA uses a localized `Pay` label and the subscription-header button uses a localized `Subscription details` label. Add localized gettext entries and replace the current test that assumes both buttons share one label.

**Tech Stack:** Phoenix, HEEx templates, gettext catalogs, ExUnit controller tests

---

## File Map

- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
  - Replace the two `/company/billing` button labels with new localized keys.
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
  - Replace the old shared-label billing test with explicit Russian/Kazakh wording assertions.
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
  - Add Russian translations for `Pay` and `Subscription details`.
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
  - Add Kazakh translations for `Pay` and `Subscription details`.

## Chunk 1: Regression Test

### Task 1: Replace the old shared-label billing test

**Files:**
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Test: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 1: Write the failing test**

Replace the current test `"renders both company billing links in russian with the same label"` with a new test that:
- seeds an outstanding billing invoice
- renders `/company` in Russian
- asserts the top CTA renders `Оплатить`
- asserts the subscription-header button renders `Детали подписки`
- refutes the old repeated `Оплата` wording for both buttons

Add/update the Kazakh test so it asserts the two new Kazakh labels too.

- [ ] **Step 2: Run the focused company controller test**

Run:

```bash
mix test test/edoc_api_web/controllers/companies_controller_test.exs
```

Expected:
- FAIL because the template still renders the old generic billing label.

## Chunk 2: Minimal UI and Translation Change

### Task 2: Update `/company` button wording

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Test: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 3: Update the top alert CTA label**

In `edit.html.heex`, change the outstanding billing alert CTA from:

```heex
<%= gettext("Billing") %>
```

to:

```heex
<%= gettext("Pay") %>
```

- [ ] **Step 4: Update the subscription-header button label**

In `edit.html.heex`, change the header button from:

```heex
<%= gettext("Billing") %>
```

to:

```heex
<%= gettext("Subscription details") %>
```

- [ ] **Step 5: Add Russian and Kazakh translations**

Add gettext entries:

```po
msgid "Pay"
msgstr "Оплатить"
```

```po
msgid "Subscription details"
msgstr "Детали подписки"
```

And Kazakh equivalents in `kk/LC_MESSAGES/default.po`.

## Chunk 3: Verification

### Task 3: Prove the wording change

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`

- [ ] **Step 6: Run the focused company controller test**

Run:

```bash
mix test test/edoc_api_web/controllers/companies_controller_test.exs
```

Expected:
- PASS

- [ ] **Step 7: Run the full suite**

Run:

```bash
mix test
```

Expected:
- PASS

- [ ] **Step 8: Commit**

Run:

```bash
git add lib/edoc_api_web/controllers/companies_html/edit.html.heex test/edoc_api_web/controllers/companies_controller_test.exs priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po
git commit -m "Refine company billing button wording"
```

Commit only this wording change if asked. Do not include unrelated dirty files.
