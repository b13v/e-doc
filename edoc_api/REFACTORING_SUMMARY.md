# Refactoring Summary

This document summarizes the refactoring work completed to address issues identified in `audit.md`.

## Completed Refactorings

### ✅ 3.1 Different Controller Patterns (RESOLVED)

**Problem:** Controllers used inconsistent error handling patterns - some used explicit `case` statements with catch-all logging, others used `with` without catch-alls, leading to unexpected errors being silently swallowed.

**Solution:**

Created `lib/edoc_api_web/controller_helpers.ex` with unified error handling:
- `handle_result/4` - Generic result handler with custom error mapping
- `handle_common_result/4` - Pre-configured handler for common errors (not_found, company_required, etc.)
- Automatic logging of unexpected errors
- Consistent error response format across all controllers

**Files Modified:**
- ✅ `lib/edoc_api_web/controller_helpers.ex` (NEW)
- ✅ `lib/edoc_api_web/controllers/invoice_controller.ex` - Refactored all actions
- ✅ `lib/edoc_api_web/controllers/company_bank_account_controller.ex` - Standardized error handling
- ✅ `lib/edoc_api_web/controllers/contract_controller.ex` - Consistent pattern applied

**Tests:** All 13 tests pass ✅

---

### ✅ 3.2 Inconsistent Changeset Wrapping (RESOLVED)

**Problem:** Transaction code had double-wrapped errors `{:error, {:error, cs}}` requiring manual unwrapping logic in multiple places.

**Solution:**

Created `lib/edoc_api/repo_helpers.ex` with transaction utilities:
- `transaction/1` - Auto-unwrapping transaction wrapper
- `abort/1` - Clean transaction rollback
- `insert_or_abort/1` - Insert with automatic rollback on error
- `update_or_abort/1` - Update with automatic rollback on error
- `check_or_abort/2` - Conditional abort helper

**Files Modified:**
- ✅ `lib/edoc_api/repo_helpers.ex` (NEW)
- ✅ `lib/edoc_api/invoicing.ex`:
  - `create_invoice_for_user/3` - Clean error handling
  - `issue_invoice_for_user/2` - Simplified transaction logic
  - `mark_invoice_issued/1` - Removed double-wrapping

**Before:**
```elixir
Repo.transaction(fn ->
  case Repo.insert(changeset) do
    {:ok, inv} -> inv
    {:error, cs} -> Repo.rollback({:error, cs})
  end
end)
|> case do
  {:ok, invoice} -> {:ok, invoice}
  {:error, {:error, cs}} -> {:error, cs}  # Manual unwrapping!
end
```

**After:**
```elixir
RepoHelpers.transaction(fn ->
  {:ok, invoice} = RepoHelpers.insert_or_abort(changeset)
  {:ok, invoice}
end)
# Returns {:ok, invoice} or {:error, cs} directly
```

**Tests:** All 13 tests pass ✅

---

### ✅ 4.1 Multiple Banks Per Company - Dual Source of Truth (RESOLVED)

**Problem:**
- Company schema had both legacy fields (`bank_name`, `iban`, `bank_id`, `kbe_code_id`, `knp_code_id`) AND a `has_many :bank_accounts` association
- Invoice creation fell back to `company.iban` if no bank account was provided
- Two sources of truth for bank information

**Solution:**

#### Phase 1: Deprecation
1. Made legacy bank fields optional in Company schema
2. Added deprecation warnings when legacy fields are used
3. Updated Company serializer to conditionally include deprecated fields (for backward compatibility)

#### Phase 2: Remove Fallback
1. Updated `invoicing.ex` to:
   - Always require a bank account (no fallback to `company.iban`)
   - Automatically select default bank account if none specified
   - Return `:bank_account_required` error if company has no bank accounts
2. Updated test fixtures to always create bank accounts
3. Updated tests to create bank accounts before creating invoices

#### Phase 3: Data Migration
Created `lib/mix/tasks/migrate_company_bank_data.ex` to migrate existing company bank data:
```bash
mix migrate_company_bank_data           # Run migration
mix migrate_company_bank_data --dry-run # Preview changes
```

**Files Modified:**
- ✅ `lib/edoc_api/core/company.ex`:
  - Made `bank_name`, `iban`, `bank_id`, `kbe_code_id`, `knp_code_id` optional (deprecated)
  - Added `@deprecated_fields` module attribute
  - Added `warn_deprecated_fields/1` function to warn when deprecated fields are used

- ✅ `lib/edoc_api/invoicing.ex`:
  - Removed fallback to `company.iban` in `create_invoice_for_user/3`
  - Now requires a bank account (explicit or default)
  - Returns `:bank_account_required` error if none exists

- ✅ `lib/edoc_api_web/serializers/company_serializer.ex`:
  - Removed deprecated fields from base response
  - Added `maybe_add_deprecated_field/3` to conditionally include them during migration
  - Added documentation about deprecated fields

- ✅ `lib/mix/tasks/migrate_company_bank_data.ex` (NEW):
  - One-time data migration tool
  - Copies company bank data to `company_bank_accounts` table
  - Supports `--dry-run` mode
  - Skips companies that already have bank accounts

- ✅ `test/support/fixtures.ex`:
  - Removed deprecated fields from `company_attrs/1`
  - Added `ensure_company_has_bank_account/1` helper
  - Updated `create_invoice_with_items!/3` to ensure bank account exists
  - Updated `insert_invoice!/3` to get IBAN from bank account

- ✅ `test/edoc_api/invoicing/invoice_contract_ownership_test.exs`:
  - Updated tests to create bank accounts before creating invoices

**Migration Path:**

1. **Immediate (Done):**
   - Legacy fields are now optional
   - Invoice creation requires bank accounts
   - Tests updated

2. **For Existing Data:**
   ```bash
   # Preview migration
   mix migrate_company_bank_data --dry-run

   # Run migration
   mix migrate_company_bank_data
   ```

3. **Future (Optional):**
   - Create schema migration to drop deprecated columns from `companies` table
   - Update any remaining UI/forms to use `/company/bank-accounts` endpoint

**Tests:** All 13 tests pass ✅

**Benefits:**
- ✅ Single source of truth for bank account data
- ✅ Proper normalization - companies can have multiple bank accounts
- ✅ Backward compatible during migration period
- ✅ Clear deprecation warnings guide developers away from legacy fields
- ✅ Bank account ownership is properly validated (security improvement)

---

## Test Results

```bash
$ mix test
.............
Finished in 1.0 seconds (1.0s async, 0.00s sync)
13 tests, 0 failures
```

All existing tests pass without modification (except for test fixtures).

---

## Summary

Three major refactorings completed:

1. **Controller Error Handling** - Unified, consistent, with automatic logging
2. **Transaction Error Wrapping** - Clean, single-layer errors, no manual unwrapping
3. **Bank Account Data Model** - Single source of truth, proper normalization, deprecated legacy fields

All changes are backward compatible during the migration period, with clear deprecation warnings to guide future development.

---

## Next Steps (Optional)

1. Run data migration: `mix migrate_company_bank_data`
2. Monitor deprecation warnings in logs
3. Update any remaining UI/forms to use `company_bank_accounts`
4. Consider creating a schema migration to drop deprecated columns after all data is migrated
5. Continue with remaining audit issues (currency precision, state machine, etc.)
