# Company Billing Payment Submissions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tenant payment submissions on `/company/billing` produce unmistakable visible feedback and expose those submitted payment reviews in a dedicated section on `/admin/billing/clients/:id`.

**Architecture:** Reuse the existing billing payment review flow instead of creating a new persistence model. Tighten the tenant-facing feedback path in the billing HTML flow, extend the admin client payload with a filtered `submitted_payments` collection, and render that collection in a dedicated admin section separate from the generic payment history.

**Tech Stack:** Phoenix controllers and HEEx templates, Ecto queries, Gettext, ExUnit controller tests

---

## File Structure

### Existing files to modify

- `lib/edoc_api_web/controllers/billing_html_controller.ex`
  - Tenant billing page POST path for payment submission flashes and redirect handling.
- `lib/edoc_api_web/controllers/billing_html/show.html.heex`
  - Tenant billing page markup; verify flashed feedback is visible in the actual page shell if needed.
- `lib/edoc_api/billing.ex`
  - Admin client detail data shaping and submitted-payments query/filter logic.
- `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
  - Dedicated admin section for tenant-submitted payments.
- `priv/gettext/ru/LC_MESSAGES/default.po`
  - Russian strings for any new tenant/admin labels or empty states.
- `priv/gettext/kk/LC_MESSAGES/default.po`
  - Kazakh strings for any new tenant/admin labels or empty states.
- `test/edoc_api_web/controllers/billing_html_controller_test.exs`
  - TDD coverage for success and error visibility on `/company/billing`.
- `test/edoc_api_web/controllers/admin_billing_controller_test.exs`
  - TDD coverage for the dedicated submitted-payments section on `/admin/billing/clients/:id`.

### Optional file to modify only if needed

- `test/edoc_api/billing/service_test.exs`
  - Add a focused billing query/service test only if controller tests alone are not enough to prove the submitted-payments separation.

### Responsibility boundaries

- Tenant feedback remains in the billing HTML controller/template boundary.
- Filtering of admin-visible submitted reviews belongs in `EdocApi.Billing`, not in the template.
- Admin template only renders a prepared collection and empty state.

---

## Chunk 1: Tenant Submission Feedback

### Task 1: Prove the tenant-visible feedback behavior

**Files:**
- Modify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Verify against: `lib/edoc_api_web/controllers/billing_html_controller.ex`
- Verify against: `lib/edoc_api_web/controllers/billing_html/show.html.heex`

- [ ] **Step 1: Add a failing test for the visible success outcome**

Add or tighten a controller test so it does more than check redirect state. It should GET the redirected billing page and assert the tenant can actually see the success message after submitting payment details.

```elixir
test "tenant sees visible success feedback after submitting payment details", %{
  conn: conn,
  billing_invoice: invoice
} do
  conn =
    conn
    |> post("/company/billing/invoices/#{invoice.id}/payments", %{
      "payment" => %{
        "external_reference" => "KASPI-CHECK-1",
        "proof_attachment_url" => "https://example.com/proof.png",
        "note" => "Paid by Kaspi transfer"
      }
    })
    |> recycle()
    |> get("/company/billing")

  body = html_response(conn, 200)

  assert body =~ "Payment reference was sent for review."
end
```

- [ ] **Step 2: Add failing tests for visible error outcomes**

Cover both the invoice-not-found path and the invalid submission path. The invalid case should use data that causes `Billing.create_customer_payment_review_for_company/3` to fail its changeset, for example an invalid proof URL if that is already validated by the payment schema.

```elixir
test "tenant sees invoice-not-found feedback on billing page", %{conn: conn} do
  conn =
    conn
    |> post("/company/billing/invoices/missing-id/payments", %{
      "payment" => %{"external_reference" => "NOPE"}
    })
    |> recycle()
    |> get("/company/billing")

  body = html_response(conn, 200)

  assert body =~ "Billing invoice not found."
end
```

```elixir
test "tenant sees invalid submission feedback on billing page", %{
  conn: conn,
  billing_invoice: invoice
} do
  conn =
    conn
    |> post("/company/billing/invoices/#{invoice.id}/payments", %{
      "payment" => %{
        "external_reference" => "BAD-REF",
        "proof_attachment_url" => "not-a-url"
      }
    })
    |> recycle()
    |> get("/company/billing")

  body = html_response(conn, 200)

  assert body =~ "Could not send payment reference."
end
```

- [ ] **Step 3: Run the focused tenant billing tests and confirm at least one fails**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected:
- At least one new assertion fails if the flash is not actually visible in the rendered billing page UX.

- [ ] **Step 4: Implement the minimal tenant-side fix**

Apply the smallest correct fix:

- If the controller already sets the correct flash and the billing page layout renders flashes, keep controller text as-is.
- If the billing page shell does not render flashed feedback clearly enough, update the relevant billing template/layout path so flashed messages are visible on `/company/billing`.
- Keep the redirect-based flow; do not introduce inline success state unless existing flash rendering is fundamentally broken.

Likely implementation areas:

- `lib/edoc_api_web/controllers/billing_html_controller.ex`
- `lib/edoc_api_web/controllers/billing_html/show.html.heex`
- possibly a shared layout component if `/company/billing` uniquely misses flash rendering

- [ ] **Step 5: Re-run the focused tenant tests**

Run:

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs
```

Expected:
- PASS for the newly added success/error visibility tests

- [ ] **Step 6: Commit the tenant feedback slice**

```bash
git add test/edoc_api_web/controllers/billing_html_controller_test.exs \
  lib/edoc_api_web/controllers/billing_html_controller.ex \
  lib/edoc_api_web/controllers/billing_html/show.html.heex \
  priv/gettext/ru/LC_MESSAGES/default.po \
  priv/gettext/kk/LC_MESSAGES/default.po
git commit -m "Fix tenant billing payment feedback"
```

---

## Chunk 2: Admin Submitted Payments Section

### Task 2: Prove the admin page is missing a dedicated submitted-payments section

**Files:**
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`
- Verify against: `lib/edoc_api/billing.ex`
- Verify against: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`

- [ ] **Step 1: Add a failing admin controller test for submitted payments**

Create a payment through the tenant review path, then assert the admin client detail page shows a dedicated submitted-payments section with the relevant evidence fields.

```elixir
test "platform admin sees a dedicated submitted payments section for tenant reviews", %{
  admin_conn: conn,
  company: company,
  billing_invoice: invoice
} do
  {:ok, payment} =
    Billing.create_customer_payment_review_for_company(company.id, invoice.id, %{
      "external_reference" => "KASPI-CHECK-42",
      "proof_attachment_url" => "https://example.com/proof.png",
      "note" => "Paid by tenant"
    })

  body =
    conn
    |> get("/admin/billing/clients/#{company.id}")
    |> html_response(200)

  assert body =~ "Submitted payments"
  assert body =~ payment.id
  assert body =~ "KASPI-CHECK-42"
  assert body =~ "https://example.com/proof.png"
  assert body =~ "Paid by tenant"
end
```

- [ ] **Step 2: Add a failing admin empty-state test**

This prevents the implementation from omitting the section entirely when no tenant submissions exist.

```elixir
test "platform admin sees an empty submitted payments state when there are no tenant reviews", %{
  admin_conn: conn,
  company: company
} do
  body =
    conn
    |> get("/admin/billing/clients/#{company.id}")
    |> html_response(200)

  assert body =~ "Submitted payments"
  assert body =~ "No submitted payment details yet."
end
```

- [ ] **Step 3: Run the focused admin controller tests and confirm failure**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected:
- FAIL because there is no dedicated submitted-payments section yet.

- [ ] **Step 4: Add a dedicated submitted-payments collection to the admin client payload**

In `lib/edoc_api/billing.ex`, extend `get_admin_client!/1` to return a filtered collection such as:

```elixir
submitted_payments =
  Payment
  |> where([p], p.company_id == ^company.id and p.status == ^PaymentStatus.pending_confirmation())
  |> order_by([p], desc: p.inserted_at)
  |> preload(:billing_invoice)
  |> Repo.all()
```

Also fetch review notes and attach them in a render-friendly shape. One practical pattern is to build a map keyed by payment id:

```elixir
submitted_payment_notes =
  submitted_payments
  |> Enum.map(& &1.id)
  |> list_payment_review_notes_by_payment_id()
```

Then return:

```elixir
Map.merge(summary, %{
  submitted_payments: submitted_payments,
  submitted_payment_notes: submitted_payment_notes,
  ...
})
```

If review notes are stored as audit events, add a small focused helper in `billing.ex` rather than embedding audit-query logic in the template.

- [ ] **Step 5: Render the dedicated admin section**

In `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`, insert a new section above generic `Payment History`:

```heex
<section class="rounded-3xl border border-stone-200 bg-white p-5 dark:border-slate-700 dark:bg-slate-900">
  <h2 class="text-lg font-bold text-gray-900 dark:text-slate-100"><%= gettext("Submitted payments") %></h2>

  <p :if={Enum.empty?(@client.submitted_payments)} class="mt-4 text-sm text-gray-600 dark:text-slate-300">
    <%= gettext("No submitted payment details yet.") %>
  </p>

  <div :for={payment <- @client.submitted_payments} class="mt-4 rounded-xl bg-stone-50 p-4 dark:bg-slate-800">
    ...
  </div>
</section>
```

Each card should render:

- payment id
- linked invoice id
- invoice status
- payment status
- method
- amount
- external reference if present
- proof URL if present
- inserted/submitted timestamp
- review note if present

Do not remove the existing generic `Payment History` section in this change.

- [ ] **Step 6: Add localized strings if new headings or empty states are introduced**

Modify:

- `priv/gettext/ru/LC_MESSAGES/default.po`
- `priv/gettext/kk/LC_MESSAGES/default.po`

Expected new keys at minimum:

```po
msgid "Submitted payments"
msgid "No submitted payment details yet."
msgid "Submitted at"
msgid "Proof URL"
msgid "Review note"
```

- [ ] **Step 7: Re-run the focused admin tests**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected:
- PASS for the new submitted-payments and empty-state tests

- [ ] **Step 8: Commit the admin submitted-payments slice**

```bash
git add test/edoc_api_web/controllers/admin_billing_controller_test.exs \
  lib/edoc_api/billing.ex \
  lib/edoc_api_web/controllers/admin_billing_html/client.html.heex \
  priv/gettext/ru/LC_MESSAGES/default.po \
  priv/gettext/kk/LC_MESSAGES/default.po
git commit -m "Add admin submitted billing payments section"
```

---

## Chunk 3: Separation and Regression Safety

### Task 3: Prove the dedicated admin section does not collapse into generic payment history

**Files:**
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`
- Optional: `test/edoc_api/billing/service_test.exs`
- Verify against: `lib/edoc_api/billing.ex`

- [ ] **Step 1: Add a regression test for separation**

Create at least two payment records:

- one tenant-submitted pending confirmation payment
- one confirmed or rejected payment

Assert the dedicated `Submitted payments` section contains only the tenant-submitted pending review row, while the broader `Payment History` section can still include the other payment.

If controller-level HTML assertions become too fragile, add a focused billing service test instead:

```elixir
test "admin client detail separates submitted payments from general payment history" do
  client = Billing.get_admin_client!(company.id)

  assert Enum.any?(client.submitted_payments, &(&1.id == submitted_payment.id))
  refute Enum.any?(client.submitted_payments, &(&1.id == confirmed_payment.id))
  assert Enum.any?(client.payments, &(&1.id == confirmed_payment.id))
end
```

- [ ] **Step 2: Run the targeted regression tests**

Run one of:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

or, if a service test was added:

```bash
mix test test/edoc_api/billing/service_test.exs
```

Expected:
- PASS for submitted-vs-history separation

- [ ] **Step 3: Commit the regression hardening slice**

```bash
git add test/edoc_api_web/controllers/admin_billing_controller_test.exs \
  test/edoc_api/billing/service_test.exs \
  lib/edoc_api/billing.ex
git commit -m "Harden billing submitted payment filtering"
```

---

## Chunk 4: Final Verification

### Task 4: Run the end-to-end verification set

**Files:**
- Verify: `test/edoc_api_web/controllers/billing_html_controller_test.exs`
- Verify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`
- Verify: `test/edoc_api/billing/service_test.exs`

- [ ] **Step 1: Run focused billing/controller coverage**

```bash
mix test test/edoc_api_web/controllers/billing_html_controller_test.exs \
  test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected:
- PASS

- [ ] **Step 2: Run any added billing service coverage**

```bash
mix test test/edoc_api/billing/service_test.exs
```

Expected:
- PASS

- [ ] **Step 3: Run the full suite**

```bash
mix test
```

Expected:
- PASS with no regressions

- [ ] **Step 4: Final commit if any verification-driven changes were needed**

```bash
git add lib/edoc_api/billing.ex \
  lib/edoc_api_web/controllers/billing_html_controller.ex \
  lib/edoc_api_web/controllers/billing_html/show.html.heex \
  lib/edoc_api_web/controllers/admin_billing_html/client.html.heex \
  priv/gettext/ru/LC_MESSAGES/default.po \
  priv/gettext/kk/LC_MESSAGES/default.po \
  test/edoc_api_web/controllers/billing_html_controller_test.exs \
  test/edoc_api_web/controllers/admin_billing_controller_test.exs \
  test/edoc_api/billing/service_test.exs
git commit -m "Finalize billing payment submission visibility"
```

---

## Notes for Execution

- Stay inside the existing billing payment model unless a concrete implementation blocker proves it cannot represent tenant-submitted review records.
- Do not collapse tenant submission into admin confirmation logic.
- Keep the admin dedicated section additive; the existing `Payment History` view remains useful for broader audit context.
- If `/company/billing` already renders shared flash components correctly, prefer tightening the tests over inventing new on-page status UI.
- Follow TDD strictly: write the failing test first for each slice, then implement the minimum code to make it pass.
