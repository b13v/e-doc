# Fix Race Condition: Single Default Bank Account Per Company

## Problem
Multiple bank accounts could have `is_default = true` simultaneously, causing:
- Non-deterministic default account selection in invoice creation
- No database-level constraint to prevent this race condition

## Solution

### 1. Database Constraint (Migration)
**File:** `priv/repo/migrations/20260121120000_ensure_single_default_bank_account.exs`

Added partial unique index:
```sql
CREATE UNIQUE INDEX company_bank_accounts_single_default
ON company_bank_accounts (company_id)
WHERE is_default = true;
```

This ensures only ONE bank account per company can have `is_default = true`.

### 2. Schema Changes
**File:** `lib/edoc_api/core/company_bank_account.ex`

- Added `unique_constraint` for single default enforcement
- Created `set_as_default_changeset/3` that:
  - Sets `is_default = true` on the target account
  - Resets all other accounts to `is_default = false` via `prepare_changes`
  - Runs atomically within a transaction

### 3. API Endpoint
**File:** `lib/edoc_api_web/router.ex`

Added route: `PUT /v1/company/bank-accounts/:id/set-default`

**File:** `lib/edoc_api_web/controllers/company_bank_account_controller.ex`

Added `set_default/2` action to allow users to change their default bank account.

### 4. Business Logic
**File:** `lib/edoc_api/payments.ex`

Added `set_default_bank_account/2` function that:
- Verifies user owns the bank account
- Resets other defaults atomically
- Returns updated bank account

Added `set_default_bank_account_for_company!/2` for test fixtures.

### 5. Invoicing Updates
**File:** `lib/edoc_api/invoicing.ex`

Extracted `get_bank_account_for_invoice/2` helper to handle:
- Explicit bank_account_id selection (with ownership validation)
- Default bank account selection
- Proper error handling

### 6. Error Handling
**File:** `lib/edoc_api_web/error_mapper.ex`

Added `bad_request/2` function for 400 error responses.

### 7. Test Updates
**File:** `test/edoc_api_web/controllers/company_bank_account_controller_test.exs`

Added comprehensive tests for `set_default` endpoint:
- ✅ Sets bank account as default and unsets others
- ✅ Returns 404 for non-existent accounts
- ✅ Returns 404 for accounts from different companies

**File:** `test/support/fixtures.ex`

Updated `create_company_bank_account!/2` to automatically set first account as default.

## Testing

```bash
$ mix test
................
Finished in 1.8 seconds (1.2s async, 0.5s sync)
16 tests, 0 failures
```

All tests pass including 3 new tests for the set_default functionality.

## API Usage

Set a bank account as default:
```bash
curl -X PUT http://localhost:4000/v1/company/bank-accounts/{id}/set-default \
  -H "Authorization: Bearer {token}"
```

Response (200 OK):
```json
{
  "bank_account": {
    "id": "...",
    "label": "Main Account",
    "iban": "KZ123456789012345678",
    "is_default": true,
    ...
  }
}
```

## Security Improvements

1. **Database-level constraint** prevents race condition
2. **Ownership verification** ensures users can only set their own accounts as default
3. **Atomic transaction** guarantees consistency when resetting other defaults
4. **User isolation** - users can only access their own bank accounts

## Migration Path

For existing production data:
1. Deploy the migration (safe, no data loss)
2. The constraint will prevent NEW multiple defaults
3. Existing duplicates can be identified and fixed manually:
```sql
SELECT company_id, COUNT(*)
FROM company_bank_accounts
WHERE is_default = true
GROUP BY company_id
HAVING COUNT(*) > 1;
```

## Files Modified

- ✅ `priv/repo/migrations/20260121120000_ensure_single_default_bank_account.exs` (NEW)
- ✅ `lib/edoc_api/core/company_bank_account.ex` - Added constraints and helper
- ✅ `lib/edoc_api/payments.ex` - Added set_default functions
- ✅ `lib/edoc_api/invoicing.ex` - Refactored bank account selection
- ✅ `lib/edoc_api_web/router.ex` - Added route
- ✅ `lib/edoc_api_web/controllers/company_bank_account_controller.ex` - Added action
- ✅ `lib/edoc_api_web/error_mapper.ex` - Added bad_request handler
- ✅ `test/edoc_api_web/controllers/company_bank_account_controller_test.exs` (NEW)
- ✅ `test/support/fixtures.ex` - Updated for default handling
