# Company Billing Payment Submission Visibility Design

## Summary

Fix the tenant payment-submission flow on `/company/billing` so that:

1. a tenant gets clear visible feedback after submitting payment details for review
2. a platform admin can see tenant-submitted payment confirmations in a dedicated section on `/admin/billing/clients/:id`

The existing billing domain model already supports tenant-submitted payment review records through `Billing.create_customer_payment_review_for_company/3`. This design reuses that path and makes its outcome visible in the tenant UI and the admin client detail UI.

## Current State

### Tenant side

- `/company/billing` renders outstanding billing invoices and a payment-submission form per invoice.
- The form posts to `BillingHTMLController.create_payment/2`.
- `BillingHTMLController.create_payment/2` already redirects back to `/company/billing` and sets localized flash messages for success and failure.
- There is already controller-level test coverage proving the redirect and success flash assignment.

### Admin side

- `/admin/billing/clients/:id` already shows a generic `Payment History` section based on `@client.payments`.
- `Billing.get_admin_client!/1` already loads all billing payments for the company.
- Tenant-submitted payment review records therefore already exist in the admin data set, but they are not surfaced as a dedicated operational section for admin review.

## Problem

The current experience fails in two ways:

1. On `/company/billing`, tenant submission does not produce an unmistakable visible outcome for the user in the actual page UX.
2. On `/admin/billing/clients/:id`, there is no dedicated section that tells the admin "the tenant submitted payment details for review", even though the underlying payment record exists.

The result is a broken business workflow: the tenant cannot tell whether the submission worked, and the admin lacks a clear destination for submitted payment evidence.

## Goals

- Make tenant payment submission visibly successful or visibly failed on `/company/billing`.
- Keep tenant submission distinct from admin confirmation.
- Provide a dedicated admin-side section for submitted payments on `/admin/billing/clients/:id`.
- Reuse the existing billing payment model rather than introducing a new persistence model.

## Non-Goals

- Changing billing settlement rules.
- Auto-confirming payments.
- Introducing email, websocket, or push notifications.
- Replacing the generic payment history; it can remain for broader audit context.

## Recommended Approach

Use existing billing payment records as the source of truth for tenant-submitted payment reviews.

### Why this approach

- The payment submission path already exists.
- Payment records already store the core review data: invoice, amount, method, external reference, proof URL, status.
- Notes for payment review already exist via `payment_review_note` audit events.
- This avoids inventing a parallel "submission notification" model that would duplicate billing state.

## User Flow

### Tenant flow

1. Tenant opens `/company/billing`.
2. Tenant enters payment reference, proof URL, and optional note.
3. Tenant submits the form.
4. Server creates a pending confirmation payment review record.
5. Tenant is redirected back to `/company/billing`.
6. A localized flash is shown with clear wording that the payment details were sent for admin review.

Failure path:

1. Submission fails validation or invoice lookup.
2. Tenant is redirected back to `/company/billing`.
3. A localized error flash is shown with clear wording that the payment details could not be sent.

### Admin flow

1. Admin opens `/admin/billing/clients/:id`.
2. Admin sees a dedicated section for submitted payments.
3. Each submitted payment entry shows the billing invoice, payment method, review evidence, and pending status.
4. Admin can still use existing billing workflows later to confirm or reject the payment.

## UX Design

### Tenant page

On `/company/billing`:

- The submit button wording can remain aligned with current behavior unless product copy is separately changed.
- The success flash must be highly visible after redirect and clearly say the details were sent for review.
- The error flash must also be visible and specific enough to distinguish "invoice not found" from generic submission failure if the current code path already differentiates those cases.

### Admin page

Add a new dedicated section above the generic `Payment History` block:

- Title: submitted payments or equivalent admin-facing wording
- Ordered newest first
- One card or row per submitted payment

Each entry should show:

- billing invoice id
- invoice status
- payment status
- payment method
- amount
- external reference if present
- proof URL if present
- submitted timestamp
- payment review note if present

This section should only show payments that are relevant to tenant-submitted review, not every historical payment row that the system ever created for the company.

## Data and Query Design

### Source of truth

Reuse `billing_payments`.

Tenant-submitted review entries are payment rows created through `Billing.create_customer_payment_review/2` and `Billing.create_customer_payment_review_for_company/3`.

### Admin client payload

Extend `Billing.get_admin_client!/1` to provide a dedicated collection for tenant-submitted payments, separate from the existing broad `payments` collection.

Recommended shape:

- `payments`: unchanged broad history
- `submitted_payments`: filtered admin-facing review queue for this company

### Filtering rule

The dedicated section should include tenant-submitted payment reviews, with newest first.

Recommended filter for initial implementation:

- payment status is `pending_confirmation`
- linked billing invoice belongs to the company
- include review metadata such as note and proof/reference fields

If the current system can create other pending admin-side payments that should not appear in this section, the implementation should further narrow the filter using available signal from payment creation path or attached review note metadata.

## Boundary Between Submission and Confirmation

This distinction must remain explicit:

- tenant submission means: "we paid; please review"
- admin confirmation means: "payment verified; invoice and subscription can be advanced"

The tenant submit action must not mark the billing invoice as paid.
The admin submitted-payments section is a review surface, not a settlement action by itself.

## Error Handling

### Tenant side

- Missing company: redirect to `/company/setup` as today.
- Missing invoice: redirect to `/company/billing` with a localized error flash.
- Validation failure: redirect to `/company/billing` with a localized error flash.

### Admin side

- If no submitted payments exist, show an empty-state message in the dedicated section instead of omitting the section entirely.

## Testing Strategy

### Controller tests

Add or refine tests for:

- tenant payment submission success flash is visible in redirect state
- tenant invoice-not-found flash path
- tenant invalid submission flash path
- admin client detail renders the submitted-payments section when tenant review payments exist
- admin client detail shows the relevant evidence fields
- admin client detail shows an empty-state message when no tenant-submitted payments exist

### Billing context tests

If needed, add a focused billing test proving the company-level admin detail query can separate:

- general payment history
- tenant-submitted payment review entries

## Implementation Notes

- Prefer reusing the existing `Payment History` data load and extending it with a filtered collection rather than building a second independent data-fetch path elsewhere in the controller.
- Reuse existing localized flash infrastructure rather than inventing a custom inline notification system unless the page currently fails to render flashed messages at all.
- If the real issue is that flashes are not displayed in the billing page layout, fix the page rendering path rather than duplicating status text inside the payment form.

## Acceptance Criteria

- After a tenant submits payment details on `/company/billing`, the next page load clearly shows whether the submission succeeded or failed.
- The submitted payment is persisted as a pending confirmation billing payment.
- `/admin/billing/clients/:id` shows a dedicated submitted-payments section for that client.
- That section shows the tenant-provided reference, proof URL, optional note, and submission time when present.
- Admin can distinguish submitted payments from confirmed historical payments.
- No new persistence model is introduced unless implementation proves the existing payment model cannot support the distinction cleanly.
