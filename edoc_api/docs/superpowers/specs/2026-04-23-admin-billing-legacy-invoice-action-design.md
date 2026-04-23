# Admin Billing Legacy Invoice Action Design

## Problem

`/admin/billing/invoices` shows pending billing rows for legacy tenant subscriptions that do not yet have a current billing subscription or billing invoice. The Actions column tells the platform admin to create the billing invoice from the client detail page.

That flow is currently broken because `/admin/billing/clients/:id` only shows renewal and upgrade invoice actions when a current billing subscription exists. Legacy pending clients have no visible action to create the invoice.

## Goal

Make the pending invoice flow actionable and explicit:

- A platform admin can open the client detail page for a pending legacy billing client.
- The page shows a clear action to create the missing billing invoice.
- Submitting the action creates the invoice using the tenant's legacy active plan and billing period.
- After creation, the admin lands on `/admin/billing/invoices`, where the invoice can be managed like normal billing invoices.

## Scope

In scope:

- Detect legacy active Starter/Basic tenant subscriptions without a current billing subscription.
- Expose this state in the admin client detail data.
- Render a "Create billing invoice" action on `/admin/billing/clients/:id` for that state.
- Add a controller endpoint that creates the missing billing invoice.
- Add regression tests for both the visible action and invoice creation path.

Out of scope:

- Tenant-facing billing UI changes.
- Online payment provider integration.
- Bulk invoice generation.
- Changing existing renewal and upgrade invoice flows for clients that already have current billing subscriptions.

## Recommended Flow

1. The admin visits `/admin/billing/invoices`.
2. A legacy pending row appears when a legacy active `TenantSubscription` exists without a current billing `Subscription`.
3. The pending row directs the admin to `/admin/billing/clients/:company_id`.
4. The client detail page shows a legacy billing action card.
5. The admin clicks "Create billing invoice".
6. The backend creates the current billing record if required and creates a draft billing invoice from the legacy plan/period.
7. The admin is redirected to `/admin/billing/invoices`.

## Data And Backend Design

Add a billing context function that receives a company or subscription identifier and creates a pending legacy billing invoice. The function should:

- Find the latest active legacy `TenantSubscription` for the company.
- Validate that the legacy plan is billable (`starter` or `basic`).
- Avoid duplicate invoices if a current billing invoice already exists for the same company and billing period.
- Create or reuse the current billing `Subscription` record needed by the normal billing invoice model.
- Create a billing invoice with plan snapshot, amount, due date, and billing period from the legacy subscription.

The controller should expose a platform-admin-only POST route, for example:

`POST /admin/billing/clients/:id/legacy-invoices`

On success, redirect to `/admin/billing/invoices`. On failure, redirect back to the client page with a clear flash error.

## UI Design

On `/admin/billing/clients/:id`, keep the existing Admin Actions section for normal subscriptions.

For legacy pending clients, show a separate action card:

- Heading: `Pending billing invoice`
- Description: explains that the client has an active legacy plan but no created billing invoice yet.
- Button: `Create billing invoice`

The card should use the same admin billing visual style as the existing action cards and support dark mode.

On `/admin/billing/invoices`, keep the pending row but make the Actions content more useful by linking to the specific client detail page instead of showing only static text.

## Error Handling

Expected failure cases:

- No active legacy subscription exists for the company.
- The legacy plan is not billable.
- A billing invoice already exists and should not be duplicated.
- Database validation fails.

Errors should not crash the page. They should redirect back with a concise flash message.

## Testing

Add controller tests that prove:

- A legacy pending client detail page shows the "Create billing invoice" action.
- Posting the action creates a billing invoice and redirects to `/admin/billing/invoices`.
- After creation, the pending virtual row is no longer shown for that company.
- The invoice list pending row links to the relevant client detail page.

Existing admin billing tests should continue passing.
