# Company Billing Localization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the tenant-facing `/company/billing` page and its related flash messages into Russian and Kazakh without changing billing behavior.

**Architecture:** Keep all localization in the Phoenix web layer. Replace hardcoded English strings in the billing HEEx template and HTML controller with `gettext`, and add any localized display helpers in the billing HTML view module so the billing domain continues returning raw plan codes and statuses.

**Tech Stack:** Elixir, Phoenix controllers/templates, Gettext, ExUnit, HEEx

---

## File Map

- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
  - Replace hardcoded English tenant-facing billing copy with `gettext`.
- Modify: `lib/edoc_api_web/controllers/billing_html_controller.ex`
  - Localize `page_title` and all billing page flash messages.
- Modify: `lib/edoc_api_web/controllers/billing_html.ex`
  - Add localized helper functions for plan/status/reminder labels if the template needs them.
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
  - Add locale-aware rendering and flash regression tests.
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
  - Add Russian translations for billing page and flash strings.
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
  - Add Kazakh translations for billing page and flash strings.

## Chunk 1: Reproduce The English Billing UI In Tests

### Task 1: Add Russian page-copy regression coverage

**Files:**
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Reference: `lib/edoc_api_web/controllers/billing_html/show.html.heex`

- [ ] **Step 1: Add a failing Russian rendering test**

Add a new test near the existing `"tenant sees current plan..."` coverage. Reuse the existing setup and switch the test session locale to Russian:

```elixir
test "tenant billing page renders russian copy when locale is ru", %{
  conn: conn,
  billing_invoice: invoice
} do
  body =
    conn
    |> Plug.Test.init_test_session(%{user_id: conn.private.plug_session["user_id"], locale: "ru"})
    |> get("/company/billing")
    |> html_response(200)

  assert body =~ "Оплата"
  assert body =~ "Текущий тариф"
  assert body =~ "Неоплаченные счета"
  assert body =~ "Инструкция по оплате"
  refute body =~ "Billing"
  refute body =~ "Outstanding invoices"
  assert body =~ invoice.id
end
```

Do not copy this snippet blindly if the session handling is awkward in this test file. If needed, extract a small helper like:

```elixir
defp localized_conn(conn, user_id, locale) do
  build_conn()
  |> Plug.Test.init_test_session(%{user_id: user_id, locale: locale})
  |> put_private(:plug_skip_csrf_protection, true)
  |> put_req_header("accept", "text/html")
end
```

- [ ] **Step 2: Run the Russian billing-page test and confirm it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs --only focus
```

If you did not tag the test with `@tag :focus`, run the single test by line number instead:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs:LINE
```

Expected: FAIL because `/company/billing` still renders English labels such as `"Billing"` and `"Outstanding invoices"`.

### Task 2: Add Kazakh page-copy and localized flash regression coverage

**Files:**
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Reference: `lib/edoc_api_web/controllers/billing_html_controller.ex`

- [ ] **Step 1: Add a failing Kazakh rendering test**

Add a second rendering test for Kazakh locale that checks the same key billing labels:

```elixir
test "tenant billing page renders kazakh copy when locale is kk", %{
  company: company
} do
  user = Repo.get!(EdocApi.Accounts.User, company.user_id)

  body =
    localized_conn(build_conn(), user.id, "kk")
    |> get("/company/billing")
    |> html_response(200)

  assert body =~ "Төлем"
  assert body =~ "Ағымдағы тариф"
  assert body =~ "Төленбеген шоттар"
  refute body =~ "Billing"
end
```

- [ ] **Step 2: Add failing localized flash tests**

Add two flash-focused tests:

1. Russian payment submission flash
2. Kazakh upgrade invoice request flash

Shape them like:

```elixir
test "payment submission flash is localized in russian", %{billing_invoice: invoice, company: company} do
  user = Repo.get!(EdocApi.Accounts.User, company.user_id)

  conn =
    localized_conn(build_conn(), user.id, "ru")
    |> post("/company/billing/invoices/#{invoice.id}/payments", %{
      "payment" => %{
        "external_reference" => "RU-REF-1",
        "proof_attachment_url" => "https://example.com/proof.png",
        "note" => "Оплачено"
      }
    })

  assert Phoenix.Flash.get(conn.assigns.flash, :info) == "..."
end
```

and

```elixir
test "upgrade invoice request flash is localized in kazakh", %{company: company} do
  user = Repo.get!(EdocApi.Accounts.User, company.user_id)

  conn =
    localized_conn(build_conn(), user.id, "kk")
    |> post("/company/billing/upgrade-invoices", %{"plan" => "basic"})

  assert Phoenix.Flash.get(conn.assigns.flash, :info) == "..."
end
```

Use the real Russian/Kazakh strings after translations are decided. Keep assertions exact for flash text.

- [ ] **Step 3: Run the billing controller test file and confirm failures**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected: FAIL with missing Russian/Kazakh copy and English flash text still returned by the controller.

- [ ] **Step 4: Commit the failing test scaffold**

```bash
git add test/edoc_api_web/controllers/billing_html_controller_test.exs
git commit -m "Add billing localization regression tests"
```

If you prefer not to commit red tests on `main`, skip this commit and move directly to implementation. Do not commit partial green/red mixed changes later without the completed localization code.

## Chunk 2: Localize The Billing Page UI

### Task 3: Replace hardcoded English strings in the billing template

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Modify: `lib/edoc_api_web/controllers/billing_html.ex`
- Reference: `priv/gettext/ru/LC_MESSAGES/default.po`
- Reference: `priv/gettext/kk/LC_MESSAGES/default.po`

- [ ] **Step 1: Identify all tenant-facing English strings in the billing template**

Replace every hardcoded English literal in `show.html.heex`, including:

- page heading/subheading
- company settings button
- blocked banner text
- overdue banner text
- stat-card headings
- upgrade section heading/body/button
- outstanding invoices section heading/empty state
- invoice field labels (`Invoice`, `Status`, `Amount`, `Due`)
- Kaspi link label/button
- payment instructions heading/body
- payment input placeholders
- payment submit button

For interpolated text, use named placeholders, for example:

```elixir
gettext("Status: %{status}. Reason: %{reason}.",
  status: localized_status,
  reason: reason_text
)
```

- [ ] **Step 2: Add localized helpers in `billing_html.ex` only if needed**

If `plan_label/1`, `status_label/1`, or `reminder_title/1` currently emit English labels directly for this page, localize them in the billing HTML view module instead of the billing domain.

Keep the helpers small and explicit, for example:

```elixir
def plan_label(nil), do: gettext("No plan")
def plan_label(%{code: "starter"}), do: gettext("Starter")
def plan_label(%{code: "basic"}), do: gettext("Basic")
def plan_label(%{code: "trial"}), do: gettext("Trial")
```

and:

```elixir
def status_label("active"), do: gettext("Active")
def status_label("overdue"), do: gettext("Overdue")
def status_label("suspended"), do: gettext("Suspended")
def status_label(status), do: status
```

Do not move these concerns into `EdocApi.Billing`.

- [ ] **Step 3: Run the billing rendering tests**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected: some tests still fail because the controller flashes and/or missing catalog translations are not done yet.

### Task 4: Localize controller flashes and page title

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html_controller.ex`
- Reference: `test/edoc_api_web/controllers/billing_html_controller_test.exs`

- [ ] **Step 1: Localize the billing page title**

Change:

```elixir
page_title: "Billing"
```

to:

```elixir
page_title: gettext("Billing")
```

Make sure the controller has access to `gettext` through the existing web macros. Do not add custom locale plumbing unless the file actually needs it.

- [ ] **Step 2: Localize all billing-page flash messages**

Replace:

- `"Payment reference was sent for review."`
- `"Billing invoice not found."`
- `"Could not send payment reference."`
- `"Upgrade invoice request was created."`
- `"Could not create upgrade invoice request."`

with `gettext(...)`.

Keep redirect behavior exactly the same.

- [ ] **Step 3: Run the billing controller test file**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected: failures now narrow to missing translation catalog entries or mismatched expected strings.

## Chunk 3: Fill Translation Catalogs And Verify

### Task 5: Add Russian and Kazakh translations for all billing strings

**Files:**
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Reference: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Reference: `lib/edoc_api_web/controllers/billing_html_controller.ex`

- [ ] **Step 1: Add Russian catalog entries**

Add translations for every string introduced by `gettext` in the billing template/controller, including helper labels. Keep wording consistent with the tenant-facing language already used elsewhere in the app.

Suggested Russian terms to keep consistent:

- `Billing` -> `Оплата`
- `Company settings` -> `Настройки компании`
- `Current plan` -> `Текущий тариф`
- `Outstanding invoices` -> `Неоплаченные счета`
- `Payment instructions` -> `Инструкция по оплате`

Use the rest of the app’s established wording where similar strings already exist.

- [ ] **Step 2: Add Kazakh catalog entries**

Add the matching Kazakh translations, keeping terminology consistent with the rest of the tenant UI.

Suggested Kazakh terms to keep consistent:

- `Billing` -> `Төлем`
- `Company settings` -> `Компания баптаулары`
- `Current plan` -> `Ағымдағы тариф`
- `Outstanding invoices` -> `Төленбеген шоттар`
- `Payment instructions` -> `Төлем нұсқаулығы`

- [ ] **Step 3: Re-run the focused billing tests**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected: PASS.

### Task 6: Run formatting and broader verification

**Files:**
- Modify: `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- Modify: `lib/edoc_api_web/controllers/billing_html_controller.ex`
- Modify: `lib/edoc_api_web/controllers/billing_html.ex`
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`

- [ ] **Step 1: Format the touched Elixir files**

Run:

```bash
mix format \
  lib/edoc_api_web/controllers/billing_html_controller.ex \
  lib/edoc_api_web/controllers/billing_html.ex \
  test/edoc_api_web/controllers/billing_html_controller_test.exs
```

No formatter run is needed for `.heex` or `.po` unless a repo-specific tool already formats them.

- [ ] **Step 2: Run focused verification**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected: PASS.

- [ ] **Step 3: Run full verification**

Run:

```bash
mix test
```

Expected: PASS. If unrelated pre-existing failures appear, record them explicitly and do not attribute them to this billing localization change without evidence.

- [ ] **Step 4: Review the final diff**

Run:

```bash
git diff -- \
  lib/edoc_api_web/controllers/billing_html/show.html.heex \
  lib/edoc_api_web/controllers/billing_html_controller.ex \
  lib/edoc_api_web/controllers/billing_html.ex \
  test/edoc_api_web/controllers/billing_html_controller_test.exs \
  priv/gettext/ru/LC_MESSAGES/default.po \
  priv/gettext/kk/LC_MESSAGES/default.po
```

Check that:

- only tenant billing UI/controller/test/catalog files changed
- no admin billing pages changed
- no billing business logic changed

- [ ] **Step 5: Commit the finished billing localization**

```bash
git add \
  lib/edoc_api_web/controllers/billing_html/show.html.heex \
  lib/edoc_api_web/controllers/billing_html_controller.ex \
  lib/edoc_api_web/controllers/billing_html.ex \
  test/edoc_api_web/controllers/billing_html_controller_test.exs \
  priv/gettext/ru/LC_MESSAGES/default.po \
  priv/gettext/kk/LC_MESSAGES/default.po \
  docs/superpowers/plans/2026-04-24-company-billing-localization.md
git commit -m "Localize company billing page"
```

## Notes For Execution

- Follow TDD strictly: tests first, then minimal implementation.
- Keep scope on tenant-facing `/company/billing`.
- Do not localize `/admin/billing/...` as part of this plan.
- If an existing shared helper would localize admin billing pages by accident, duplicate the helper in the tenant billing HTML layer instead of broadening the change.
