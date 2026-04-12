# Member Removal Company-Scoped Offboarding Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Removing a member from `/company` must fully remove access to that company, reassign company-owned records to owner, revoke member-created public links for that company, and hard-delete the user only when no global blockers remain.

**Architecture:** Keep orchestration in `Monetization.remove_membership/2`, move reassignment/offboarding mechanics into `Accounts` service transaction, and keep controller thin with localized flash mapping. Implement strict TDD for domain logic first, then controller behavior and i18n mapping.

**Tech Stack:** Elixir, Phoenix, Ecto, PostgreSQL, Gettext, ExUnit.

---

## File Structure Map

- `lib/edoc_api/accounts.ex`
  - Add company-offboarding service for active member users.
  - Owns reassignment queries and conditional hard-delete decision.
- `lib/edoc_api/monetization.ex`
  - Keep business orchestration and return-mode contract for remove flow.
- `lib/edoc_api_web/controllers/companies_controller.ex`
  - Map new domain errors to localized flash messages.
- `lib/edoc_api/document_delivery/public_access_token.ex` (read-only unless helper needed)
  - Token schema reference for revocation query shape.
- `test/edoc_api/monetization_test.exs`
  - Domain behavior tests for branch modes and rollback/conflict paths.
- `test/edoc_api_web/controllers/companies_controller_test.exs`
  - Controller flash/redirect + role guard regressions.
- `priv/gettext/ru/LC_MESSAGES/default.po`
  - RU translations for new remove-member error flashes.
- `priv/gettext/kk/LC_MESSAGES/default.po`
  - KK translations for new remove-member error flashes.

---

## Chunk 1: Domain Offboarding Core

### Task 1: Add failing tests for branch modes and reassignment

**Files:**
- Modify: `test/edoc_api/monetization_test.exs`
- Test: `test/edoc_api/monetization_test.exs`

- [ ] **Step 1: Write failing test for `:company_removed_only` mode**
  - Setup owner + company + active member.
  - Ensure member has cross-company blocker (active membership in a second company).
  - Remove member from first company.
  - Assert:
    - returned mode is `:company_removed_only`;
    - removed-company membership is gone;
    - user row still exists.

- [ ] **Step 1a: Write failing test for `companies.user_id` blocker path**
  - Setup scenario where membership blocker is absent but removed user still owns another company (`companies.user_id == member_user_id`).
  - Remove member from target company.
  - Assert mode remains `:company_removed_only` and user is not deleted.

- [ ] **Step 1c: Write failing test for cross-company invoice/act blocker path**
  - Ensure user still has `invoices.user_id` or `acts.user_id` in another company.
  - Remove from target company.
  - Assert `:company_removed_only`; verify cross-company rows remain untouched.

- [ ] **Step 1b: Write failing test for `tenant_memberships.user_id` blocker**
  - Keep additional membership for same user in another company.
  - Remove from target company.
  - Assert mode `:company_removed_only` and user is not deleted.

- [ ] **Step 2: Run targeted test to confirm failure**
  - Run: `mix test test/edoc_api/monetization_test.exs`
  - Expected: FAIL (mode/behavior not implemented yet).

- [ ] **Step 3: Write failing test for hard-delete branch**
  - Setup owner + company + active member with no global blockers after offboarding.
  - Remove member.
  - Assert:
    - returned mode is `:hard_deleted_user`;
    - user is deleted from `users`;
    - membership no longer exists.

- [ ] **Step 4: Run targeted hard-delete test**
  - Run: `mix test test/edoc_api/monetization_test.exs`
  - Expected: FAIL.

- [ ] **Step 5: Write failing test for reassignment + cleanup**
  - Setup member-owned invoice/act in target company.
  - Create public access tokens by removed user for target-company docs.
  - Remove member.
  - Assert:
    - invoice/act `user_id` changed to owner;
    - removed-user target-company public tokens are revoked/deleted;
    - target-company generated-document cache for removed user removed.
    - negative assertions: same user’s cross-company invoices/acts, generated_documents, and public tokens remain unchanged.

- [ ] **Step 5a: Write failing test for hard-delete global generated-document cleanup**
  - Setup hard-delete-eligible user with additional `generated_documents` row outside target-company docs.
  - Remove member and trigger `:hard_deleted_user` branch.
  - Assert all remaining `generated_documents` rows for deleted user are removed.

- [ ] **Step 5b: Write failing test for hard-delete auth-token cascade cleanup**
  - Create member refresh/email-verification/password-reset token rows.
  - Trigger `:hard_deleted_user`.
  - Assert token rows for deleted user are removed.

- [ ] **Step 5c: Write failing test for best-effort `file_path` cleanup attempt**
  - Create `generated_documents` with non-empty `file_path` for removed user.
  - Trigger hard-delete and assert DB removal succeeds even when file deletion fails.
  - Assert cleanup attempt is observable (via log/assertion helper used in codebase).

- [ ] **Step 6: Run reassignment/cleanup test**
  - Run: `mix test test/edoc_api/monetization_test.exs`
  - Expected: FAIL.

- [ ] **Step 7: Write failing test for invoice number collision rollback**
  - Setup owner and member each with invoice of same `number` in target company.
  - Remove member.
  - Assert:
    - returns `:invoice_number_conflict_on_reassign`;
    - no reassignment happened;
    - membership/user state unchanged (transaction rollback).

- [ ] **Step 7a: Write failing test for `:owner_not_found` rollback**
  - Prepare target company state with missing active owner path.
  - Attempt remove.
  - Assert `:owner_not_found` and unchanged state.

- [ ] **Step 7b: Write failing test for `:reassign_failed` rollback**
  - Force reassignment failure branch (deterministic conflict/failure setup).
  - Assert `:reassign_failed` and full rollback of prior updates.

- [ ] **Step 8: Write failing test for invited/pending soft-remove mode contract**
  - Remove invited membership (no `user_id`).
  - Assert return payload contains `mode: :soft_removed_membership`.
  - Assert seat usage decreases as before.

- [ ] **Step 9: Commit tests**
  - Run:
    - `git add test/edoc_api/monetization_test.exs`
    - `git commit -m "test(monetization): cover company-scoped member offboarding branches"`

### Task 2: Implement offboarding transaction and mode contract

**Files:**
- Modify: `lib/edoc_api/accounts.ex`
- Modify: `lib/edoc_api/monetization.ex`
- Modify (if needed): `lib/edoc_api/documents/generated_document.ex`

- [ ] **Step 1: Implement minimal service in `Accounts`**
  - Add function (example): `offboard_member_from_company(company_id, member_user_id, owner_user_id)`.
  - In one transaction:
    - reassign `invoices` and `acts` in target company to owner;
    - remove target-company membership row for member;
    - revoke/delete removed-user `public_access_tokens` for target-company docs;
    - remove relevant `generated_documents` rows for removed-user target-company docs;
    - compute global blockers (`companies`, `tenant_memberships`, `invoices`, `acts` by `user_id`);
    - if blockers absent: hard delete user + delete all remaining generated_documents for that user;
    - return mode map.
  - Implement post-commit best-effort file cleanup for deleted `generated_documents.file_path` values (log failure, no transaction rollback).
  - Explicitly rely on FK cascade for auth token tables on hard-delete branch and verify with tests.

- [ ] **Step 2: Wire `Monetization.remove_membership/2` to service for active users**
  - Keep `:last_owner` guard.
  - Keep invited/pending path as soft removal mode.
  - Return exact mode payload contract from spec.

- [ ] **Step 3: Run focused monetization tests**
  - Run: `mix test test/edoc_api/monetization_test.exs`
  - Expected: new mode/collision/rollback tests PASS.

- [ ] **Step 3a: Boundary note**
  - Auth outcome (`invalid_credentials` after `:hard_deleted_user`) is verified in Chunk 3, Task 5, Step 1 to keep chunk boundaries focused.

- [ ] **Step 4: Commit domain implementation**
  - Run:
    - `git add lib/edoc_api/accounts.ex lib/edoc_api/monetization.ex test/edoc_api/monetization_test.exs`
    - `git commit -m "feat(monetization): implement company-scoped member offboarding with conditional hard delete"`

---

## Chunk 2: Controller and Localization

### Task 3: Add failing controller tests for new error mapping and success behavior

**Files:**
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 1: Add failing tests for domain-error -> flash mapping**
  - Add cases for:
    - `:owner_not_found`
    - `:reassign_failed`
    - `:invoice_number_conflict_on_reassign`
  - Assert redirect `/company` and localized flash in RU/KK context.

- [ ] **Step 2: Add failing test for active member removal success path**
  - Assert member removed from team list.
  - Assert no unauthorized regression for existing role-guard tests.

- [ ] **Step 3: Run controller test file**
  - Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
  - Expected: FAIL for new mappings before implementation.

- [ ] **Step 4: Commit failing tests**
  - Run:
    - `git add test/edoc_api_web/controllers/companies_controller_test.exs`
    - `git commit -m "test(companies): cover member-offboarding flash mapping and success path"`

### Task 4: Implement controller mapping + gettext entries

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_controller.ex`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`

- [ ] **Step 1: Add error mapping branches in `remove_member`**
  - Map new domain errors to user-friendly messages.
  - Preserve existing redirect behavior.

- [ ] **Step 2: Add RU/KK translations**
  - Add new `msgid` keys used in mapping.
  - Provide clear business wording in both locales.

- [ ] **Step 3: Run controller tests**
  - Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
  - Expected: PASS.

- [ ] **Step 4: Commit controller+i18n**
  - Run:
    - `git add lib/edoc_api_web/controllers/companies_controller.ex priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api_web/controllers/companies_controller_test.exs`
    - `git commit -m "fix(company): localize member-offboarding errors and enforce new remove flow responses"`

---

## Chunk 3: Integration Safety and Final Verification

### Task 5: Add auth/document regressions and run full verification

**Files:**
- Modify (if needed): `test/edoc_api_web/controllers/auth_controller_test.exs`
- Modify (if needed): `test/edoc_api_web/controllers/session_controller_test.exs`
- Modify (if needed): `test/edoc_api/document_delivery_test.exs` or nearest delivery test file

- [ ] **Step 1: Add login-outcome regression tests**
  - Hard-delete branch user cannot authenticate.
  - Company-only branch user authenticates but lacks removed-company access.

- [ ] **Step 2: Add token-revocation regression test**
  - Removed member’s previously shared target-company public link fails resolution.

- [ ] **Step 3: Run focused regressions**
  - Run:
    - `mix test test/edoc_api_web/controllers/auth_controller_test.exs`
    - `mix test test/edoc_api_web/controllers/session_controller_test.exs`
    - `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
    - `mix test test/edoc_api/monetization_test.exs`

- [ ] **Step 4: Run full suite**
  - Run: `mix test`
  - Expected: `0 failures`.

- [ ] **Step 5: Commit verification/regressions**
  - Run:
    - `git add test/edoc_api_web/controllers/auth_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs test/edoc_api_web/controllers/companies_controller_test.exs test/edoc_api/monetization_test.exs`
    - `git commit -m "test(auth,company): verify member-offboarding access and token revocation behavior"`

- [ ] **Step 6: Final implementation commit if remaining files are unstaged**
  - Run:
    - `git add lib/edoc_api/accounts.ex lib/edoc_api/monetization.ex lib/edoc_api_web/controllers/companies_controller.ex priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po`
    - `git commit -m "feat(company): enforce company-scoped member offboarding with conditional account deletion"`

---

## Verification Notes

- Prefer deterministic DB assertions over HTML-only checks for ownership reassignment.
- Keep transactions strict: any failure must preserve pre-operation state.
- Do not change unrelated subscription/seat logic while implementing offboarding.
- Reuse existing fixtures; extend only where needed for multi-company member setup.

## Final Handoff Report (to fill during execution)

- Branch modes observed:
  - `:soft_removed_membership`:
  - `:company_removed_only`:
  - `:hard_deleted_user`:
- Reassignment validated for:
  - invoices:
  - acts:
- Cleanup validated for:
  - generated_documents:
  - public_access_tokens:
- Full test result:
  - command:
  - summary:
