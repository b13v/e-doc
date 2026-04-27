# Upgrade Invoice Expiry And Duplicate Request Guard

## Summary

The current billing flow allows a tenant on `Starter` to request a `Basic` upgrade invoice from `/company/billing`, but the resulting unpaid upgrade invoice can remain open indefinitely. The system also does not prevent repeated upgrade requests for the same target plan, which can create duplicate unpaid upgrade invoices for one tenant.

This change makes the upgrade-invoice lifecycle finite and predictable:

- only one active unpaid upgrade invoice per tenant and target plan
- duplicate upgrade requests are blocked while that invoice is still open
- stale unpaid upgrade invoices auto-expire after 7 days
- auto-expired upgrade invoices disappear from the tenant’s actionable billing view
- tenant can request a new upgrade invoice again after expiry
- admin keeps full visibility into canceled/expired upgrade invoices and their audit trail

## Current Behavior

Current code path:

- tenant requests upgrade on `/company/billing`
- [`EdocApiWeb.BillingHTMLController.create_upgrade_invoice/2`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/billing_html_controller.ex)
- [`EdocApi.Billing.create_upgrade_invoice_for_company/3`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex)
- [`EdocApi.Billing.create_immediate_upgrade_invoice/3`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex)
- [`EdocApi.Billing.create_upgrade_invoice/3`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex)

Observed lifecycle today:

- upgrade invoice is created as `draft`
- admin may later mark it `sent`
- overdue processing can move it to `overdue`
- subscription may move to `grace_period` and later `suspended`
- invoice is not auto-canceled or auto-expired
- repeated upgrade requests are not guarded against existing unpaid upgrade invoices

## Goals

- prevent duplicate unpaid upgrade invoices for the same tenant and target plan
- ensure stale unpaid upgrade invoices do not remain actionable forever
- keep tenant billing UI focused on currently payable actions only
- preserve complete billing history and auditability for admins

## Non-Goals

- no changes to renewal invoice behavior
- no new billing invoice status like `expired`
- no changes to payment-confirmation flow
- no changes to downgrade flow

## Recommended Approach

Reuse existing `billing_invoices.status == "canceled"` for auto-expired upgrade invoices instead of introducing a new status.

Reasoning:

- `canceled` already exists in the billing model
- it avoids broad enum/UI/filter changes
- the important distinction is carried in audit metadata, not a new invoice status

## Business Rules

### 1. Duplicate Upgrade Request Guard

When a tenant requests `Starter -> Basic` from `/company/billing`:

- search for an existing invoice for the same company where:
  - `note == "upgrade"`
  - `plan_snapshot_code == "basic"`
  - `status in ["draft", "sent", "overdue"]`
- if such an invoice exists, do not create another invoice
- return a domain error that the tenant controller maps to a localized flash

Tenant-facing result:

- request is blocked
- message says an unpaid upgrade invoice already exists and they should pay it or contact the platform administrator

### 2. Upgrade Invoice Expiry Window

An unpaid upgrade invoice auto-expires after 7 days.

Expiry timestamp rule:

- use `due_at` when present
- otherwise fall back to `issued_at`
- if both are absent, the invoice is not eligible for expiry yet

Target invoices for auto-expiry:

- `note == "upgrade"`
- `status in ["draft", "sent", "overdue"]`
- age threshold reached based on the rule above

### 3. Expiry Outcome

When an upgrade invoice expires:

- set `status` to `canceled`
- write a billing audit event indicating automatic expiry

Recommended audit metadata:

- `reason: "expired_unpaid_upgrade"`
- `expired_at`
- `based_on: "due_at"` or `"issued_at"`

### 4. Tenant UI Behavior

Tenant `/company/billing` should continue to show only actionable invoices in the main outstanding-invoice area.

Result:

- `sent` and `overdue` remain visible there
- auto-canceled upgrade invoices disappear from tenant actionable UI
- after cancellation, the `Request upgrade to Basic` action becomes available again

Additionally:

- on the first relevant billing-page load after auto-expiry, tenant should see a localized flash:
  - previous upgrade invoice expired
  - they can request a new one

This flash should be tied to actual expiry detection state, not shown repeatedly forever.

### 5. Admin Behavior

Admin billing pages must keep visibility into expired upgrade invoices.

Result:

- canceled upgrade invoices remain in admin billing history and filters
- admin client detail and invoice list can still surface them through status/history views
- audit metadata makes it clear they were auto-expired, not manually canceled

## Architecture

### Billing Context

Primary changes belong in [`EdocApi.Billing`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/billing.ex):

- add a helper to find an existing open upgrade invoice for a company and target plan
- enforce the duplicate-request guard in `create_upgrade_invoice_for_company/3` or the narrowest correct downstream boundary
- add lifecycle logic to expire stale unpaid upgrade invoices
- emit billing audit records for automatic expiry

### Lifecycle Worker

Current lifecycle worker:

- [`EdocApi.ObanWorkers.BillingLifecycleWorker`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api/oban_workers/billing_lifecycle_worker.ex)

Recommended shape:

- extend scheduled billing lifecycle processing with an upgrade-expiry pass
- either:
  - add a dedicated action such as `expire_unpaid_upgrade_invoices`
  - or fold the logic into existing billing lifecycle execution if that keeps responsibilities clearer

Recommendation:

- dedicated action is clearer and easier to test independently

### Tenant Controller

Tenant entry point:

- [`EdocApiWeb.BillingHTMLController.create_upgrade_invoice/2`](/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/billing_html_controller.ex)

Required behavior:

- map duplicate-upgrade error to a localized blocking flash
- preserve existing success path for legitimate upgrade requests
- support one-time expiry feedback on `/company/billing`

## Data Flow

### Request Upgrade

1. Tenant submits `POST /company/billing/upgrade-invoices`
2. Billing checks for existing open upgrade invoice for the same target plan
3. If found:
   - return domain error
   - controller redirects to `/company/billing` with localized error flash
4. If not found:
   - create upgrade invoice as today
   - controller redirects with success flash

### Auto-Expire Upgrade Invoice

1. Scheduled billing lifecycle job runs
2. Billing selects stale unpaid upgrade invoices
3. Each selected invoice is updated to `canceled`
4. Audit event is inserted
5. Tenant no longer sees the invoice in outstanding actionable list
6. Tenant can request a new upgrade invoice again

## Error Handling

New domain error recommended:

- `{:error, :upgrade_invoice_already_open}`

Possible controller flash copy:

- Russian/Kazakh localized equivalent of:
  - `An unpaid upgrade invoice already exists. Please pay it or contact the platform administrator.`

Optional informational flash after expiry:

- Russian/Kazakh localized equivalent of:
  - `The previous upgrade invoice expired. You can request a new one.`

## Testing

### Billing Service Tests

- duplicate upgrade request is blocked when an unpaid upgrade invoice already exists
- duplicate guard applies to `draft`, `sent`, and `overdue` upgrade invoices
- duplicate guard is scoped to the same target plan
- tenant may request again after prior upgrade invoice becomes `canceled`
- stale unpaid upgrade invoice auto-cancels after 7 days
- expiry uses `due_at` when present
- expiry falls back to `issued_at` when `due_at` is absent
- renewal invoices are unaffected by this new guard

### Tenant Controller Tests

- `/company/billing/upgrade-invoices` shows localized blocking flash when open upgrade invoice exists
- expired upgrade invoice is absent from tenant outstanding/actionable view
- tenant can successfully request a new upgrade invoice after prior one expires
- expiry info flash appears when appropriate

### Admin Tests

- canceled upgrade invoices remain visible in admin billing list/history paths
- auto-expiry writes expected audit metadata

## Open Implementation Choice

The only remaining implementation choice is how to carry the “show tenant one-time expiry flash” signal.

Recommended implementation:

- determine it from a recent billing audit event tied to the company and action reason `expired_unpaid_upgrade`
- mark it as shown through session flash behavior rather than a persistent new database field

This keeps the schema unchanged while still giving the tenant useful feedback at the next billing-page visit.
