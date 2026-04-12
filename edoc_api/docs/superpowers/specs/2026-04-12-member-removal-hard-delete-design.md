# Member Removal Hard-Delete Design

Date: 2026-04-12
Status: Draft for review
Owner: Monetization / Accounts / Company settings

## 1. Problem

Current behavior when owner/admin removes a team member:

- membership row is marked removed;
- user account remains in `users`;
- the removed user can still log in and is redirected to company setup flow.

This is not aligned with required business logic.

## 2. Goal

When a member is removed by owner/admin:

1. Reassign all removed member records to company owner.
2. Fully delete removed member account from database.
3. Ensure future login with old credentials fails; user must sign up again.

## 3. Scope

In scope:

- Company member removal flow (`/company/memberships/:id`).
- Domain-level reassignment + hard delete for active member users.
- Error mapping and localized flash behavior.
- Test coverage for reassignment + deletion + auth outcome.

Out of scope:

- Owner removal semantics (existing last-owner guard stays).
- Bulk/offline member cleanup jobs.
- Data anonymization/legal retention policy changes.

## 4. Chosen Approach

Chosen approach: transactional **reassign -> hard delete**.

Decision details:

- Reassignment target: **company owner** (not actor admin).
- For members with user-linked records, all affected records are moved to owner first.
- User is then hard-deleted from `users`.
- Operation is all-or-nothing in one DB transaction.

## 5. Functional Behavior

### 5.1 Member removal (active member with user_id)

When owner/admin removes an active member:

1. Validate actor permission (existing guard).
2. Validate target is not last owner (existing guard).
3. Resolve active owner membership for same company.
4. Reassign target user-owned records in same company to owner.
5. Remove membership association and hard-delete user.
6. Return success flash.

Lifecycle contract for active-member path:

- membership row is not preserved as tombstone;
- membership row is deleted via FK cascade when user is hard-deleted;
- `remove_membership/2` success return contract is explicit and branch-specific:
  - active user hard-delete branch: `{:ok, %{mode: :hard_deleted_user, membership_id: ..., user_id: ...}}`
  - invited/pending soft-remove branch: `{:ok, %{mode: :soft_removed_membership, membership_id: ...}}`

### 5.2 Invited/pending membership removal

If target membership has no `user_id` (invited/pending), keep existing behavior:

- mark membership removed / remove seat occupancy;
- no user deletion attempt.

### 5.3 Post-removal auth behavior

After successful hard delete:

- old credentials cannot authenticate;
- user must perform signup to access system again.

## 6. Architecture and Boundaries

### Unit A: `Monetization.remove_membership/2` orchestration

- Keeps business-rule checks (`last_owner`, membership existence).
- Detects whether target has linked active user.
- Delegates hard-delete flow for active member users.

### Unit B: `Accounts` deletion service (new)

- New service function (name finalized in implementation plan) to:
  - receive `company_id`, `member_user_id`, `owner_user_id`;
  - run transaction for reassignment + user delete;
  - return domain errors on failure.
- Precondition checks include:
  - target user is not owner of any company record in `companies.user_id` (otherwise reject with dedicated business error to avoid FK failure).

### Unit C: Controller flash mapping

- `CompaniesController.remove_member` remains thin.
- Maps new domain errors to localized, user-friendly flash messages.

## 7. Data Reassignment Rules

Reassignment is explicit and table-by-table:

- `invoices.user_id` (company-scoped) -> reassign to owner.
- `acts.user_id` (company-scoped) -> reassign to owner.
- `generated_documents.user_id` (user-scoped cache/history) -> reassign to owner.

Delete-by-cascade (no reassignment needed):

- `refresh_tokens` (`on_delete: :delete_all`).
- `email_verification_tokens` (`on_delete: :delete_all`).
- `password_reset_tokens` (`on_delete: :delete_all`).
- `tenant_memberships.user_id` (`on_delete: :delete_all`).

Reassignment filter for company-bound tables:

- `company_id == target_company_id`;
- `user_id == removed_member_user_id`.

User-scoped tables without `company_id` (like `generated_documents`) are reassigned by `user_id` only.

Invoice uniqueness collision policy:

- `invoices` has unique index `[:user_id, :number]`;
- if reassignment causes collision with owner invoice numbers, transaction is rolled back and removal fails with explicit domain error (`:invoice_number_conflict_on_reassign`), no partial changes.

## 8. Failure Handling

Potential new errors from domain layer:

- `:owner_not_found` — no active owner available for reassignment.
- `:reassign_failed` — reassignment/update/delete failure.
- `:invoice_number_conflict_on_reassign` — invoice number uniqueness conflict during ownership transfer.
- `:member_owns_company` — target user owns a company and cannot be hard-deleted safely.
- existing: `:not_found`, `:last_owner`.

Transaction semantics:

- Any step failure rolls back all previous updates.
- No partial reassignment and no partial deletion.

Controller mapping contract:

- `:owner_not_found`, `:reassign_failed`, `:invoice_number_conflict_on_reassign`, `:member_owns_company`
  - redirect to `/company`
  - localized error flash (RU/KK) with actionable text;
  - no internal technical details in UI.

## 9. Testing Strategy (TDD)

Required tests:

1. Monetization/domain:
   - active member with invoices/acts is removed;
   - invoices/acts reassigned to owner;
   - user row deleted.
2. Regression:
   - invited member removal still works.
   - last owner protection unchanged.
   - soft-remove branch returns `mode: :soft_removed_membership`.
   - hard-delete branch returns `mode: :hard_deleted_user`.
3. Controller:
   - owner/admin removal success path unchanged UX-wise.
   - non-privileged member still blocked.
   - each new domain error maps to localized RU/KK flash:
     - `:owner_not_found`
     - `:reassign_failed`
     - `:invoice_number_conflict_on_reassign`
     - `:member_owns_company`
4. Auth outcome:
   - removed user login fails (`invalid_credentials` path).
5. Conflict path:
   - invoice number collision during reassignment returns explicit error and preserves all rows unchanged.

## 10. Acceptance Criteria

1. Removing active member fully deletes that user account.
2. Member historical documents are reassigned to owner, not lost.
3. Removed member cannot log in with previous credentials.
4. Removing invited member remains supported.
5. Last owner removal remains blocked.
6. Tests proving above behavior pass.
