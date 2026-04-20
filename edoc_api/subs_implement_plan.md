# Billing + Kaspi Link + Admin CRM Implementation Plan

This document is a step-by-step execution plan for implementing billing, Kaspi payment-link renewals, plan upgrades, access restriction on non-payment, and an internal admin CRM/backoffice.

The plan is intentionally written so an autonomous coding agent can mark items as done and move phase by phase.

---

## Execution Rules for the Agent

- Work strictly phase by phase.
- Do not skip dependencies.
- Mark completed checklist items as `[x]`.
- Leave not-yet-completed items as `[ ]`.
- After each phase, run tests and write a short progress summary.
- Prefer small, reviewable commits.
- Do not implement speculative integrations that are not required for the current phase.
- For Kaspi, assume **payment link flow with manual confirmation** unless a verified API/webhook is explicitly available.
- Keep billing enforcement on the backend, not only in the UI.
- Preserve access to existing data for suspended tenants, but block creation of new billable activity.

---

## Product Assumptions

### Plans

- Trial
  - up to 10 documents total or during trial period (confirm existing product rule in code)
  - up to 2 users
- Starter
  - up to 50 documents per month
  - up to 2 users
- Basic
  - up to 500 documents per month
  - up to 5 users

### Billing Behavior

- Payments are initiated through a Kaspi payment link.
- Renewals are handled by creating a billing invoice for each period.
- Access is extended only after payment is confirmed.
- Plan upgrade can be handled initially as:
  - immediate upgrade after successful payment, or
  - scheduled upgrade from next period
- Non-payment leads to restricted usage.

### Initial Enforcement Scope

When subscription is not in good standing, block:
- creation of new documents
- finalization/issuing of documents
- adding new users

Still allow:
- sign in
- viewing existing data
- viewing billing page
- paying outstanding invoice

---

## Suggested Phase Order

1. Domain modeling
2. Database schema + migrations
3. Billing core services
4. Enforcement guards for document/user limits
5. Admin CRM/backoffice
6. Kaspi link workflow
7. Renewal workflow + overdue handling
8. Upgrade workflow
9. Notifications and reminders
10. Reporting, audit, polish

---

# Phase 0 — Discovery and Alignment

## Goal
Define exact business rules before schema and code changes.

## Tasks
- [x] Audit current tenant/company/user model in the codebase.
- [x] Audit current document model(s) and identify which actions count toward usage.
- [x] Decide what counts as a billable document.
- [x] Decide whether trial document limit is lifetime-trial or monthly-trial.
- [x] Decide whether upgrade is immediate or next-cycle for MVP.
- [x] Decide whether downgrade is immediate or next-cycle for MVP.
- [x] Decide grace period length (recommended: 3 days).
- [x] Decide whether suspended tenants can still download old PDFs.
- [x] Document current entry points where documents are created/finalized.
- [x] Document current entry points where tenant users are invited/created.

## Deliverables
- [x] `docs/billing_rules.md`
- [x] list of billable document actions
- [x] list of enforcement points in the application

## Done Criteria
- [x] Business rules are written down.
- [x] Enforcement points are identified.
- [x] No unresolved product ambiguity blocks schema work.

---

# Phase 1 — Billing Domain Design

## Goal
Introduce the billing domain model in code without yet wiring the full UI/workflows.

## Tasks
- [ ] Create a dedicated billing context/module (for example `EdocApi.Billing`).
- [ ] Define domain responsibilities:
  - [ ] plans
  - [ ] subscriptions
  - [ ] billing invoices
  - [ ] payments
  - [ ] usage counters
  - [ ] admin notes / audit events
- [ ] Define canonical subscription statuses.
- [ ] Define canonical billing invoice statuses.
- [ ] Define canonical payment statuses.
- [ ] Define a clear separation between:
  - [ ] subscription state
  - [ ] payment record state
  - [ ] usage tracking state

## Recommended Statuses

### Subscription statuses
- `trialing`
- `active`
- `grace_period`
- `past_due`
- `suspended`
- `canceled`

### Billing invoice statuses
- `draft`
- `sent`
- `paid`
- `overdue`
- `canceled`

### Payment statuses
- `pending_confirmation`
- `confirmed`
- `rejected`

## Deliverables
- [ ] billing domain design notes in `docs/billing_domain.md`
- [ ] enums/status decisions reflected in code constants/types/modules

## Done Criteria
- [ ] Billing domain boundaries are clear.
- [ ] Status model is finalized.
- [ ] Code structure for billing context is ready.

---

# Phase 2 — Database Schema and Migrations

## Goal
Create all core tables required for billing and admin monitoring.

## Tasks

### Plans
- [ ] Create `plans` table with fields such as:
  - [ ] `id`
  - [ ] `code`
  - [ ] `name`
  - [ ] `price_kzt`
  - [ ] `monthly_document_limit`
  - [ ] `included_users`
  - [ ] `is_active`
  - [ ] timestamps
- [ ] Add unique index on `code`.

### Subscriptions
- [ ] Create `subscriptions` table with fields such as:
  - [ ] `id`
  - [ ] `tenant_id` or `company_id`
  - [ ] `plan_id`
  - [ ] `status`
  - [ ] `current_period_start`
  - [ ] `current_period_end`
  - [ ] `grace_until`
  - [ ] `extra_user_seats`
  - [ ] `auto_renew_mode`
  - [ ] `next_plan_id`
  - [ ] `change_effective_at`
  - [ ] `blocked_reason`
  - [ ] timestamps
- [ ] Add indexes for tenant/company + status.
- [ ] Enforce one current active subscription per tenant/company as needed.

### Billing Invoices
- [ ] Create `billing_invoices` table with fields such as:
  - [ ] `id`
  - [ ] `tenant_id`
  - [ ] `subscription_id`
  - [ ] `period_start`
  - [ ] `period_end`
  - [ ] `plan_snapshot_code`
  - [ ] `amount_kzt`
  - [ ] `status`
  - [ ] `payment_method`
  - [ ] `kaspi_payment_link`
  - [ ] `issued_at`
  - [ ] `due_at`
  - [ ] `paid_at`
  - [ ] `activated_by_user_id`
  - [ ] `note`
  - [ ] timestamps
- [ ] Add indexes for tenant/company + status + due date.

### Payments
- [ ] Create `payments` table with fields such as:
  - [ ] `id`
  - [ ] `tenant_id`
  - [ ] `billing_invoice_id`
  - [ ] `amount_kzt`
  - [ ] `method`
  - [ ] `status`
  - [ ] `paid_at`
  - [ ] `confirmed_at`
  - [ ] `confirmed_by_user_id`
  - [ ] `external_reference`
  - [ ] `proof_attachment_url` (or equivalent)
  - [ ] timestamps
- [ ] Add indexes for invoice + status.

### Usage Counters
- [ ] Create `usage_counters` table with fields such as:
  - [ ] `id`
  - [ ] `tenant_id`
  - [ ] `metric`
  - [ ] `period_start`
  - [ ] `period_end`
  - [ ] `value`
  - [ ] timestamps
- [ ] Add unique index on `(tenant_id, metric, period_start, period_end)`.

### Usage Events (recommended)
- [ ] Create `usage_events` table with fields such as:
  - [ ] `id`
  - [ ] `tenant_id`
  - [ ] `metric`
  - [ ] `resource_type`
  - [ ] `resource_id`
  - [ ] `count`
  - [ ] timestamps
- [ ] Add indexes for tenant/company + period.

### Admin Notes / Audit
- [ ] Create `admin_notes` or `billing_audit_events` table.
- [ ] Ensure manual actions are traceable.

## Seed Data
- [ ] Seed `trial`, `starter`, and `basic` plans.

## Deliverables
- [ ] migrations
- [ ] schemas
- [ ] changesets
- [ ] seeds for plans

## Done Criteria
- [ ] All billing tables exist.
- [ ] Constraints and indexes are in place.
- [ ] Plans are seeded in dev/test.

---

# Phase 3 — Core Billing Services

## Goal
Implement the core application services for subscription state, usage accounting, and payment confirmation.

## Tasks

### Plans API
- [ ] Implement plan lookup functions.
- [ ] Implement active plan listing functions.

### Subscription API
- [ ] Implement `get_current_subscription/1`.
- [ ] Implement subscription creation for new tenants.
- [ ] Implement activation logic.
- [ ] Implement suspension logic.
- [ ] Implement grace-period transition logic.
- [ ] Implement renewal extension logic.
- [ ] Implement plan change scheduling logic.

### Usage API
- [ ] Implement `current_document_usage/1`.
- [ ] Implement `allowed_document_limit/1`.
- [ ] Implement `allowed_user_limit/1`.
- [ ] Implement usage counter creation/upsert.
- [ ] Implement usage event recording.

### Billing Invoice API
- [ ] Implement invoice creation for renewals.
- [ ] Implement invoice creation for upgrades.
- [ ] Implement invoice status transitions.
- [ ] Implement overdue marking.

### Payment API
- [ ] Implement manual payment confirmation service.
- [ ] Implement payment rejection service.
- [ ] Implement idempotent protection so the same invoice is not confirmed twice.

## Important Transactional Work
- [ ] Confirm payment in a DB transaction.
- [ ] Update invoice + payment + subscription atomically.
- [ ] Prevent double-activation from repeated admin clicks.

## Deliverables
- [ ] billing context functions
- [ ] tests for service-layer behavior

## Done Criteria
- [ ] New tenant can receive a trial subscription.
- [ ] Payment confirmation extends access correctly.
- [ ] Suspension/reactivation can be executed from code.

---

# Phase 4 — Enforce Limits and Access Restrictions

## Goal
Prevent unpaid or over-limit tenants from continuing billable usage.

## Tasks

### Document Quota Enforcement
- [ ] Implement `can_create_document?/1`.
- [ ] Implement `ensure_can_create_document!/1`.
- [ ] Implement `record_document_usage/3`.
- [ ] Decide whether usage is counted on draft creation, finalization, or issue.
- [ ] Apply enforcement at all document entry points.

### User Seat Enforcement
- [ ] Implement `can_add_user?/1`.
- [ ] Implement `ensure_can_add_user!/1`.
- [ ] Count current active users correctly.
- [ ] Respect `included_users + extra_user_seats`.

### Subscription Standing Enforcement
- [ ] Block creation when subscription status is `grace_period` if product requires strict block.
- [ ] Otherwise allow limited grace behavior only if explicitly desired.
- [ ] Block creation when status is `suspended`.
- [ ] Ensure read-only access still works.

### App Integration
- [ ] Add enforcement errors/messages at domain level.
- [ ] Map domain errors to controller/API responses.
- [ ] Surface clear upgrade/payment prompts in API response payloads where appropriate.

## Deliverables
- [ ] enforcement guards
- [ ] tests proving blocked/unblocked behavior

## Done Criteria
- [ ] Tenant cannot exceed document quota.
- [ ] Tenant cannot exceed user seat quota.
- [ ] Suspended tenant cannot create new billable data.

---

# Phase 5 — Admin CRM / Backoffice Foundation

## Goal
Provide an internal admin interface to monitor clients and manually control billing lifecycle.

## Tasks

### Admin Auth / Authorization
- [ ] Decide where admin panel lives.
- [ ] Restrict admin routes to internal/admin users only.

### Client List View
- [ ] Build list page for tenants/clients with columns such as:
  - [ ] company name
  - [ ] current plan
  - [ ] subscription status
  - [ ] active users / limit
  - [ ] documents used / limit
  - [ ] current period end
  - [ ] overdue state

### Client Detail View
- [ ] Build client detail page with sections:
  - [ ] company info
  - [ ] subscription info
  - [ ] usage summary
  - [ ] user list
  - [ ] invoice history
  - [ ] payment history
  - [ ] internal notes

### Billing Invoice List View
- [ ] Build invoice list with filters:
  - [ ] draft
  - [ ] sent
  - [ ] paid
  - [ ] overdue
- [ ] Show Kaspi link availability and invoice due date.

### Admin Actions
- [ ] Add action: create renewal invoice.
- [ ] Add action: edit/add Kaspi payment link.
- [ ] Add action: mark invoice as sent.
- [ ] Add action: confirm payment.
- [ ] Add action: reject payment.
- [ ] Add action: activate/reactivate tenant.
- [ ] Add action: suspend tenant.
- [ ] Add action: extend grace period.
- [ ] Add action: schedule upgrade.
- [ ] Add action: add extra seats.
- [ ] Add action: add internal note.

## Deliverables
- [ ] admin billing dashboard
- [ ] client detail view
- [ ] invoice/payment views

## Done Criteria
- [ ] Admin can find any client quickly.
- [ ] Admin can confirm payment from UI.
- [ ] Admin can see which clients are overdue.

---

# Phase 6 — Kaspi Link Payment Workflow

## Goal
Implement the operational workflow for Kaspi payment links.

## Tasks

### Billing Invoice + Link Flow
- [ ] Allow admin to attach Kaspi payment link to a billing invoice.
- [ ] Store payment link safely.
- [ ] Add validation that payment method is `kaspi_link` when link is present.
- [ ] Allow copying/opening the link from admin UI.

### Customer-Facing Billing Page
- [ ] Build tenant billing page showing:
  - [ ] current plan
  - [ ] renewal date
  - [ ] outstanding invoices
  - [ ] Kaspi payment link
  - [ ] payment instructions
- [ ] Show blocked/overdue banners where relevant.

### Payment Confirmation Workflow
- [ ] Define internal steps for manual reconciliation.
- [ ] Add optional fields for proof/reference from customer.
- [ ] Add internal comment/note for payment review.

## Deliverables
- [ ] tenant billing page
- [ ] admin Kaspi-link handling flow

## Done Criteria
- [ ] Customer can see outstanding invoice and payment link.
- [ ] Admin can confirm payment after receiving it.

---

# Phase 7 — Renewal Cycle and Overdue Automation

## Goal
Automate invoice generation and subscription state transitions around renewals.

## Tasks

### Renewal Invoice Generation
- [ ] Create scheduled job to generate renewal invoices before period end.
- [ ] Recommended lead time: 5 to 7 days before `current_period_end`.
- [ ] Avoid duplicate invoice generation for the same period.

### Overdue State Transitions
- [ ] Mark invoice overdue when `due_at` passes.
- [ ] Transition subscription to `past_due` or `grace_period` based on product rule.
- [ ] Transition to `suspended` after grace period expires.

### Recovery Flow
- [ ] When overdue invoice is confirmed as paid, restore subscription to `active`.
- [ ] Extend `current_period_end` correctly.
- [ ] Clear blocked reason where relevant.

### Scheduled Jobs
- [ ] Add recurring jobs (Oban or equivalent) for:
  - [ ] invoice generation
  - [ ] overdue marking
  - [ ] grace expiry processing

## Deliverables
- [ ] automated renewal jobs
- [ ] state transition tests

## Done Criteria
- [ ] Renewals are generated automatically.
- [ ] Unpaid tenants move through overdue lifecycle correctly.
- [ ] Paid overdue tenants can be reactivated safely.

---

# Phase 8 — Upgrade and Seat Expansion Workflow

## Goal
Support plan upgrades and additional user seats.

## Tasks

### Upgrade Flow
- [ ] Add customer/admin action to request upgrade.
- [ ] Decide MVP behavior:
  - [ ] immediate upgrade after payment, or
  - [ ] upgrade next cycle
- [ ] Create upgrade billing invoice.
- [ ] On payment confirmation, apply upgrade logic.

### Downgrade Flow
- [ ] Support scheduled downgrade for next billing cycle.
- [ ] Prevent immediate downgrade if it would violate current active user count or current usage assumptions.

### Extra Seats
- [ ] Support `extra_user_seats` on subscription.
- [ ] Add admin action to increase/decrease seats.
- [ ] Reflect seats in `allowed_user_limit/1`.

### Optional Proration
- [ ] If implementing immediate mid-cycle upgrade, decide proration rules.
- [ ] Add tests for proration if included.

## Deliverables
- [ ] upgrade workflow
- [ ] seat add-on workflow

## Done Criteria
- [ ] Tenant can move to a higher plan via invoice/payment flow.
- [ ] Additional seats affect user limit correctly.

---

# Phase 9 — Notifications and Reminders

## Goal
Reduce missed payments through timely reminders.

## Tasks
- [ ] Add reminder notification 7 days before renewal.
- [ ] Add reminder notification 3 days before renewal.
- [ ] Add day-of-due reminder.
- [ ] Add overdue reminder after due date.
- [ ] Add suspended notice after account suspension.
- [ ] Add internal admin alert for overdue high-value clients.

## Delivery Channels
- [ ] email
- [ ] in-app banner
- [ ] optional WhatsApp/manual follow-up placeholder

## Deliverables
- [ ] reminder jobs
- [ ] notification templates

## Done Criteria
- [ ] Reminder cadence works end to end.
- [ ] Overdue clients receive clear payment instructions.

---

# Phase 10 — Audit, Reporting, and Hardening

## Goal
Make the system operationally safe and visible.

## Tasks

### Auditability
- [ ] Log all admin billing actions.
- [ ] Log subscription status changes.
- [ ] Log payment confirmation actions with actor and timestamp.

### Reporting
- [ ] Add admin dashboard cards for:
  - [ ] active clients
  - [ ] trial clients
  - [ ] overdue clients
  - [ ] suspended clients
  - [ ] monthly collected revenue
  - [ ] upcoming renewals
- [ ] Add lists for:
  - [ ] invoices due soon
  - [ ] unpaid invoices
  - [ ] recently reactivated clients

### Safety and Correctness
- [ ] Add concurrency tests around payment confirmation.
- [ ] Add concurrency tests around document usage counting.
- [ ] Ensure double-submit does not double-charge or double-extend.
- [ ] Ensure suspension rules are consistently enforced across all entry points.

### Documentation
- [ ] Write internal admin operating guide.
- [ ] Write customer-facing billing behavior notes.

## Deliverables
- [ ] reporting widgets or pages
- [ ] audit logs
- [ ] internal runbook

## Done Criteria
- [ ] Billing actions are traceable.
- [ ] Operational dashboard is usable.
- [ ] Core race conditions are covered by tests.

---

# Recommended Initial Technical Decisions

## Billing Period
- Monthly only for MVP.

## Renewal Model
- Manual payment via Kaspi link.
- Subscription extension only after payment confirmation.

## Upgrade Model
- Immediate after payment for upgrade.
- Downgrade next cycle.

## Access Restriction Model
- Trial exhausted -> block new billable actions.
- Paid plan unpaid after due date -> grace period -> suspended.

## Enforcement Point
- Enforce in domain/services, not only in controllers or UI.

## Admin CRM Scope
- Keep lightweight.
- Focus on billing operations first, not full sales CRM.

---

# Suggested File/Module Map

Adjust names to actual project conventions.

- `lib/edoc_api/billing.ex`
- `lib/edoc_api/billing/plan.ex`
- `lib/edoc_api/billing/subscription.ex`
- `lib/edoc_api/billing/billing_invoice.ex`
- `lib/edoc_api/billing/payment.ex`
- `lib/edoc_api/billing/usage_counter.ex`
- `lib/edoc_api/billing/usage_event.ex`
- `lib/edoc_api/billing/admin_note.ex`
- `lib/edoc_api/billing/enforcement.ex`
- `lib/edoc_api/workers/billing_renewal_worker.ex`
- `lib/edoc_api/workers/billing_overdue_worker.ex`
- `lib/edoc_api/workers/billing_reminder_worker.ex`

Admin/UI naming can vary depending on current Phoenix structure.

---

# Testing Strategy Checklist

## Unit Tests
- [ ] plan lookup
- [ ] subscription status transitions
- [ ] usage limit calculations
- [ ] extra seat calculations
- [ ] invoice state transitions
- [ ] payment confirmation idempotency

## Integration Tests
- [ ] new tenant gets trial subscription
- [ ] exhausted trial blocks new document creation
- [ ] paid invoice activates subscription
- [ ] overdue invoice leads to restricted access
- [ ] confirmed overdue payment reactivates tenant
- [ ] upgrade invoice changes plan correctly

## UI/Admin Tests
- [ ] admin can confirm payment
- [ ] admin can suspend/reactivate tenant
- [ ] tenant can view payment link
- [ ] overdue banner is visible when expected

---

# MVP Cut Line

If implementation needs to be reduced, keep these items in MVP:

- [ ] plans
- [ ] subscriptions
- [ ] billing invoices
- [ ] payments
- [ ] usage counters
- [ ] document enforcement
- [ ] user-seat enforcement
- [ ] manual payment confirmation by admin
- [ ] admin client list
- [ ] admin client detail
- [ ] tenant billing page with Kaspi link
- [ ] renewal invoice generation job
- [ ] overdue -> suspended flow

Can be delayed until later:
- [ ] proration
- [ ] advanced reporting
- [ ] external reconciliation automation
- [ ] richer CRM features
- [ ] complex discounting/promotions

---

# Final Agent Workflow

Use this sequence during implementation:

- [ ] Complete Phase 0 and commit.
- [ ] Complete Phase 1 and commit.
- [ ] Complete Phase 2 and run migrations/tests.
- [ ] Complete Phase 3 and run service tests.
- [ ] Complete Phase 4 and verify blocked/unblocked flows.
- [ ] Complete Phase 5 and verify admin flows manually.
- [ ] Complete Phase 6 and verify tenant billing page manually.
- [ ] Complete Phase 7 and verify scheduled renewal lifecycle.
- [ ] Complete Phase 8 and verify upgrade/seat flow.
- [ ] Complete Phase 9 and verify reminders.
- [ ] Complete Phase 10 and finalize documentation.

At the end of each phase:
- [ ] update this file by marking completed items `[x]`
- [ ] add a brief summary under the phase
- [ ] record open risks/blockers

---

# Notes for Codex

- Prefer the smallest end-to-end slice that delivers value.
- Keep migrations reversible.
- Avoid mixing billing logic into unrelated contexts.
- Reuse existing tenant/company/user structures where possible.
- Do not assume Kaspi recurring API exists unless verified.
- Build for manual ops first; automate later.
