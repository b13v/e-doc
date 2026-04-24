# Company Billing Dark-Mode Contrast Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize dark-mode contrast on tenant `/company/billing` so all cards, labels, helper copy, and upgrade surfaces remain readable.

**Architecture:** Keep the change template-scoped. Add a failing controller rendering test first, then update the tenant billing HEEx template to use one stronger dark-mode contrast pattern across summary cards, upgrade card, invoice blocks, and payment sections. Do not change billing logic, routes, or admin pages.

**Tech Stack:** Phoenix, HEEx templates, ExUnit controller tests, gettext-backed tenant billing UI

---

## File Map

- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
  - Normalize dark-mode text and surface classes across the full tenant billing page.
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
  - Add rendering regression coverage for stronger dark-mode classes and absence of the old weak classes.

## Chunk 1: Dark-Mode Contrast Regression Test

### Task 1: Add a failing test for billing dark-mode contrast

**Files:**
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 1: Write the failing test**

Add a focused test near the existing `/company/billing` rendering tests that:
- renders `GET /company/billing`
- asserts the page contains the stronger dark-mode classes chosen for:
  - summary-card heading labels
  - the starter upgrade card surface/text
  - nested invoice/payment helper text if those classes are normalized too
- refutes the old weak classes that caused the bug, especially:
  - `dark:text-slate-400`
  - `dark:bg-blue-950`

Suggested structure:

```elixir
test "tenant billing page uses stronger dark mode contrast classes", %{conn: conn} do
  body =
    conn
    |> get("/company/billing")
    |> html_response(200)

  assert body =~ "dark:text-slate-200"
  assert body =~ "dark:bg-sky-900/40"
  refute body =~ "dark:text-slate-400"
  refute body =~ "dark:bg-blue-950"
end
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected:
- FAIL because the current template still renders weak dark-mode classes.

## Chunk 2: Minimal Template Fix

### Task 2: Normalize `/company/billing` dark-mode contrast

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 3: Update summary-card labels**

In `show.html.heex`, replace weak dark-mode label styling on summary cards with a stronger readable label color. Keep values unchanged if they are already high contrast.

Target pattern:

```heex
<div class="text-xs font-semibold uppercase tracking-wide text-stone-500 dark:text-slate-200">
```

- [ ] **Step 4: Normalize the starter upgrade card surface and text**

Update the starter upgrade section from the current low-contrast blue treatment to a more readable dark-mode surface and body text while preserving blue semantics.

Target pattern:

```heex
class="rounded-3xl border border-blue-200 bg-blue-50 p-5 shadow-sm dark:border-sky-700 dark:bg-sky-900/40"
```

And body/heading text should use stronger readable classes such as:

```heex
dark:text-slate-100
dark:text-slate-200
```

- [ ] **Step 5: Normalize the remaining page labels and helper text**

In the same template, replace weak dark-mode small-label/helper classes in:
- outstanding invoice metadata labels
- Kaspi payment link label
- payment instruction helper copy

Use the same stronger pattern consistently so the page has one contrast system.

- [ ] **Step 6: Keep inputs readable**

Check payment form inputs and placeholders in the billing page template. If any input or helper copy still inherits weak dark-mode contrast, add explicit readable dark-mode text/placeholder classes, but do not change behavior.

## Chunk 3: Verification

### Task 3: Prove the page is fixed

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 7: Run the focused billing controller test**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected:
- PASS

- [ ] **Step 8: Run the full test suite**

Run:

```bash
mix test
```

Expected:
- PASS with no new failures

- [ ] **Step 9: Commit**

Run:

```bash
git add lib/edoc_api_web/controllers/billing_html/show.html.heex test/edoc_api_web/controllers/billing_html_controller_test.exs
git commit -m "Improve company billing dark mode contrast"
```

Commit only the billing-page contrast implementation and its regression test. Do not include unrelated dirty files.
