# Company Subscription Pane Current vs Scheduled State Design

## Summary

The `/company` page currently mixes active-subscription state with scheduled-downgrade state. When a tenant schedules `Basic -> Starter` for the next billing cycle, `/company/billing` and `/admin/billing/clients/:id` correctly continue to show the current `Basic` plan until the effective date, but the `/company` Subscription pane starts showing `Starter` limits early. This makes the tenant-facing account summary inconsistent and incorrect.

## Goal

Make the `/company` Subscription pane show only the active current plan until the scheduled downgrade takes effect, and show the future `Starter` change separately as scheduled state.

## Business Rule

For a scheduled downgrade:

- The active plan remains `Basic` until `change_effective_at`.
- The current plan name, document limit, and seat limit must remain `Basic` values until that moment.
- The future `Starter` plan must be presented only as an upcoming change, not as current state.

This matches the existing business behavior already shown on:

- `/company/billing`
- `/admin/billing/clients/:id`

## Recommended Approach

Use the billing snapshot as the single display source of truth for both:

- current effective subscription state
- scheduled future plan-change state

The `/company` template should stop inferring active plan limits from mixed legacy subscription fields and instead render explicit snapshot values.

## Data Contract Change

`Billing.tenant_billing_snapshot/1` should expose two separate buckets of information:

### Current state

- current plan code
- current plan label
- current document limit
- current seat limit
- current used documents
- current used seats

### Scheduled state

- next plan code, if any
- next plan label, if any
- effective date, if any

The snapshot should treat `next_plan_id` and `change_effective_at` as future-only metadata. They must not mutate current plan display values before the effective date.

## UI Behavior

On `/company`:

- The `Subscription` badge near `Subscription details` must continue to show `Basic` while downgrade is only scheduled.
- The `Documents Used` denominator must stay `500`, not `50`, until the effective date.
- The `Users` denominator must stay `5`, not `2`, until the effective date.
- If a downgrade is scheduled, show a separate passive notice in the pane, for example:
  - scheduled change: `Starter`
  - effective from: `<change_effective_at>`

The scheduled-change notice should inform the tenant that the lower plan begins next billing cycle, without changing the current-state numbers.

## Scope

In scope:

- billing snapshot state separation
- `/company` subscription-pane rendering
- regression tests for scheduled downgrade display

Out of scope:

- changes to `/company/billing`
- changes to `/admin/billing/clients/:id`
- billing lifecycle behavior
- plan-change business rules

## Testing

Add a regression test proving that with an active `Basic` subscription and a scheduled `Starter` downgrade:

- `/company` still shows `Basic`
- `/company` still shows `500` current document limit
- `/company` still shows `5` current seat limit
- `/company` separately shows the scheduled `Starter` change and effective date

The test should fail against current behavior and pass only after the snapshot/template fix.
