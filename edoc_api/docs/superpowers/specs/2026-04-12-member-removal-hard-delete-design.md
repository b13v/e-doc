# Member Removal Company-Scoped Offboarding Design

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
2. Remove user access to this company completely.
3. Delete user account globally only when they have no remaining company associations.

## 3. Scope

In scope:

- Company member removal flow (`/company/memberships/:id`).
- Domain-level reassignment + company-scoped offboarding for active members.
- Conditional hard delete logic when user has no other companies.
- Error mapping and localized flash behavior.
- Test coverage for reassignment + offboarding + conditional auth outcome.

Out of scope:

- Owner removal semantics (existing last-owner guard stays).
- Bulk/offline member cleanup jobs.
- Data anonymization/legal retention policy changes.

## 4. Chosen Approach

Chosen approach: transactional **company-scoped reassignment -> membership removal -> conditional hard delete**.

Decision details:

- Reassignment target: **company owner** (not actor admin).
- For members with user-linked records in target company, affected records are moved to target-company owner first.
- User is hard-deleted only if there are no global FK blockers after target-company offboarding:
  - no `companies.user_id == member_user_id`
  - no `tenant_memberships.user_id == member_user_id` (any status)
  - no `invoices.user_id == member_user_id` (any company)
  - no `acts.user_id == member_user_id` (any company)
- Operation is all-or-nothing in one DB transaction.

## 5. Functional Behavior

### 5.1 Member removal (active member with user_id)

When owner/admin removes an active member:

1. Validate actor permission (existing guard).
2. Validate target is not last owner (existing guard).
3. Resolve active owner membership for same company.
4. Reassign target user-owned records in same company to owner.
5. Remove membership association from current company.
6. Conditionally hard-delete user only if no remaining cross-company ties.
7. Return success flash.

Lifecycle contract for active-member path:

- membership row is physically deleted (no tombstone) for removed target company access;
- `remove_membership/2` success return contract is explicit and branch-specific:
  - active user company-only offboard branch: `{:ok, %{mode: :company_removed_only, membership_id: ..., user_id: ...}}`
  - active user hard-delete branch: `{:ok, %{mode: :hard_deleted_user, membership_id: ..., user_id: ...}}`
  - invited/pending soft-remove branch: `{:ok, %{mode: :soft_removed_membership, membership_id: ...}}`

### 5.2 Invited/pending membership removal

If target membership has no `user_id` (invited/pending), keep existing behavior:

- mark membership removed / remove seat occupancy;
- no user deletion attempt.

### 5.3 Post-removal auth behavior

After removal:

- if `mode == :hard_deleted_user`: old credentials cannot authenticate; signup is required;
- if `mode == :company_removed_only`: user can still log in for their other companies, but has no access to removed company.

## 6. Architecture and Boundaries

### Unit A: `Monetization.remove_membership/2` orchestration

- Keeps business-rule checks (`last_owner`, membership existence).
- Detects whether target has linked active user.
- Delegates hard-delete flow for active member users.

### Unit B: `Accounts` deletion service (new)

- New service function (name finalized in implementation plan) to:
  - receive `company_id`, `member_user_id`, `owner_user_id`;
  - run transaction for reassignment + company offboarding + conditional user delete;
  - return domain errors on failure.
- Precondition checks include:
  - target user is not the last owner for the target company (existing guard);
  - cross-company ownership/membership is used to choose `company_removed_only` vs `hard_deleted_user`, not as a hard error.
  - hard-delete eligibility is based on `user_id` blockers listed in section 4, not on email invite rows.

### Unit C: Controller flash mapping

- `CompaniesController.remove_member` remains thin.
- Maps new domain errors to localized, user-friendly flash messages.

## 7. Data Reassignment Rules

Reassignment for target company is explicit and table-by-table:

- `invoices.user_id` (company-scoped) -> reassign to owner.
- `acts.user_id` (company-scoped) -> reassign to owner.

`generated_documents` policy:

- do not reassign globally to owner (avoids cross-company ownership mixing).
- on `company_removed_only`: delete removed user’s `generated_documents` that reference documents from the target company (invoice/act/contract ids in that company), so removed-company cached PDFs are not retrievable anymore.
- on `hard_deleted_user`: delete all `generated_documents` rows for that user explicitly.
- for rows with `file_path`, perform best-effort filesystem cleanup after DB commit (log-and-continue on file delete failure; DB operation remains successful).

Public share-link policy:

- on both `company_removed_only` and `hard_deleted_user` branches, delete/revoke `public_access_tokens` for target-company documents created by removed user.
- this invalidates previously shared public links initiated by removed member for the removed company.

Email-invite policy (`tenant_memberships.invite_email`):

- invite/pending rows keyed by email are not treated as hard-delete blockers;
- they may remain and can be accepted later if user signs up again with same email.

Delete behavior for user-linked auth/session rows:

- `refresh_tokens` (`on_delete: :delete_all`).
- `email_verification_tokens` (`on_delete: :delete_all`).
- `password_reset_tokens` (`on_delete: :delete_all`).
- `tenant_memberships.user_id` (`on_delete: :delete_all`) on hard-delete branch only.

Reassignment filter for company-bound tables:

- `company_id == target_company_id`;
- `user_id == removed_member_user_id`.

User-scoped tables without `company_id` are never reassigned to another user in this design.

Invoice uniqueness collision policy:

- `invoices` has unique index `[:user_id, :number]`;
- if reassignment causes collision with owner invoice numbers, transaction is rolled back and removal fails with explicit domain error (`:invoice_number_conflict_on_reassign`), no partial changes.

## 8. Failure Handling

Potential new errors from domain layer:

- `:owner_not_found` — no active owner available for reassignment.
- `:reassign_failed` — reassignment/update/delete failure.
- `:invoice_number_conflict_on_reassign` — invoice number uniqueness conflict during ownership transfer.
- existing: `:not_found`, `:last_owner`.

Transaction semantics:

- Any step failure rolls back all previous updates.
- No partial reassignment and no partial deletion.

Controller mapping contract:

- `:owner_not_found`, `:reassign_failed`, `:invoice_number_conflict_on_reassign`
  - redirect to `/company`
  - localized error flash (RU/KK) with actionable text;
  - no internal technical details in UI.

## 9. Testing Strategy (TDD)

Required tests:

1. Monetization/domain:
   - active member with invoices/acts is removed;
   - invoices/acts reassigned to owner;
   - branch result is `:company_removed_only` when user still belongs elsewhere.
   - branch result is `:hard_deleted_user` when user has no remaining company ties.
2. Regression:
   - invited member removal still works.
   - last owner protection unchanged.
   - soft-remove branch returns `mode: :soft_removed_membership`.
   - company-only branch returns `mode: :company_removed_only`.
   - hard-delete branch returns `mode: :hard_deleted_user`.
3. Controller:
   - owner/admin removal success path unchanged UX-wise.
   - non-privileged member still blocked.
   - each new domain error maps to localized RU/KK flash:
     - `:owner_not_found`
     - `:reassign_failed`
     - `:invoice_number_conflict_on_reassign`
4. Auth outcome:
   - hard-deleted removed user login fails (`invalid_credentials` path).
   - company-only removed user still logs in and does not regain removed company access.
5. Conflict path:
   - invoice number collision during reassignment returns explicit error and preserves all rows unchanged.
6. Hard-delete eligibility path:
   - if any global blocker remains (`companies`, `tenant_memberships`, `invoices`, `acts` by `user_id`), mode must be `:company_removed_only` and user row remains.
7. Generated-document cleanup path:
   - `company_removed_only` removes target-company cached PDFs for removed member.
   - `hard_deleted_user` removes all cached PDFs for deleted user.
   - file-backed artifacts (`file_path`) are attempted to be deleted (best effort).
8. Public-link revocation path:
   - target-company `public_access_tokens` created by removed member are removed/revoked during offboarding transaction.

## 10. Acceptance Criteria

1. Removing active member always removes their access to the target company.
2. Member historical documents in the target company are reassigned to owner, not lost.
3. User account is hard-deleted only when no remaining company ties exist.
4. If hard-deleted, old credentials fail and signup is required.
5. If not hard-deleted, user can still access their other companies only.
6. Removing invited member remains supported.
7. Last owner removal remains blocked.
8. Tests proving above behavior pass.
