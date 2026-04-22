# Manual Testing of Billing (`localhost:4000`)

This checklist verifies Phases 0–10 behavior in the UI and with light DB/job support.

## 0. Preconditions

- Run server: `mix phx.server`
- Use dev DB with seeded plans (`trial`, `starter`, `basic`).
- Have two users:
  - Tenant owner (regular app user).
  - Platform admin (`users.is_platform_admin = true`).
- Confirm admin routes:
  - `/admin/billing` (redirects to clients)
  - `/admin/billing/clients`
  - `/admin/billing/invoices`

## 1. Tenant Billing Page (Phase 6 baseline)

Login as tenant owner and open `/company/billing`.

Verify:
- Current plan is shown.
- Renewal date / current period shown.
- Outstanding billing invoices list is visible.
- Kaspi payment link is visible on sent invoices (if present).
- Payment instruction text is visible.

Expected:
- Page loads without errors.
- Invoice statuses and amounts are readable and consistent.

## 2. Admin Backoffice Access (Phase 5)

### 2.1 Route + auth
- As non-platform user, open `/admin/billing/clients`.
  - Expected: `403 Forbidden`.
- As platform admin, open `/admin/billing`.
  - Expected: redirect to `/admin/billing/clients`.

### 2.2 Clients page
Open `/admin/billing/clients` and verify:
- Client rows include company, plan, subscription status.
- Active users / seat limit shown.
- Document usage / document limit shown.
- Current period end shown.
- Overdue indicator shown when applicable.

### 2.3 Invoices page
Open `/admin/billing/invoices` and verify:
- Filter by status works (`draft`, `sent`, `paid`, `overdue`).
- Due date shown.
- Kaspi link open/copy actions visible when link exists.

## 3. Quota Enforcement (Phase 4)

As tenant owner:
- Create/issue documents repeatedly until reaching plan limit.

Verify:
- At limit, new billable creation/issue is blocked.
- User sees upgrade/payment guidance message.
- Existing documents remain viewable.

Expected:
- No server errors.
- Block applies consistently for invoices/contracts/acts entry points.

## 4. Seat Enforcement (Phase 4 + 8)

As owner/admin on `/company` team management:
- Invite members up to seat limit.
- Try inviting one more member.

Verify:
- Invite above limit is blocked.

Expected:
- Effective limit comes only from the current plan:
- Trial: 2 seats.
- Starter: 2 seats.
- Basic: 5 seats.

## 5. Upgrade Workflow (Phase 8)

As tenant owner:
- Request upgrade from `/company/billing` (e.g., Starter -> Basic).

As platform admin:
- Open `/admin/billing/invoices`.
- Ensure upgrade invoice exists.
- Send invoice with Kaspi link.
- Create payment and confirm payment.

Verify as tenant:
- Plan changes to upgraded plan after payment confirmation.
- Seat/document limits reflect upgraded plan.

Expected:
- Upgrade is immediate after confirmed payment (current MVP policy).

## 6. Overdue + Grace + Suspension Lifecycle (Phase 7)

Setup:
- Ensure there is an unpaid `sent` billing invoice with `due_at` in the past.

Run billing lifecycle jobs (or wait for schedule):
- Renewal generation worker.
- Overdue marking worker.
- Grace expiry worker.

Verify:
- Invoice moves to `overdue`.
- Subscription transitions through overdue/grace states.
- After grace expiry, subscription becomes `suspended`.
- Suspended tenant cannot create new billable data.
- Suspended tenant can still sign in and view existing data.

## 7. Recovery from Overdue (Phase 7)

As platform admin:
- Confirm payment for overdue invoice.

Verify:
- Payment becomes `confirmed`.
- Billing invoice becomes `paid`.
- Subscription returns to `active`.
- Blocked/grace markers are cleared.
- Tenant can create billable data again.

## 8. Notifications and Reminders (Phase 9)

Run reminder process (job/worker path).

Verify:
- Reminder cadence fires for:
  - 7 days before renewal
  - 3 days before renewal
  - due day
  - overdue
  - suspended
- In-app overdue/suspended banner appears on tenant billing view.
- Emails are generated/sent via configured dev mail flow.

Expected:
- Reminders are idempotent (no duplicate spam for same event window).

## 9. Audit + Reporting + Hardening (Phase 10)

### 9.1 Audit events
Perform admin actions:
- Send invoice
- Create payment
- Confirm payment
- Reject payment
- Suspend/reactivate
- Extend grace
- Schedule plan change

Verify:
- Each action produces `billing_audit_events` record with:
  - actor
  - action
  - subject type/id
  - timestamp

### 9.2 Dashboard reporting
Open `/admin/billing/clients`.

Verify dashboard cards:
- Active clients
- Trial clients
- Overdue clients
- Suspended clients
- Monthly collected revenue
- Upcoming renewals

Verify lists:
- Invoices due soon
- Unpaid invoices
- Recently reactivated clients

### 9.3 Concurrency/idempotency smoke checks
- Rapidly click confirm payment twice.
  - Expected: no double-extend/double-charge effect.
- Simulate near-limit document creation race (two tabs/users at same time).
  - Expected: usage does not exceed limit due to race.

## 10. Quick SQL helpers (optional)

Set platform admin:

```sql
UPDATE users
SET is_platform_admin = true
WHERE email = 'admin@example.com';
```

Check latest billing audit events:

```sql
SELECT inserted_at, action, actor_user_id, subject_type, subject_id, metadata
FROM billing_audit_events
ORDER BY inserted_at DESC
LIMIT 50;
```

Check subscription standing:

```sql
SELECT company_id, status, current_period_start, current_period_end, grace_until, blocked_reason
FROM subscriptions
ORDER BY updated_at DESC;
```

Check outstanding billing invoices:

```sql
SELECT id, company_id, status, amount_kzt, due_at, paid_at
FROM billing_invoices
WHERE status IN ('sent', 'overdue')
ORDER BY due_at NULLS LAST;
```
