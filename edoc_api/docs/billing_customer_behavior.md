# Customer-Facing Billing Behavior

This note defines how billing behaves for tenants.

## Subscription States

- `trialing`: normal access while in trial limits.
- `active`: paid access is valid.
- `grace_period`: invoice overdue, temporary access still allowed.
- `past_due` / `suspended`: creation of new billable documents is blocked.
- `canceled`: billing access ended.

## Invoice and Payment Lifecycle

Billing invoice statuses:
- `draft` -> `sent` -> `paid`
- `sent` can become `overdue`

Payment statuses:
- `pending_confirmation` -> `confirmed` or `rejected`

When payment is confirmed:
- Billing invoice becomes `paid`.
- Subscription period and plan are aligned to the paid invoice.

## Reminder Cadence

The system sends reminders by email:
- 7 days before renewal
- 3 days before renewal
- on due date
- after invoice becomes overdue
- after subscription suspension

In-app billing reminders are shown on `/company/billing` for overdue and suspended states.

## Access Restrictions

When subscription is not in good standing:
- Cannot create new billable documents.
- Cannot issue billable documents.
- Seat additions are blocked when limits are reached.

Still allowed:
- Sign in
- View existing documents
- Open billing pages
- Submit payment references/proof

## Upgrade/Downgrade

Upgrade:
- Invoice can be issued and, after payment confirmation, applies immediately for current cycle.

Downgrade:
- Scheduled for next cycle.
- Blocked if current occupied seats or current usage exceed target plan limits.
