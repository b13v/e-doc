# Billing Rules and Enforcement Map

Phase 0 discovery for the billing, Kaspi payment-link, subscription renewal, and admin CRM implementation.

## Current Tenant Model

- The tenant is the `companies` row.
- The first registered user owns the company through `companies.user_id`.
- Team access is modeled separately through `tenant_memberships`.
- `tenant_memberships.role` currently supports `owner`, `admin`, and `member`.
- `tenant_memberships.status` currently supports `invited`, `pending_seat`, `active`, and `removed`.
- A user can access a company either because they own `companies.user_id` or because they have an active tenant membership.
- `EdocApi.Companies.get_company_by_user_id/1` returns the owned company first, otherwise the first active membership company.
- Owner/admin users can manage billing and team membership through `EdocApi.Monetization.can_manage_billing_and_team?/2`.
- Member users must not change tariffs, invite users, or remove users.

## Current Subscription and Usage Model

- Existing subscription records live in `tenant_subscriptions`.
- Current plans are `trial`, `starter`, and `basic`.
- Current subscription statuses are `active`, `canceled`, and `past_due`.
- Current trial policy is both document-count and time-window based:
  - 10 billable documents total.
  - 14 days from `trial_started_at` or `period_start`.
- Starter currently allows 50 documents per period and 2 occupied seats.
- Basic currently allows 500 documents per period and 5 occupied seats.
- Occupied seats are active, invited, and pending-seat memberships.
- Existing usage events live in `tenant_usage_events`.
- Usage events are unique per `(company_id, document_type, document_id)`, so a document is counted only once.

## Billable Document Rule

For the MVP billing implementation, a billable document is counted when a document is finalized for the first time.

Billable actions:

- Invoice: first successful issue, recorded as `invoice_issued`.
- Contract: first successful issue, recorded as `contract_issued`.
- Act: first successful issue, recorded as `act_issued`.

Non-billable actions:

- Creating or editing drafts.
- Marking an invoice as paid.
- Marking a contract as signed.
- Marking an act as signed.
- Downloading or regenerating PDFs for existing documents.
- Sending an existing document by email, WhatsApp, or Telegram.
- Deleting drafts.

Draft creation is still guarded by the current quota check. This is an intentional UX guard: if the tenant has no remaining document allowance, the app blocks creating a draft that cannot later be issued.

## Trial Rule

Trial usage is lifetime trial usage for the company, not monthly trial usage.

The trial ends when either condition is met:

- 10 billable documents have been consumed.
- 14 days have passed from the trial start.

The trial should not reset monthly unless a future product decision explicitly changes that rule.

## Upgrade and Downgrade Rules

MVP upgrade rule:

- Paid upgrades should apply immediately after payment confirmation.
- The upgraded limits should become available immediately after the billing invoice is confirmed as paid.

MVP downgrade rule:

- Downgrades should be scheduled for the next billing period by default.
- If an immediate downgrade is exposed in the current UI, it must remain guarded by target-plan seat and usage limits.
- A downgrade from Basic to Starter must not be allowed while occupied seats exceed the Starter limit.
- Occupied seats means active plus invited plus pending-seat memberships.

## Grace Period and Suspension Rules

Grace period:

- The MVP grace period is 3 days after a billing invoice becomes overdue.

Good-standing states:

- `trialing` when trial document and time limits are not exceeded.
- `active` when the current paid period is valid.
- `grace_period` during the 3-day overdue grace window.

Not-good-standing states:

- `past_due` after the grace period expires.
- `suspended` after access has been restricted.
- `canceled` when subscription access is explicitly ended.

When a tenant is not in good standing, block:

- Creating new invoices, contracts, and acts.
- Issuing invoices, contracts, and acts.
- Inviting or activating additional users.
- Plan changes that would increase usage before payment is confirmed.

When a tenant is not in good standing, still allow:

- Sign in.
- Viewing existing documents and company data.
- Downloading or regenerating PDFs for existing documents.
- Viewing billing pages.
- Paying outstanding billing invoices.
- Removing users to get under plan limits.

## Current Document Models

Invoices:

- Schema: `EdocApi.Core.Invoice`.
- Table: `invoices`.
- Tenant key: `company_id`.
- User key: `user_id`.
- Statuses: `draft`, `issued`, `paid`, `void`.
- Contract-linked invoices use `contract_id`.
- A contract-linked invoice can only progress when the contract progression rule allows it.

Contracts:

- Schema: `EdocApi.Core.Contract`.
- Table: `contracts`.
- Tenant key: `company_id`.
- No direct `user_id` field exists on contracts.
- Statuses: `draft`, `issued`, `signed`.
- Contract signing is not billable.

Acts:

- Schema: `EdocApi.Core.Act`.
- Table: `acts`.
- Tenant key: `company_id`.
- User key: `user_id`.
- Statuses: `draft`, `issued`, `signed`.
- Act signing is not billable.

## Current Document Creation and Finalization Entry Points

HTML invoice entry points:

- `GET /invoices/new`
- `POST /invoices`
- `GET /invoices/from-contract/:contract_id`
- `POST /invoices/from-contract/:contract_id`
- `PUT /invoices/:id`
- `POST /invoices/:id/issue`
- `POST /invoices/:id/pay`

API invoice entry points:

- `POST /v1/invoices`
- `PUT /v1/invoices/:id`
- `POST /v1/invoices/:id/issue`
- `POST /v1/invoices/:id/pay`

HTML contract entry points:

- `GET /contracts/new`
- `POST /contracts`
- `PUT /contracts/:id`
- `POST /contracts/:id/issue`
- `POST /contracts/:id/sign`

API contract entry points:

- `POST /v1/contracts`
- `POST /v1/contracts/:id/issue`
- `POST /v1/contracts/:id/sign`

HTML act entry points:

- `GET /acts/new`
- `POST /acts`
- `PUT /acts/:id`
- `POST /acts/:id/issue`
- `POST /acts/:id/sign`

Core service enforcement points:

- `EdocApi.Invoicing.create_invoice_for_user/3`
- `EdocApi.Invoicing.issue_invoice_for_user/2`
- `EdocApi.Core.create_contract_for_user/3`
- `EdocApi.Core.issue_contract_for_user/2`
- `EdocApi.Acts.create_act_for_user/3`
- `EdocApi.Acts.issue_act_for_user/2`

Existing quota functions:

- `EdocApi.Monetization.ensure_document_creation_allowed/1`
- `EdocApi.Monetization.consume_document_quota/4`

## Current Team Invitation and User Entry Points

HTML team entry points:

- `POST /company/memberships`
- `DELETE /company/memberships/:id`
- `POST /company/subscription`

API/company entry point:

- `PUT /company/subscription`

Registration and invitation entry points:

- `GET /signup`
- `POST /signup`
- `GET /verify-email-pending`
- `GET /verify-email`
- `POST /verify-email-pending/resend`

Core team enforcement points:

- `EdocApi.Monetization.invite_member/2`
- `EdocApi.Monetization.accept_pending_memberships_for_user/1`
- `EdocApi.Monetization.can_activate_member?/1`
- `EdocApi.Monetization.validate_plan_change/2`
- `EdocApi.Monetization.remove_membership/2`

## Schema Gaps for Later Phases

The current monetization tables are enough for basic quota and seat enforcement, but not enough for full billing operations.

Missing or incomplete concepts:

- Dedicated plan catalog table.
- Billing invoice table for Kaspi payment-link renewals.
- Payment records with manual confirmation state.
- Billing audit events/admin notes.
- Explicit subscription statuses for `trialing`, `grace_period`, `suspended`, and `canceled`.
- Billing invoice statuses such as `draft`, `sent`, `paid`, `overdue`, and `canceled`.
- Payment statuses such as `pending_confirmation`, `confirmed`, and `rejected`.
- Monthly usage counters derived from immutable usage events.

## Phase 0 Decisions

- Company is the tenant boundary.
- Billable usage is counted on first successful issue/finalization, not on draft creation.
- Draft creation remains blocked when no document allowance remains.
- Trial is lifetime per company and expires after 10 billable documents or 14 days.
- Upgrades are immediate after payment confirmation.
- Downgrades are next-cycle by default, with immediate downgrade allowed only when target-plan constraints are already satisfied.
- Grace period is 3 days.
- Suspended tenants can still view existing data and download/regenerate old PDFs.
- Backend service functions remain the primary enforcement layer; UI controls are secondary.
