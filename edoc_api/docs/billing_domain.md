# Billing Domain Design

Phase 1 introduces the billing domain boundary and canonical state language. It does not add database tables, migrations, Kaspi integration, admin screens, or runtime enforcement changes.

## Context Boundary

The billing context is `EdocApi.Billing`.

Its responsibilities are:

- Plans.
- Subscriptions.
- Billing invoices.
- Payments.
- Usage counters.
- Billing audit events.

The tenant boundary is `company_id`. Billing records should attach to the company/tenant, not to an individual user.

## Separation of State

Billing state must be split across separate concepts.

Subscription state:

- Describes whether the tenant currently has access.
- Drives backend enforcement for creating documents, issuing documents, and inviting users.
- Must not be used to represent whether a specific payment has been manually confirmed.

Billing invoice state:

- Describes the payment request for a subscription period.
- Carries amount, period, due date, Kaspi payment link, and payment status from the tenant-facing billing perspective.
- Must not be used as the canonical subscription access state.

Payment state:

- Describes an individual payment attempt or manual confirmation.
- For Kaspi payment-link MVP, this is manual confirmation by an admin/backoffice user.
- Must not directly grant access without subscription update logic.

Usage tracking state:

- Immutable usage events record billable document events.
- Usage counters can be derived or cached for faster limit checks.
- Usage tracking must remain independent from payment state.

## Canonical Subscription Statuses

Defined in `EdocApi.Billing.SubscriptionStatus`.

- `trialing`: tenant is in trial and within trial limits.
- `active`: paid subscription is active.
- `grace_period`: payment is overdue but tenant is still temporarily allowed to continue.
- `past_due`: grace period expired or payment is overdue enough to block new billable activity.
- `suspended`: tenant access to new billable activity is blocked.
- `canceled`: subscription was explicitly ended.

Good-standing subscription states:

- `trialing`
- `active`
- `grace_period`

Restricted subscription states:

- `past_due`
- `suspended`
- `canceled`

## Canonical Billing Invoice Statuses

Defined in `EdocApi.Billing.BillingInvoiceStatus`.

- `draft`: invoice exists but has not been sent to tenant.
- `sent`: invoice was issued/sent and can be paid.
- `paid`: invoice was paid and applied.
- `overdue`: invoice due date passed.
- `canceled`: invoice is no longer payable.

Payable billing invoice states:

- `sent`
- `overdue`

## Canonical Payment Statuses

Defined in `EdocApi.Billing.PaymentStatus`.

- `pending_confirmation`: tenant initiated payment or submitted proof, but admin has not confirmed it.
- `confirmed`: admin confirmed the payment.
- `rejected`: admin rejected the payment.

Final payment states:

- `confirmed`
- `rejected`

## MVP Billing Flow

1. A billing invoice is created for the subscription period.
2. Tenant opens the Kaspi payment link from the billing page.
3. Tenant pays through Kaspi outside the app.
4. Admin confirms the payment manually in the future backoffice.
5. Payment becomes `confirmed`.
6. Billing invoice becomes `paid`.
7. Subscription becomes or remains `active`, and its period is extended or upgraded.

## Non-Goals for Phase 1

- No schema changes.
- No payment-link generation.
- No admin CRM UI.
- No renewal jobs.
- No access-enforcement behavior changes.
- No migration from current `EdocApi.Monetization` tables.

## Compatibility with Existing Monetization

The current `EdocApi.Monetization` module remains responsible for active runtime enforcement until later phases replace or wrap it.

Current records:

- `tenant_subscriptions`
- `tenant_memberships`
- `tenant_usage_events`

Future billing records should use the same tenant boundary: `company_id`.

The new status modules intentionally include statuses that do not yet exist in `tenant_subscriptions`. Later phases should migrate or map existing statuses into the canonical billing model.
