# Team Membership Monetization Design

Date: 2026-04-03

## Goal

Extend the current subscription foundation so seat limits are enforceable through real tenant membership management. The first implementation pass should let a company owner invite teammates by email from `/company`, consume seats in a predictable way, and automatically activate invited users when they log in with the invited email.

## Current Context

The app already has:

- subscription plans with document quotas and seat limits
- a `tenant_memberships` table with `company_id`, `user_id`, `role`, and `status`
- owner membership seeding when a company is created
- subscription visibility and plan adjustment on `/company`
- company lookup that already falls back to active tenant membership

The remaining gap is that there is no actual team-management workflow. Seat counts are visible, but there is no way to invite, activate, or remove tenant members.

## Requirements

The next slice must:

- allow inviting teammates by email from the company settings page
- support `admin` and `member` roles
- keep `owner` reserved for the original company owner flow
- enforce seat limits during invite creation
- show invited and active members on `/company`
- auto-activate invited memberships when a user signs in with the invited email
- avoid adding invitation email delivery in this pass

The next slice must not yet:

- send invitation emails
- implement magic-link acceptance
- add role editing after invite
- add multi-tenant switching UI
- add a separate audit log

## Approaches Considered

### Approach 1: Reuse `tenant_memberships` for invited and active members

Store invited users directly in `tenant_memberships` by adding `invite_email`, leaving `user_id` nullable while invited, and using `status` to represent lifecycle.

Pros:

- smallest schema change
- fits the existing membership-based company lookup
- minimal controller and auth integration

Cons:

- one table carries both pending and active membership states

Recommendation: use this approach.

### Approach 2: Add a dedicated `tenant_invites` table

Create invitations separately and convert them to memberships on acceptance.

Pros:

- cleaner separation between invitation and membership lifecycle

Cons:

- more tables, code paths, tests, and lifecycle complexity than needed now

### Approach 3: Invitation token flow with explicit acceptance page

Require a dedicated invitation acceptance step.

Pros:

- stronger long-term UX and security story

Cons:

- introduces token issuance, expiry, delivery, and acceptance UI immediately
- too large for the next slice

## Chosen Design

### Data Model

Extend `tenant_memberships`:

- add `invite_email`
- keep `user_id` nullable for invited memberships
- continue using `status` with `invited`, `active`, and `removed`

Constraints:

- one membership per `company_id + user_id` when `user_id` is present
- one membership per `company_id + invite_email` when `invite_email` is present
- email values must be normalized before persistence

Status behavior:

- `owner` memberships are active and seeded automatically
- invited teammates are stored with `status = invited`
- accepted teammates are stored with `status = active`
- removed teammates are stored with `status = removed`

### Seat Consumption Rule

Seats are consumed at invite time, not only at activation time.

Reasoning:

- it prevents oversubscription by sending a large number of pending invites
- it makes the visible seat counters match the real company capacity commitment
- it keeps the implementation simple because invited users already occupy a slot

Operationally:

- `active` and `invited` memberships both count against the seat limit
- `removed` memberships do not count against the seat limit

### Backend API

Add membership operations in the existing monetization layer first:

- `list_memberships(company_id)`
- `invite_member(company_id, attrs)`
- `remove_membership(company_id, membership_id)`
- `accept_pending_memberships_for_user(user)`

Responsibilities:

- `list_memberships/1` returns invited and active members for company settings
- `invite_member/2` normalizes email, checks seat availability, rejects duplicates, and creates an invited membership
- `remove_membership/2` marks a membership removed and frees the seat
- `accept_pending_memberships_for_user/1` finds invited memberships by normalized email, binds `user_id`, and activates them

Business rules:

- cannot invite if no seats remain
- cannot invite an email already invited for the same company
- cannot invite a user already active in the same company
- cannot remove the only remaining owner

### Auth Integration

Membership acceptance should happen on successful login.

Reasoning:

- it is the first reliable point where a verified authenticated user exists
- it avoids coupling invitation acceptance to email verification internals
- it covers both existing users and newly registered users once they log in

Flow:

1. user logs in successfully
2. system normalizes `user.email`
3. system finds any matching invited memberships
4. matching memberships are updated to `status = active` and `user_id = user.id`
5. user can immediately access the tenant through the existing company lookup path

This same helper may also be called from other authentication entry points later, but login is sufficient for the first pass.

### UI

Extend `/company` with a Team panel below subscription.

Team panel contents:

- invite form with:
  - email
  - role select (`admin`, `member`)
  - invite button
- members list showing:
  - email
  - role
  - status
  - remove action for removable memberships

Display rules:

- invited and active memberships are shown together
- owner is visible and not removable through this first-pass UI
- subscription seat usage remains the high-level summary

### Error Handling

User-facing cases:

- seat limit reached
- invitation already exists
- member already exists
- invalid email
- membership not found
- owner removal blocked

Controller behavior:

- redirect back to `/company`
- use localized flash messages for success and failure

### Testing Strategy

Follow test-first implementation.

Required tests:

- monetization/context tests for:
  - invite creation
  - seat-limit rejection
  - duplicate-invite rejection
  - membership activation on matched email
  - membership removal
- controller tests for:
  - rendering the Team panel on `/company`
  - inviting a member through the HTML form
  - removing a member through the HTML flow
- authentication tests for:
  - invited existing user becomes active on login
  - newly registered user with invited email becomes active on first login

## Implementation Boundaries

Included in this pass:

- schema extension for pending invites
- backend membership operations
- HTML company settings team-management UI
- login-triggered membership activation
- localized flashes and labels

Deferred:

- invitation emails
- acceptance tokens
- role editing
- tenant switching UI
- API endpoints for membership management

## Risks

### Duplicate identity state

If email normalization is inconsistent, an invited email may not match a user email later. Mitigation: always normalize using the same account/email normalization path before persistence and lookup.

### Seat-count drift

If invited memberships are not counted the same way everywhere, the subscription card and invite guard can diverge. Mitigation: add one shared helper for occupied seat count and use it for snapshot plus invite checks.

### Owner safety

If removal is too permissive, a company can lose its only owner. Mitigation: explicitly block removal of the last owner in backend logic even if the UI hides the action.

## Recommended Next Step

Write the implementation plan for this exact first pass, then execute it test-first.
