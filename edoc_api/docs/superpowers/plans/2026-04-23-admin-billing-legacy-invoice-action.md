# Admin Billing Legacy Invoice Action Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let platform admins create the missing billing invoice for legacy pending billing clients from `/admin/billing/clients/:id`.

**Architecture:** Add a focused billing context function that converts an active legacy tenant subscription into a normal billing subscription and draft billing invoice when no current billing invoice exists. Expose it through a platform-admin-only POST route and render a visible action on the admin client detail page for legacy pending clients.

**Tech Stack:** Phoenix 1.7 controllers/templates, Ecto schemas and queries, ExUnit controller tests, existing `EdocApi.Billing` context.

---

## File Structure

- Modify `lib/edoc_api/billing.ex`: add a public function for creating a legacy pending billing invoice and add legacy pending metadata to admin client summaries.
- Modify `lib/edoc_api_web/router.ex`: add the admin POST route.
- Modify `lib/edoc_api_web/controllers/admin_billing_controller.ex`: add the controller action and audit event.
- Modify `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`: render the legacy pending invoice action.
- Modify `lib/edoc_api_web/controllers/admin_billing_html/invoices.html.heex`: make pending row action link to the client detail page.
- Modify `test/edoc_api_web/controllers/admin_billing_controller_test.exs`: add regression coverage for the broken flow.

## Chunk 1: Reproduce The Broken Admin Flow

### Task 1: Add failing tests for legacy pending invoice creation

**Files:**
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 1: Write a failing client-detail visibility test**

Add a test near the existing legacy billing tests:

```elixir
test "platform admin can see create invoice action for legacy pending billing client", %{
  admin_conn: conn
} do
  user = create_user!(%{"email" => "legacy-action-admin@example.com"})
  company = create_company!(user, %{name: "Legacy Action Client"})

  create_legacy_subscription!(company.id, %{
    plan: "basic",
    status: "active",
    period_start: ~U[2026-04-01 00:00:00Z],
    period_end: ~U[2026-05-01 00:00:00Z]
  })

  body =
    conn
    |> get("/admin/billing/clients/#{company.id}")
    |> html_response(200)

  assert body =~ "Pending billing invoice"
  assert body =~ ~s(action="/admin/billing/clients/#{company.id}/legacy-invoices")
  assert body =~ "Create billing invoice"
end
```

- [ ] **Step 2: Write a failing POST test**

Add:

```elixir
test "platform admin creates billing invoice from legacy pending client", %{
  admin_conn: conn
} do
  user = create_user!(%{"email" => "legacy-create-admin@example.com"})
  company = create_company!(user, %{name: "Legacy Create Client"})

  create_legacy_subscription!(company.id, %{
    plan: "basic",
    status: "active",
    period_start: ~U[2026-04-01 00:00:00Z],
    period_end: ~U[2026-05-01 00:00:00Z]
  })

  conn = post(conn, "/admin/billing/clients/#{company.id}/legacy-invoices")

  assert redirected_to(conn) == "/admin/billing/invoices"

  body =
    build_admin_conn()
    |> get("/admin/billing/invoices")
    |> html_response(200)

  assert body =~ "Legacy Create Client"
  refute body =~ "pending-"
  refute body =~ "Create the billing invoice from the client detail page"
end
```

If `build_admin_conn/0` is unavailable in the test module, reuse the existing admin connection setup pattern from the file.

- [ ] **Step 3: Write a failing invoice-list link test**

Extend the existing test for legacy monetization tenants on `/admin/billing/invoices`:

```elixir
assert body =~ ~s(href="/admin/billing/clients/#{company.id}")
assert body =~ "Create from client detail"
```

- [ ] **Step 4: Run the focused test file and verify failures**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected: FAIL because the route, billing function, and client-detail action do not exist yet.

## Chunk 2: Add Billing Context Support

### Task 2: Implement legacy pending invoice creation in `EdocApi.Billing`

**Files:**
- Modify: `lib/edoc_api/billing.ex`

- [ ] **Step 1: Expose legacy pending state in admin client summary**

In `get_admin_client!/1`, add a `legacy_pending_billing_invoice` field to the returned map.

Implementation shape:

```elixir
legacy_pending_invoice =
  if summary.subscription do
    nil
  else
    latest_active_billable_legacy_subscription(company.id)
  end

Map.merge(summary, %{
  memberships: memberships,
  invoices: invoices,
  payments: payments,
  notes: notes,
  legacy_pending_billing_invoice: legacy_pending_invoice
})
```

Use the existing legacy subscription query helpers where possible. Keep this read-only and side-effect free.

- [ ] **Step 2: Add public creation function**

Add:

```elixir
@doc "Creates the missing billing invoice for a legacy active tenant subscription."
def create_legacy_pending_billing_invoice(company_or_id) do
  company_id = record_id(company_or_id)

  with {:ok, legacy_subscription} <- fetch_active_billable_legacy_subscription(company_id),
       {:ok, subscription} <- ensure_current_subscription_from_legacy(legacy_subscription),
       :ok <- ensure_no_open_billing_invoice(subscription, legacy_subscription) do
    create_billing_invoice(subscription, legacy_subscription.plan, "legacy_pending", [
      period_start: legacy_subscription.period_start,
      period_end: legacy_subscription.period_end,
      due_at: legacy_subscription.period_end
    ])
  end
end
```

Adapt option names to the existing private `create_billing_invoice/4` API. If it does not accept period overrides yet, add the smallest private support needed.

- [ ] **Step 3: Add private helpers**

Add helpers near existing legacy helpers:

```elixir
defp fetch_active_billable_legacy_subscription(company_id) do
  case latest_active_billable_legacy_subscription(company_id) do
    nil -> {:error, :legacy_subscription_not_found}
    subscription -> {:ok, subscription}
  end
end
```

Add `latest_active_billable_legacy_subscription/1` using the existing `TenantSubscription` schema:

```elixir
TenantSubscription
|> where([s], s.company_id == ^company_id)
|> where([s], s.status == "active" and s.plan in ["starter", "basic"])
|> order_by([s], desc: s.period_end, desc: s.inserted_at)
|> limit(1)
|> Repo.one()
```

Add duplicate protection by checking existing invoices for the same company and period where status is not cancelled/rejected. If the billing model has no cancelled status, check any billing invoice for that subscription and period.

- [ ] **Step 4: Run focused context-related tests**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected: still FAIL because route/controller/template are not wired yet, but context compilation should pass.

## Chunk 3: Wire Route And Controller

### Task 3: Add admin POST endpoint

**Files:**
- Modify: `lib/edoc_api_web/router.ex`
- Modify: `lib/edoc_api_web/controllers/admin_billing_controller.ex`

- [ ] **Step 1: Add route**

Inside the admin billing scope, add:

```elixir
post("/billing/clients/:id/legacy-invoices", AdminBillingController, :create_legacy_invoice)
```

- [ ] **Step 2: Add controller action**

Add to `AdminBillingController`:

```elixir
def create_legacy_invoice(conn, %{"id" => company_id}) do
  case Billing.create_legacy_pending_billing_invoice(company_id) do
    {:ok, invoice} ->
      audit_admin_action(
        conn,
        invoice.company_id,
        "admin_legacy_invoice_created",
        "billing_invoice",
        invoice.id,
        %{company_id: company_id}
      )

      conn
      |> put_flash(:info, "Billing invoice created.")
      |> redirect(to: "/admin/billing/invoices")

    {:error, reason} ->
      conn
      |> put_flash(:error, legacy_invoice_error_message(reason))
      |> redirect(to: "/admin/billing/clients/#{company_id}")
  end
end
```

Add a small private `legacy_invoice_error_message/1` function with stable English admin messages. Admin billing pages are currently English-only.

- [ ] **Step 3: Run focused tests**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected: route/controller failures should be resolved; template tests may still fail.

## Chunk 4: Render Admin UI Actions

### Task 4: Add client detail action and invoice-list link

**Files:**
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/invoices.html.heex`

- [ ] **Step 1: Render legacy action on client detail**

Below the normal `Admin Actions` section, add:

```heex
<section :if={@client.legacy_pending_billing_invoice} class="rounded-3xl border border-amber-200 bg-amber-50 p-5 dark:border-amber-500/40 dark:bg-amber-950/40">
  <h2 class="text-lg font-bold text-gray-900 dark:text-white">Pending billing invoice</h2>
  <p class="mt-2 text-sm text-gray-700 dark:text-amber-50">
    This client has an active legacy billing plan but no created billing invoice yet.
  </p>
  <form action={"/admin/billing/clients/#{@client.company.id}/legacy-invoices"} method="post" class="mt-4">
    <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
    <button type="submit" class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700">
      Create billing invoice
    </button>
  </form>
</section>
```

Keep dark-mode text high-contrast.

- [ ] **Step 2: Replace static pending invoice action text with a link**

In `invoices.html.heex`, for virtual invoices, replace the plain span with:

```heex
<a
  href={"/admin/billing/clients/#{invoice.company.id}"}
  class="font-semibold text-blue-700 hover:text-blue-900 dark:text-sky-300"
>
  Create from client detail
</a>
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected: all admin billing controller tests pass.

## Chunk 5: Full Verification And Commit

### Task 5: Verify, format, and commit

**Files:**
- All files modified above

- [ ] **Step 1: Format touched Elixir and HEEx files**

Run:

```bash
mix format lib/edoc_api/billing.ex lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/admin_billing_controller.ex lib/edoc_api_web/controllers/admin_billing_html/client.html.heex lib/edoc_api_web/controllers/admin_billing_html/invoices.html.heex test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

- [ ] **Step 2: Run focused tests**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected: `15+ tests, 0 failures`.

- [ ] **Step 3: Run full suite**

Run:

```bash
mix test
```

Expected: full suite passes.

- [ ] **Step 4: Inspect diff**

Run:

```bash
git diff -- lib/edoc_api/billing.ex lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/admin_billing_controller.ex lib/edoc_api_web/controllers/admin_billing_html/client.html.heex lib/edoc_api_web/controllers/admin_billing_html/invoices.html.heex test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Confirm the diff only includes the legacy pending invoice flow.

- [ ] **Step 5: Commit**

Run:

```bash
git add lib/edoc_api/billing.ex lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/admin_billing_controller.ex lib/edoc_api_web/controllers/admin_billing_html/client.html.heex lib/edoc_api_web/controllers/admin_billing_html/invoices.html.heex test/edoc_api_web/controllers/admin_billing_controller_test.exs docs/superpowers/plans/2026-04-23-admin-billing-legacy-invoice-action.md
git commit -m "Add admin legacy billing invoice action"
```

Do not stage unrelated dirty files.
