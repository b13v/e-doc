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
- [x] Create a dedicated billing context/module (for example `EdocApi.Billing`).
- [x] Define domain responsibilities:
  - [x] plans
  - [x] subscriptions
  - [x] billing invoices
  - [x] payments
  - [x] usage counters
  - [x] admin notes / audit events
- [x] Define canonical subscription statuses.
- [x] Define canonical billing invoice statuses.
- [x] Define canonical payment statuses.
- [x] Define a clear separation between:
  - [x] subscription state
  - [x] payment record state
  - [x] usage tracking state

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
- [x] billing domain design notes in `docs/billing_domain.md`
- [x] enums/status decisions reflected in code constants/types/modules

## Done Criteria
- [x] Billing domain boundaries are clear.
- [x] Status model is finalized.
- [x] Code structure for billing context is ready.

---

# Phase 2 — Database Schema and Migrations

## Goal
Create all core tables required for billing and admin monitoring.

## Tasks

### Plans
- [x] Create `plans` table with fields such as:
  - [x] `id`
  - [x] `code`
  - [x] `name`
  - [x] `price_kzt`
  - [x] `monthly_document_limit`
  - [x] `included_users`
  - [x] `is_active`
  - [x] timestamps
- [x] Add unique index on `code`.

### Subscriptions
- [x] Create `subscriptions` table with fields such as:
  - [x] `id`
  - [x] `tenant_id` or `company_id`
  - [x] `plan_id`
  - [x] `status`
  - [x] `current_period_start`
  - [x] `current_period_end`
  - [x] `grace_until`
  - [x] `auto_renew_mode`
  - [x] `next_plan_id`
  - [x] `change_effective_at`
  - [x] `blocked_reason`
  - [x] timestamps
- [x] Add indexes for tenant/company + status.
- [x] Enforce one current active subscription per tenant/company as needed.

### Billing Invoices
- [x] Create `billing_invoices` table with fields such as:
  - [x] `id`
  - [x] `tenant_id`
  - [x] `subscription_id`
  - [x] `period_start`
  - [x] `period_end`
  - [x] `plan_snapshot_code`
  - [x] `amount_kzt`
  - [x] `status`
  - [x] `payment_method`
  - [x] `kaspi_payment_link`
  - [x] `issued_at`
  - [x] `due_at`
  - [x] `paid_at`
  - [x] `activated_by_user_id`
  - [x] `note`
  - [x] timestamps
- [x] Add indexes for tenant/company + status + due date.

### Payments
- [x] Create `payments` table with fields such as:
  - [x] `id`
  - [x] `tenant_id`
  - [x] `billing_invoice_id`
  - [x] `amount_kzt`
  - [x] `method`
  - [x] `status`
  - [x] `paid_at`
  - [x] `confirmed_at`
  - [x] `confirmed_by_user_id`
  - [x] `external_reference`
  - [x] `proof_attachment_url` (or equivalent)
  - [x] timestamps
- [x] Add indexes for invoice + status.

### Usage Counters
- [x] Create `usage_counters` table with fields such as:
  - [x] `id`
  - [x] `tenant_id`
  - [x] `metric`
  - [x] `period_start`
  - [x] `period_end`
  - [x] `value`
  - [x] timestamps
- [x] Add unique index on `(tenant_id, metric, period_start, period_end)`.

### Usage Events (recommended)
- [x] Create `usage_events` table with fields such as:
  - [x] `id`
  - [x] `tenant_id`
  - [x] `metric`
  - [x] `resource_type`
  - [x] `resource_id`
  - [x] `count`
  - [x] timestamps
- [x] Add indexes for tenant/company + period.

### Admin Notes / Audit
- [x] Create `admin_notes` or `billing_audit_events` table.
- [x] Ensure manual actions are traceable.

## Seed Data
- [x] Seed `trial`, `starter`, and `basic` plans.

## Deliverables
- [x] migrations
- [x] schemas
- [x] changesets
- [x] seeds for plans

## Done Criteria
- [x] All billing tables exist.
- [x] Constraints and indexes are in place.
- [x] Plans are seeded in dev/test.

---

# Phase 3 — Core Billing Services

## Goal
Implement the core application services for subscription state, usage accounting, and payment confirmation.

## Tasks

### Plans API
- [x] Implement plan lookup functions.
- [x] Implement active plan listing functions.

### Subscription API
- [x] Implement `get_current_subscription/1`.
- [x] Implement subscription creation for new tenants.
- [x] Implement activation logic.
- [x] Implement suspension logic.
- [x] Implement grace-period transition logic.
- [x] Implement renewal extension logic.
- [x] Implement plan change scheduling logic.

### Usage API
- [x] Implement `current_document_usage/1`.
- [x] Implement `allowed_document_limit/1`.
- [x] Implement `allowed_user_limit/1`.
- [x] Implement usage counter creation/upsert.
- [x] Implement usage event recording.

### Billing Invoice API
- [x] Implement invoice creation for renewals.
- [x] Implement invoice creation for upgrades.
- [x] Implement invoice status transitions.
- [x] Implement overdue marking.

### Payment API
- [x] Implement manual payment confirmation service.
- [x] Implement payment rejection service.
- [x] Implement idempotent protection so the same invoice is not confirmed twice.

## Important Transactional Work
- [x] Confirm payment in a DB transaction.
- [x] Update invoice + payment + subscription atomically.
- [x] Prevent double-activation from repeated admin clicks.

## Deliverables
- [x] billing context functions
- [x] tests for service-layer behavior

## Done Criteria
- [x] New tenant can receive a trial subscription.
- [x] Payment confirmation extends access correctly.
- [x] Suspension/reactivation can be executed from code.

## Phase 3 Summary
- Added service-layer APIs in `EdocApi.Billing` for plan lookup/listing, current subscription lookup, trial creation, subscription state transitions, current-period usage accounting, billing invoice transitions, and payment confirmation/rejection.
- Payment confirmation is transactional and idempotent: repeated confirmation returns the existing confirmed payment/invoice/subscription state without extending access twice.
- Added service tests covering the Phase 3 lifecycle paths.

## Phase 3 Open Risks
- These services are not wired into document enforcement, tenant onboarding, admin screens, or scheduled jobs yet; those are later phases.
- Payment confirmation currently assumes trusted admin/service callers and does not yet enforce admin authorization in the billing context.

---

# Phase 4 — Enforce Limits and Access Restrictions

## Goal
Prevent unpaid or over-limit tenants from continuing billable usage.

## Tasks

### Document Quota Enforcement
- [x] Implement `can_create_document?/1`.
- [x] Implement `ensure_can_create_document!/1`.
- [x] Implement `record_document_usage/3`.
- [x] Decide whether usage is counted on draft creation, finalization, or issue.
- [x] Apply enforcement at all document entry points.

### User Seat Enforcement
- [x] Implement `can_add_user?/1`.
- [x] Implement `ensure_can_add_user!/1`.
- [x] Count current active users correctly.
- [x] Respect fixed plan seats from `plans.included_users`.

### Subscription Standing Enforcement
- [x] Decide grace-period behavior: allow creation during the Phase 0 grace window.
- [x] Otherwise allow limited grace behavior only if explicitly desired.
- [x] Block creation when status is `suspended`.
- [x] Ensure read-only access still works.

### App Integration
- [x] Add enforcement errors/messages at domain level.
- [x] Map domain errors to controller/API responses.
- [x] Surface clear upgrade/payment prompts in API response payloads where appropriate.

## Deliverables
- [x] enforcement guards
- [x] tests proving blocked/unblocked behavior

## Done Criteria
- [x] Tenant cannot exceed document quota.
- [x] Tenant cannot exceed user seat quota.
- [x] Suspended tenant cannot create new billable data.

## Phase 4 Summary
- Added billing guard APIs for document quota, subscription standing, and user-seat enforcement.
- Billing document usage is still counted on issue/finalization; draft creation checks the already-used quota before allowing new drafts.
- Grace-period tenants remain allowed because the Phase 0 policy includes a grace window; `past_due`, `suspended`, and `canceled` tenants are blocked.
- Bridged the existing `Monetization` API to the new billing guards when a new billing subscription exists, while preserving legacy behavior for tenants that have not migrated.

## Phase 4 Open Risks
- Controller/UI messages still use the existing `quota_exceeded` response path for document blocks, with `reason: :subscription_restricted` included in details for suspended/past-due billing subscriptions.
- Seat enforcement is available through Billing and affects existing invite limits via `Monetization.effective_seat_limit/1`; direct invite creation still lives in the legacy membership module until later admin/team phases.

---

# Phase 5 — Admin CRM / Backoffice Foundation

## Goal
Provide an internal admin interface to monitor clients and manually control billing lifecycle.

## Tasks

### Admin Auth / Authorization
- [x] Decide where admin panel lives: `/admin/billing/...`.
- [x] Restrict admin routes to internal/admin users only via `users.is_platform_admin`.

### Client List View
- [x] Build list page for tenants/clients with columns such as:
  - [x] company name
  - [x] current plan
  - [x] subscription status
  - [x] active users / limit
  - [x] documents used / limit
  - [x] current period end
  - [x] overdue state

### Client Detail View
- [x] Build client detail page with sections:
  - [x] company info
  - [x] subscription info
  - [x] usage summary
  - [x] user list
  - [x] invoice history
  - [x] payment history
  - [x] internal notes

### Billing Invoice List View
- [x] Build invoice list with filters:
  - [x] draft
  - [x] sent
  - [x] paid
  - [x] overdue
- [x] Show Kaspi link availability and invoice due date.

### Admin Actions
- [x] Add action: create renewal invoice.
- [x] Add action: edit/add Kaspi payment link.
- [x] Add action: mark invoice as sent.
- [x] Add action: confirm payment.
- [x] Add action: reject payment.
- [x] Add action: activate/reactivate tenant.
- [x] Add action: suspend tenant.
- [x] Add action: extend grace period.
- [x] Add action: schedule upgrade.
- [x] Add action: add internal note.

## Deliverables
- [x] admin billing dashboard
- [x] client detail view
- [x] invoice/payment views

## Done Criteria
- [x] Admin can find any client quickly.
- [x] Admin can confirm payment from UI.
- [x] Admin can see which clients are overdue.

## Phase 5 Summary

- Added `/admin/billing/...` backoffice routes protected by a new `users.is_platform_admin` flag.
- Added client list/detail pages with subscription, seat, document, invoice, payment, and internal-note visibility.
- Added billing invoice list filters and manual actions for Kaspi link/sent state, payments, suspension/reactivation, grace extension, scheduled upgrades, renewal invoices, and upgrade invoices.

## Phase 5 Open Risks

- Platform-admin assignment is currently database/manual only; a later operational task should define who can grant or revoke this flag.
- Backoffice copy is intentionally internal English for now; localizing it can be deferred unless non-technical operators will use it.

---

# Phase 6 — Kaspi Link Payment Workflow

## Goal
Implement the operational workflow for Kaspi payment links.

## Tasks

### Billing Invoice + Link Flow
- [x] Allow admin to attach Kaspi payment link to a billing invoice.
- [x] Store payment link safely by trimming blanks and validating http/https URLs.
- [x] Add validation that payment method is `kaspi_link` when link is present.
- [x] Allow copying/opening the link from admin UI.

### Customer-Facing Billing Page
- [x] Build tenant billing page showing:
  - [x] current plan
  - [x] renewal date
  - [x] outstanding invoices
  - [x] Kaspi payment link
  - [x] payment instructions
- [x] Show blocked/overdue banners where relevant.

### Payment Confirmation Workflow
- [x] Define internal steps for manual reconciliation.
- [x] Add optional fields for proof/reference from customer.
- [x] Add internal comment/note for payment review.

## Deliverables
- [x] tenant billing page
- [x] admin Kaspi-link handling flow

## Done Criteria
- [x] Customer can see outstanding invoice and payment link.
- [x] Admin can confirm payment after receiving it.

## Phase 6 Summary

- Added a tenant-facing `/company/billing` page showing the current plan, renewal date, outstanding billing invoices, Kaspi payment links, payment instructions, and blocked/overdue banners.
- Added customer payment-review submission with optional external reference, proof URL, and internal review note.
- Hardened Kaspi-link handling so billing invoices require `payment_method: "kaspi_link"` when a Kaspi link is stored, and admin UI can open/copy the link.

## Phase 6 Open Risks

- Customer proof is currently a URL field, not a file upload flow.
- Payment confirmation remains manual from the backoffice; automated Kaspi reconciliation is intentionally deferred.

---

# Phase 7 — Renewal Cycle and Overdue Automation

## Goal
Automate invoice generation and subscription state transitions around renewals.

## Tasks

### Renewal Invoice Generation
- [x] Create scheduled job to generate renewal invoices before period end.
- [x] Recommended lead time: 5 to 7 days before `current_period_end`.
- [x] Avoid duplicate invoice generation for the same period.

### Overdue State Transitions
- [x] Mark invoice overdue when `due_at` passes.
- [x] Transition subscription to `past_due` or `grace_period` based on product rule.
- [x] Transition to `suspended` after grace period expires.

### Recovery Flow
- [x] When overdue invoice is confirmed as paid, restore subscription to `active`.
- [x] Extend `current_period_end` correctly.
- [x] Clear blocked reason where relevant.

### Scheduled Jobs
- [x] Add recurring jobs (Oban or equivalent) for:
  - [x] invoice generation
  - [x] overdue marking
  - [x] grace expiry processing

## Deliverables
- [x] automated renewal jobs
- [x] state transition tests

## Done Criteria
- [x] Renewals are generated automatically.
- [x] Unpaid tenants move through overdue lifecycle correctly.
- [x] Paid overdue tenants can be reactivated safely.

## Phase 7 Summary

- Added daily Oban billing lifecycle jobs for renewal invoice creation, overdue marking, and grace-expiry suspension.
- Added idempotent renewal generation with a 7-day lead window and duplicate prevention for the same subscription period.
- Added overdue processing that moves tenants into a 7-day grace period, then suspends after grace expiration.
- Existing payment confirmation flow now serves as the recovery path by restoring `active`, extending the paid period, and clearing blocked/grace fields.

## Phase 7 Open Risks

- Renewal invoices are generated as drafts; attaching Kaspi links and sending invoices remains an admin/manual step.
- The current grace policy allows document creation during the 7-day grace period and blocks only after suspension.

---

# Phase 8 — Upgrade and Seat Expansion Workflow

## Goal
Support plan upgrades and additional user seats.

## Tasks

### Upgrade Flow
- [x] Add customer/admin action to request upgrade.
- [x] Decide MVP behavior:
  - [x] immediate upgrade after payment, or
  - [ ] upgrade next cycle
- [x] Create upgrade billing invoice.
- [x] On payment confirmation, apply upgrade logic.

### Downgrade Flow
- [x] Support scheduled downgrade for next billing cycle.
- [x] Prevent immediate downgrade if it would violate current active user count or current usage assumptions.

### Seat Limits
- [x] Enforce fixed plan seats from plan definitions.
- [x] Trial and Starter allow 2 seats.
- [x] Basic allows 5 seats.

### Optional Proration
- [x] If implementing immediate mid-cycle upgrade, decide proration rules.
- [ ] Add tests for proration if included.

## Deliverables
- [x] upgrade workflow
- [x] seat add-on workflow

## Done Criteria
- [x] Tenant can move to a higher plan via invoice/payment flow.
- [x] Additional seats affect user limit correctly.

## Phase 8 Summary

- Added tenant-facing Basic upgrade invoice requests from `/company/billing` and admin-facing immediate upgrade invoice creation.
- Chose the MVP upgrade policy: paid upgrade invoices apply immediately for the remainder of the current billing cycle, without proration.
- Added scheduled downgrade support for the next cycle, with guards for occupied seats and current document usage before scheduling.
- Removed extra-seat expansion from the product model; seat limits now come only from the selected plan.
- Payment confirmation now clears pending scheduled plan-change fields after applying the paid invoice period.

## Phase 8 Open Risks

- Upgrade invoices currently charge full target-plan price for the remainder of the current cycle; real proration is intentionally deferred.
- Extra-seat purchase/request UI is intentionally not implemented because the product only supports fixed plan seat limits.

---

# Phase 9 — Notifications and Reminders

## Goal
Reduce missed payments through timely reminders.

## Tasks
- [x] Add reminder notification 7 days before renewal.
- [x] Add reminder notification 3 days before renewal.
- [x] Add day-of-due reminder.
- [x] Add overdue reminder after due date.
- [x] Add suspended notice after account suspension.
- [x] Add internal admin alert for overdue high-value clients.

## Delivery Channels
- [x] email
- [x] in-app banner
- [x] optional WhatsApp/manual follow-up placeholder

## Deliverables
- [x] reminder jobs
- [x] notification templates

## Done Criteria
- [x] Reminder cadence works end to end.
- [x] Overdue clients receive clear payment instructions.

## Phase 9 Summary
- Added `send_billing_reminders` lifecycle processing for 7-day, 3-day, due-day, overdue, suspended, and high-value overdue admin alerts.
- Reminder sends are idempotent through `billing_audit_events` and are dispatched by the daily billing Oban cron.
- Tenant billing snapshots now expose in-app reminder banners for overdue payments and suspended subscriptions.
- Customer emails include payment instructions and route clients back to the billing page or Kaspi link when present.

## Open Risks / Blockers
- WhatsApp follow-up remains a manual/internal process placeholder; no WhatsApp API integration exists yet.
- Billing reminder copy is Russian-first for MVP and should be localized if paid billing emails must follow the UI locale.

---

# Phase 10 — Audit, Reporting, and Hardening

## Goal
Make the system operationally safe and visible.

## Tasks

### Auditability
- [x] Log all admin billing actions.
- [x] Log subscription status changes.
- [x] Log payment confirmation actions with actor and timestamp.

### Reporting
- [x] Add admin dashboard cards for:
  - [x] active clients
  - [x] trial clients
  - [x] overdue clients
  - [x] suspended clients
  - [x] monthly collected revenue
  - [x] upcoming renewals
- [x] Add lists for:
  - [x] invoices due soon
  - [x] unpaid invoices
  - [x] recently reactivated clients

### Safety and Correctness
- [x] Add concurrency tests around payment confirmation.
- [x] Add concurrency tests around document usage counting.
- [x] Ensure double-submit does not double-charge or double-extend.
- [x] Ensure suspension rules are consistently enforced across all entry points.

### Documentation
- [x] Write internal admin operating guide.
- [x] Write customer-facing billing behavior notes.

## Deliverables
- [x] reporting widgets or pages
- [x] audit logs
- [x] internal runbook

## Done Criteria
- [x] Billing actions are traceable.
- [x] Operational dashboard is usable.
- [x] Core race conditions are covered by tests.

## Phase 10 Summary
- Added backoffice dashboard aggregates and operational lists to `/admin/billing/clients`.
- Added audit logging for admin billing actions, payment confirmations/rejections, and subscription status transitions.
- Hardened payment confirmation and usage recording behavior to be safe for repeated submits and concurrent attempts.
- Added billing operations docs for internal admins and customer-facing billing behavior.

## Open Risks / Blockers
- Dashboard revenue currently computes from `billing_invoices.paid_at` and does not include external accounting reconciliations.
- Customer-facing billing copy in docs is RU/EN style and may need full RU/KK localized UI content if shown directly in product screens.

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
- [x] Complete Phase 3 and run service tests.
- [x] Complete Phase 4 and verify blocked/unblocked flows.
- [x] Complete Phase 5 and verify admin flows.
- [x] Complete Phase 6 and verify tenant billing page.
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
