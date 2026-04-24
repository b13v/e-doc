# Company Billing Dark-Mode Contrast Follow-up Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `/company/billing` top summary-card headings and the starter upgrade card clearly readable in dark mode.

**Architecture:** Keep this as a narrow template-only follow-up. Replace the current muted dark-mode classes on the three summary-card headings with bright explicit classes, and strengthen the upgrade card dark-mode border, surface, and text. Tighten the controller rendering test so it asserts the new exact classes instead of the previous broad “some stronger class exists somewhere” check.

**Tech Stack:** Phoenix, HEEx templates, ExUnit controller tests

---

## File Map

- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
  - Change only the top heading labels and the starter upgrade card dark-mode classes.
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
  - Replace the current broad dark-mode assertion with a narrow regression for the still-broken elements.

## Chunk 1: Tighten the Regression Test

### Task 1: Replace the weak dark-mode regression with an exact one

**Files:**
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 1: Write the failing follow-up test**

Replace the current test `"tenant billing page uses stronger dark mode contrast classes"` with a narrower version that:
- activates the starter plan so the upgrade card renders
- asserts the summary labels use `dark:text-white`
- asserts the upgrade card uses:
  - `dark:border-sky-500`
  - `dark:bg-sky-800/60`
- refutes the previous weaker upgrade treatment:
  - `dark:border-sky-700`
  - `dark:bg-sky-900/40`

Suggested structure:

```elixir
test "tenant billing page uses bright dark mode classes for summary headings and upgrade card", %{conn: conn, company: company} do
  {:ok, subscription} = Billing.get_current_subscription(company.id)
  {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

  body =
    conn
    |> get("/company/billing")
    |> html_response(200)

  assert body =~ "dark:text-white"
  assert body =~ "dark:border-sky-500"
  assert body =~ "dark:bg-sky-800/60"
  refute body =~ "dark:border-sky-700"
  refute body =~ "dark:bg-sky-900/40"
end
```

- [ ] **Step 2: Run the focused test to confirm it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected:
- FAIL because the template still uses the weaker classes.

## Chunk 2: Minimal Template Follow-up

### Task 2: Brighten only the still-broken elements

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 3: Brighten the three summary headings**

Change only the three top summary-card label classes from:

```heex
dark:text-slate-200
```

to:

```heex
dark:text-white
```

- [ ] **Step 4: Strengthen the upgrade card surface and border**

Change only the starter upgrade card dark-mode classes from:

```heex
dark:border-sky-700 dark:bg-sky-900/40
```

to:

```heex
dark:border-sky-500 dark:bg-sky-800/60
```

- [ ] **Step 5: Brighten the upgrade-card text**

Ensure the upgrade card heading and body use high-contrast text:
- heading: `dark:text-white`
- body: `dark:text-white`

Do not change the rest of the billing page in this follow-up.

## Chunk 3: Verification

### Task 3: Prove the follow-up fix

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Test: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 6: Run the focused billing test**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
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
git add lib/edoc_api_web/controllers/billing_html/show.html.heex test/edoc_api_web/controllers/billing_html_controller_test.exs
git commit -m "Fix billing page dark mode contrast follow-up"
```

Commit only this focused follow-up if asked. Do not include unrelated dirty files.
