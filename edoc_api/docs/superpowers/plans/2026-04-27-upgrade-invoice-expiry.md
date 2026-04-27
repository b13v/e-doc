# Upgrade Invoice Expiry And Duplicate Request Guard

## Objective

Make `Starter -> Basic` upgrade billing requests finite and non-duplicative:

- allow only one open unpaid upgrade invoice per tenant and target plan
- auto-cancel stale unpaid upgrade invoices after 7 days
- remove expired upgrade invoices from tenant actionable billing UI
- allow tenant to request a new upgrade invoice after expiry
- preserve canceled upgrade invoices and expiry auditability in admin history

## Scope

In scope:

- billing domain guard for duplicate upgrade requests
- billing lifecycle logic for automatic upgrade-invoice expiry
- tenant `/company/billing` flash behavior for blocked requests and expired requests
- admin visibility preservation for canceled upgrade invoices
- Russian/Kazakh localization for new tenant-facing messages
- regression tests for guard and expiry behavior

Out of scope:

- renewal invoice behavior
- downgrade flow
- payment confirmation flow
- any new invoice status beyond existing `canceled`

## Constraints

- Follow test-first workflow for the bug/behavior change.
- Reuse existing `billing_invoices.status == "canceled"` for auto-expired upgrades.
- Expiry window is 7 days from `due_at`, falling back to `issued_at` if `due_at` is absent.
- Duplicate blocking applies only to unpaid upgrade invoices for the same target plan.

## Implementation Steps

### 1. Add failing service tests for duplicate guard and expiry

Target files:

- [test/edoc_api/billing/service_test.exs](/home/biba/codes/e-doc/edoc_api/test/edoc_api/billing/service_test.exs)
- if needed, a narrower lifecycle-oriented test file under [test/edoc_api/billing](/home/biba/codes/e-doc/edoc_api/test/edoc_api/billing)

Add tests that prove:

- creating a second `Starter -> Basic` upgrade invoice is blocked when an open one already exists in `draft`
- the same block applies for `sent` and `overdue`
- the guard does not trigger for unrelated invoice kinds
- a canceled prior upgrade invoice allows a new request
- a stale unpaid upgrade invoice older than 7 days is auto-canceled by lifecycle processing
- expiry uses `due_at` first and `issued_at` only as fallback

Expected initial result:

- these tests fail before implementation

### 2. Add failing controller tests for tenant messaging and billing page behavior

Target files:

- [test/edoc_api_web/controllers/billing_html_controller_test.exs](/home/biba/codes/e-doc/edoc_api/test/edoc_api_web/controllers/billing_html_controller_test.exs)

Add tests that prove:

- duplicate upgrade request redirects to `/company/billing` with localized blocking flash
- after an upgrade invoice has expired, tenant billing page no longer shows it in the actionable list
- after expiry, tenant sees the localized “previous upgrade invoice expired” feedback and can request again

Keep the tests specific to current route/controller structure, not to broad HTML snapshots.

### 3. Implement billing-domain duplicate guard

Target file:

- [lib/edoc_api/billing.ex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex)

Changes:

- add a focused helper to find an existing open upgrade invoice for a company and target plan
- scope it to:
  - `note == "upgrade"`
  - `plan_snapshot_code == target plan code`
  - `status in ["draft", "sent", "overdue"]`
- enforce the guard in the narrowest correct upgrade creation path
- return a stable domain error such as `{:error, :upgrade_invoice_already_open}`

### 4. Implement automatic expiry in billing lifecycle

Target files:

- [lib/edoc_api/billing.ex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex)
- [lib/edoc_api/oban_workers/billing_lifecycle_worker.ex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/oban_workers/billing_lifecycle_worker.ex)

Changes:

- add a lifecycle pass that selects stale unpaid upgrade invoices
- compute expiry threshold from:
  - `due_at`
  - otherwise `issued_at`
- ignore invoices with neither timestamp populated
- set expired invoices to `canceled`
- record audit metadata indicating automatic expiry with reason `expired_unpaid_upgrade`
- ensure the pass is wired into the existing billing lifecycle execution path without affecting renewals

### 5. Implement tenant-controller flash handling

Target file:

- [lib/edoc_api_web/controllers/billing_html_controller.ex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/billing_html_controller.ex)

Changes:

- map `{:error, :upgrade_invoice_already_open}` to a localized error flash
- preserve the current success redirect for valid upgrade requests
- add localized feedback path for the “previous upgrade invoice expired” message on `/company/billing`
- keep the flash behavior bounded so it does not repeat indefinitely on every page load

### 6. Ensure tenant billing page only shows actionable invoices

Target files:

- [lib/edoc_api_web/controllers/billing_html/show.html.heex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/billing_html/show.html.heex)
- any billing-page helper file already shaping invoice lists

Changes:

- confirm the tenant actionable area remains limited to current payable invoices
- ensure canceled upgrade invoices do not reappear there after expiry
- do not remove admin visibility elsewhere

### 7. Preserve admin visibility and history

Target files:

- [lib/edoc_api_web/controllers/admin_billing_controller.ex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/admin_billing_controller.ex)
- [lib/edoc_api_web/controllers/admin_billing_html/client.html.heex](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/admin_billing_html/client.html.heex)
- related admin invoice list templates only if needed

Goal:

- verify canceled upgrade invoices still remain visible in admin billing history/filter flows
- avoid unnecessary admin UI churn unless tests show an actual visibility gap

### 8. Add localization entries

Target files:

- [priv/gettext/ru/LC_MESSAGES/default.po](/home/biba/codes/e-doc/edoc_api/priv/gettext/ru/LC_MESSAGES/default.po)
- [priv/gettext/kk/LC_MESSAGES/default.po](/home/biba/codes/e-doc/edoc_api/priv/gettext/kk/LC_MESSAGES/default.po)

Add translations for:

- duplicate unpaid upgrade invoice blocking message
- previous upgrade invoice expired informational message

### 9. Run targeted verification, then full test suite

Run at minimum:

- `mix test test/edoc_api/billing/service_test.exs`
- `mix test test/edoc_api_web/controllers/billing_html_controller_test.exs`
- any targeted admin billing tests touched by the visibility assertions
- `mix test`

## Risks And Checks

- The lifecycle path must not cancel renewal invoices or any invoice kind other than `upgrade`.
- Duplicate guard must not block unrelated billing invoices or future plan changes to other targets.
- The expiry feedback must not become a permanent recurring flash on every billing page load.
- Admin visibility should be verified with tests before changing templates broadly.

## Done Criteria

- tenant cannot create duplicate unpaid `Starter -> Basic` upgrade invoices
- stale unpaid upgrade invoices auto-cancel after 7 days from `due_at` or fallback `issued_at`
- expired upgrade invoices disappear from tenant actionable billing UI
- tenant sees localized blocked-request and post-expiry messaging
- admin history still retains canceled upgrade invoices
- targeted tests pass
- full `mix test` passes
