# Company Billing Plan Management Design

## Problem

The tenant-facing subscription UX is split across two conflicting surfaces:

- `/company` still exposes a direct tariff mutation form through `POST /company/subscription`
- `/company/billing` already models upgrades through billing invoices, payment proof, and admin confirmation

That split is no longer coherent after the billing refactor. A tenant can still bypass the billing flow from `/company`, even though plan changes are now supposed to run through billing subscriptions, billing invoices, and payment records.

## Goals

- Make `/company/billing` the only tenant-facing page for plan changes.
- Remove the tariff dropdown and direct subscription mutation flow from `/company`.
- Keep upgrades to `Basic` invoice-driven and admin-confirmed.
- Make downgrades to `Starter` tenant-initiated, validated automatically, and scheduled for the next billing cycle.
- Show clear tenant messaging that a scheduled downgrade starts on the next billing cycle.
- Expose scheduled downgrade state to the platform admin in `/admin/billing/clients/:id`.

## Non-Goals

- Changing the payment-confirmation flow for upgrades.
- Introducing admin approval for tenant downgrades.
- Reworking billing invoice status semantics.
- Adding proration or partial-period billing adjustments.
- Changing document-usage enforcement for the current billing cycle.

## Current State

### `/company`

The subscription pane currently shows:

- current plan badge
- usage and seat summary
- billing link
- a tariff dropdown form posting to `/company/subscription`

That form still calls the legacy monetization path:

- `EdocApiWeb.CompaniesController.update_subscription/2`
- `EdocApi.Monetization.validate_plan_change/2`
- `EdocApi.Monetization.activate_subscription_for_company/2`

This means tenant plan changes can still happen outside the billing context.

### `/company/billing`

The billing page already has the newer billing flow:

- outstanding billing invoices
- tenant payment-proof submission
- Starter-to-Basic upgrade invoice request

That page is the correct boundary for plan changes because it already talks to the billing context.

## Product Decision

### Canonical Tenant Flow

`/company/billing` becomes the only tenant-facing place where plan changes are initiated.

`/company` becomes read-only for subscription state.

### Upgrade Rule

Upgrade from `Starter` to `Basic` remains invoice-driven:

1. Tenant requests an upgrade invoice on `/company/billing`
2. Admin sees the request for that tenant
3. Admin issues billing invoice
4. Tenant pays and submits payment proof/reference
5. Admin confirms payment
6. `Basic` activates immediately for the current billing cycle

### Downgrade Rule

Downgrade from `Basic` to `Starter` is self-service but scheduled:

1. Tenant requests downgrade on `/company/billing`
2. System validates eligibility immediately
3. If valid, the current subscription stores a scheduled plan change to `Starter`
4. Downgrade applies automatically at the next billing cycle boundary

No admin approval is required for downgrade.

## Validation Rules

### Downgrade Eligibility

Downgrade to `Starter` checks occupied seats only.

Occupied seats include:

- active memberships
- invited memberships
- pending-seat memberships

Current-period document usage does not block a scheduled downgrade. The new lower document limit starts with the next billing cycle, so the previous cycle's usage should not prevent the tenant from scheduling a future downgrade.

### Upgrade Eligibility

Upgrade request behavior remains as currently implemented in billing:

- tenant can request a `Basic` upgrade invoice from `/company/billing`
- billing creates a request/invoice artifact visible to the admin

## UX Changes

### `/company`

Remove the subscription mutation controls entirely:

- remove tariff dropdown
- remove update-subscription submit button
- remove downgrade-warning UI tied only to that form

Keep:

- current plan badge
- document usage
- user seats
- billing period
- billing alert banner
- `Subscription details` link to `/company/billing`

### `/company/billing`

#### Starter tenant

Show the existing upgrade card for `Basic`.

After requesting an upgrade invoice:

- redirect back to `/company/billing`
- show localized success flash saying the request was sent for processing

#### Basic tenant

Show a downgrade card for `Starter`.

The card copy must explicitly state that `Starter` begins from the next billing cycle.

After a successful downgrade request:

- redirect back to `/company/billing`
- show localized success flash saying the downgrade is scheduled
- include the effective timing in the flash or adjacent status block

If a downgrade is already scheduled:

- replace the request form with a passive scheduled-status card
- show target plan and effective date

If downgrade is blocked by seats:

- keep user on `/company/billing`
- show localized error explaining too many occupied seats exist for `Starter`

### `/admin/billing/clients/:id`

Show scheduled downgrade state in the client billing detail when present:

- current plan
- next scheduled plan
- effective date

This is visibility only. Admin does not need to approve the downgrade.

## Architecture

### Remove Tenant Mutation Path from Companies Controller

The tenant-owned route `/company/subscription` should no longer serve as the canonical plan change path.

Design intent:

- remove the form from `/company`
- stop relying on `CompaniesController.update_subscription/2` for tenant plan changes

Implementation may either:

- remove the route entirely, or
- leave the route in place but redirect with an informational flash to `/company/billing`

The user-facing result must be the same: no tenant plan mutation happens from `/company`.

### Billing Context Owns Tenant Plan Changes

The billing context should own both tenant-facing plan change actions:

- upgrade invoice request
- scheduled downgrade request

Downgrade scheduling should reuse the current billing subscription model:

- `next_plan_id`
- `change_effective_at`

No new billing table is required for this feature.

## Data Flow

### Upgrade

Tenant:
- submits upgrade request on `/company/billing`

Billing:
- creates upgrade invoice/request artifact

Admin:
- sees request
- sends invoice
- confirms payment later

Subscription:
- current plan changes to `Basic` at payment confirmation

### Downgrade

Tenant:
- submits downgrade request on `/company/billing`

Billing:
- validates occupied seats against `Starter`
- stores scheduled plan change on current subscription

Admin:
- sees scheduled downgrade on client detail

Lifecycle:
- next cycle transition applies `Starter`

## Error Handling

### Downgrade blocked by seats

Return localized flash on `/company/billing`:

- Russian/Kazakh equivalent of:
  - `Remove extra team members before switching to Starter.`

This message should be billing-page-specific and should not rely on the removed `/company` dropdown flow.

### Missing subscription

If tenant reaches `/company/billing` without a current billing subscription but has a legacy subscription snapshot, the page should keep current fallback behavior and must not crash.

### Duplicate scheduled downgrade

If `Starter` is already scheduled:

- do not create another change
- return idempotent success or a neutral informational flash

## Testing

Add failing tests first for:

1. `/company` no longer renders the tariff dropdown form or `/company/subscription` action.
2. `/company/billing` renders a downgrade card for active `Basic` tenants.
3. Posting the downgrade action schedules `Starter` for the next billing cycle.
4. Downgrade success flash is localized and explicitly says the change starts next billing cycle.
5. Downgrade is blocked when occupied seats exceed `Starter` seat limit.
6. `/admin/billing/clients/:id` shows scheduled downgrade state.

Regression expectations:

- Starter upgrade flow still works.
- Existing payment-proof submission flow still works.
- Admin upgrade/payment confirmation flow remains unchanged.

## Acceptance Criteria

1. `/company` no longer contains a tenant plan-change dropdown or submit button.
2. `/company/billing` is the sole tenant-facing subscription-change surface.
3. Upgrades to `Basic` remain invoice-driven and admin-confirmed.
4. Downgrades to `Starter` are self-service, seat-validated, and scheduled for the next billing cycle.
5. Tenant sees explicit localized messaging that `Starter` begins next billing cycle.
6. Admin can see scheduled downgrade state on the tenant billing detail page.
