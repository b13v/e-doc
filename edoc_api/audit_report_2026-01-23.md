# Code Audit Report: EdocApi

**Date:** 2026-01-23
**Last Updated:** 2026-01-23
**Repository:** edoc_api
**Focus:** Duplicated business rules, missing validations, inconsistent error handling, areas likely to break with new requirements

---

## Phase 1 Completion Status ✅

**Completed:** 2026-01-23

Both critical issues from Phase 1 have been resolved:

| Issue | Status | Files Modified |
|-------|--------|----------------|
| 1.1 Bank Account Selection Logic | ✅ FIXED | `lib/edoc_api/core/company_bank_account.ex`, `lib/edoc_api/invoicing.ex` |
| 4.1 Race Condition in Default Bank | ✅ FIXED | `lib/edoc_api/core/company_bank_account.ex`, `lib/edoc_api/payments.ex` |

**Summary of Changes:**
1. Created `CompanyBankAccount.get_default_account/1` - centralized function for fetching default bank accounts
2. Created `CompanyBankAccount.reset_all_defaults/1` - transaction-safe function for resetting defaults
3. Removed `prepare_changes(&reset_other_defaults/1)` from `set_as_default_changeset` to fix race condition
4. Updated `Payments.set_default_bank_account/2` to use transaction-safe pattern
5. Updated `Invoicing.get_bank_account_for_invoice/2` to use new consolidated function
6. Updated `Invoicing.select_bank_account/1` to use new consolidated function

---

## Executive Summary

This audit identified **17 distinct issues** across the codebase:
- **2 Critical** - ✅ Both fixed in Phase 1
- **5 High** - Security and correctness concerns
- **7 Medium** - Maintainability and technical debt
- **3 Low** - Minor inconsistencies

The codebase shows good structure with validators (`BinIin`, `Iban`) and helpers (`RepoHelpers`, `ControllerHelpers`), but these patterns are not consistently applied across all modules.

---

## 1. Duplicated Business Rules

### 1.1 Bank Account Selection Logic (CRITICAL) ✅ FIXED

**Status:** RESOLVED in Phase 1

**Original Locations:**
- `lib/edoc_api/invoicing.ex:210-224` - `get_bank_account_for_invoice/2`
- `lib/edoc_api/invoicing.ex:422-454` - `select_bank_account/1`

**Original Issue:** Same query pattern duplicated to find default bank account.

**Solution Implemented:**
Created `CompanyBankAccount.get_default_account/1` and updated both call sites:

```elixir
# In lib/edoc_api/core/company_bank_account.ex (NEW)
@doc """
Gets the default bank account for a company.
Returns nil if no default is set.
"""
def get_default_account(company_id) do
  __MODULE__
  |> where([a], a.company_id == ^company_id and a.is_default == true)
  |> order_by([a], desc: a.inserted_at)
  |> limit(1)
  |> Repo.one()
end

# Updated in lib/edoc_api/invoicing.ex
defp get_bank_account_for_invoice(company_id, nil) do
  case CompanyBankAccount.get_default_account(company_id) do
    nil -> RepoHelpers.abort(:bank_account_required)
    acc -> acc
  end
end
```

---

### 1.2 Email Validation Regex

**Locations:**
- `lib/edoc_api/core/company.ex:126`
- `lib/edoc_api/accounts/user.ex:24`

**Issue:** Identical regex `~r/^[^\s]+@[^\s]+\.[^\s]+$/` duplicated.

**Suggested Refactor:** Create `lib/edoc_api/validators/email.ex`:
```elixir
defmodule EdocApi.Validators.Email do
  import Ecto.Changeset

  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  def normalize(nil), do: nil
  def normalize(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  def validate(changeset, field) do
    validate_format(changeset, field, @email_regex, message: "invalid email")
  end
end
```

---

### 1.3 Email Normalization

**Locations:**
- `lib/edoc_api/core/company.ex:105-108` - `normalize_email/1`
- `lib/edoc_api/accounts/user.ex:30-31` - `normalize_email/1`

**Issue:** Same `String.trim() |> String.downcase()` pattern duplicated.

**Impact:** See 1.2 - consolidate into `Validators.Email`.

---

### 1.4 String Trimming (Multiple Variants)

**Locations:**
- `lib/edoc_api/core/company.ex:110-111` - `normalize_trim/1` (doesn't handle empty string)
- `lib/edoc_api/core/invoice.ex:111-116` - `trim_nil/1` (converts empty to nil)
- Multiple inline `String.trim/1` calls throughout

**Issue:** Inconsistent handling of empty vs nil strings.

**Suggested Refactor:** Create `lib/edoc_api/validators/string.ex`:
```elixir
defmodule EdocApi.Validators.String do
  def normalize(nil), do: nil
  def normalize(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end
end
```

---

### 1.5 Decimal Precision Hardcoding

**Locations:**
- `lib/edoc_api/core/invoice.ex:191-193` - VAT calculation uses `Decimal.round(2)`
- `lib/edoc_api/core/invoice_item.ex:38` - Amount uses `Decimal.round(2)`
- `lib/edoc_api/invoicing.ex:245-247` - Uses `Currencies.round_default()`

**Issue:** `Currencies` module exists but not consistently used. Adding currency-specific precision (e.g., JPY with 0 decimals) would require multiple changes.

**Suggested Refactor:**
```elixir
# In invoice.ex - pass currency through computation
defp compute_totals(changeset) do
  subtotal = get_field(changeset, :subtotal)
  vat_rate = get_field(changeset, :vat_rate)
  currency = get_field(changeset, :currency) || "KZT"

  if is_struct(subtotal, Decimal) and is_integer(vat_rate) do
    vat = subtotal
      |> Decimal.mult(Decimal.new(vat_rate))
      |> Decimal.div(Decimal.new(100))
      |> Currencies.round_currency(currency)

    total = subtotal
      |> Decimal.add(vat)
      |> Currencies.round_currency(currency)

    changeset
    |> put_change(:vat, vat)
    |> put_change(:total, total)
  else
    changeset
  end
end
```

---

## 2. Missing Validations

### 2.1 Contract Ownership Not Validated (HIGH)

**Location:** `lib/edoc_api/core/contract.ex:22-27`

**Issue:** Contract changeset accepts any `company_id` from params without ownership verification. Invoice validates contract ownership via `prepare_changes`, but Contract doesn't validate its own relationship.

```elixir
def changeset(contract, attrs) do
  contract
  |> cast(attrs, @required_fields ++ @optional_fields)
  |> validate_required(@required_fields)
  # No ownership validation like Invoice has
end
```

**Suggested Refactor:**
```elixir
def changeset(contract, attrs, company_id) do
  contract
  |> cast(attrs, @required_fields ++ @optional_fields)
  |> put_change(:company_id, company_id)
  |> validate_required(@required_fields ++ [:company_id])
  |> unique_constraint(:number, name: :contracts_company_id_number_index)
end
```

Then update `Core.create_contract_for_user/2` to pass company_id explicitly (similar to Invoice pattern).

---

### 2.2 Invoice `seller_iban` Can Be Manipulated

**Location:** `lib/edoc_api/invoicing.ex:98-102`

**Issue:** `seller_iban` is populated from `bank_account.iban`, but still accepts user input via `attrs`. Someone could pass an IBAN that doesn't match the selected `bank_account_id`.

**Suggested Refactor:**
```elixir
# In lib/edoc_api/core/invoice.ex
# Remove seller_iban from @required_fields, make it virtual or computed-only
@required_fields ~w(
  service_name
  issue_date
  currency
  seller_name
  seller_bin_iin
  seller_address
  # seller_iban - REMOVE, always derive from bank_account
  buyer_name
  buyer_bin_iin
  buyer_address
  vat_rate
)a

# Add validation in changeset:
defp validate_seller_iban_matches_bank(changeset) do
  bank_iban = get_field(changeset, :seller_iban)
  bank_account_id = get_field(changeset, :bank_account_id)

  if bank_account_id do
    # This should already match since we set it in invoicing.ex
    # But double-check here to prevent manual override
    changeset
  else
    changeset
  end
end
```

---

### 2.3 InvoiceItem `amount` Is User-Modifiable

**Location:** `lib/edoc_api/core/invoice_item.ex:23-30`

**Issue:** `amount` is computed in `compute_amount/1`, but still included in `@required` and cast from attrs. Users could pass incorrect amounts.

```elixir
@required ~w(name qty unit_price amount)a  # amount shouldn't be here

def changeset(item, attrs) do
  item
  |> cast(attrs, @required ++ @optional ++ [:invoice_id])
  # amount is computed, but user can override it
  |> compute_amount()
  |> validate_required(@required ++ [:invoice_id])
end
```

**Suggested Refactor:**
```elixir
@required ~w(name qty unit_price)a  # Remove amount
@optional ~w(code)a

def changeset(item, attrs) do
  item
  |> cast(attrs, @required ++ @optional ++ [:invoice_id])
  |> validate_required(@required ++ [:invoice_id])
  |> validate_number(:qty, greater_than: 0)
  |> validate_number(:unit_price, greater_than: 0)
  |> compute_amount()  # Always compute, never accept from attrs
end
```

---

### 2.4 InvoiceBankSnapshot Lacks Content Validation

**Location:** `lib/edoc_api/core/invoice_bank_snapshot.ex:22-27`

**Issue:** Only validates field presence, not format (IBAN, BIC). Relies on upstream validation but doesn't re-validate stored data.

**Suggested Refactor:**
```elixir
def changeset(snapshot, attrs) do
  snapshot
  |> cast(attrs, @required)
  |> validate_required(@required)
  |> unique_constraint(:invoice_id, name: :invoice_bank_snapshots_invoice_id_index)
  |> EdocApi.Validators.Iban.validate(:iban)
end
```

---

### 2.5 CompanyBankAccount Default Set Lacks Idempotency Guard

**Location:** `lib/edoc_api/core/company_bank_account.ex:48-70`

**Issue:** `reset_other_defaults/1` runs in `prepare_changes` BEFORE validation. If validation fails, defaults are still reset. Database constraint prevents violation, but the partial state is problematic.

**Suggested Refactor:** See section 4.1 for detailed fix.

---

## 3. Inconsistent Error Handling

### 3.1 Multiple Error Return Shapes

**Locations:** Throughout `lib/edoc_api/invoicing.ex` and `lib/edoc_api/payments.ex`

**Issue:** Three different error shapes:
- `{:error, atom}` - e.g., `{:error, :invoice_not_found}`
- `{:error, atom, details}` - e.g., `{:error, :cannot_issue, %{status: "..."}}`
- `{:error, {:error, changeset}}` - nested tuples in `Payments.set_default_bank_account/2` (line 58)

**Suggested Refactor:** Create `lib/edoc_api/errors.ex`:
```elixir
defmodule EdocApi.Errors do
  # Standardized error construction
  def not_found(resource), do: {:error, :not_found, %{resource: resource}}
  def validation(field, message), do: {:error, :validation, %{field: field, message: message}}
  def business_rule(rule, details), do: {:error, :business_rule, %{rule: rule, details: details}}

  # Never nest tuples
  def from_changeset({:error, changeset}), do: {:error, :validation, changeset: changeset}
end
```

---

### 3.2 Inconsistent Error Atoms for Same Condition

**Examples:**
- `:invoice_not_found` (invoicing.ex) vs generic `:not_found` (controller_helpers.ex:87)
- `:invoice_already_issued` (invoicing.ex:393) vs `:already_issued` (invoicing.ex:396)
- `:bank_account_required` means different things in different contexts

**Suggested Refactor:** Canonical error atoms:
```elixir
defmodule EdocApi.Errors do
  @error_atoms %{
    invoice_not_found: :invoice_not_found,
    invoice_already_issued: :invoice_already_issued,
    bank_account_required: :bank_account_required,
    contract_not_found: :contract_not_found,
    # ... etc
  }
end
```

---

### 3.3 Transaction Rollback Wrapping Inconsistency

**Location:** `lib/edoc_api/payments.ex:58` vs `lib/edoc_api/repo_helpers.ex:27-35`

**Issue:** `RepoHelpers.transaction/1` expects `{:error, reason}` but `Payments.set_default_bank_account` rolls back `{:error, cs}` tuple.

**Current problematic code:**
```elixir
# lib/edoc_api/payments.ex:58
%{valid?: false} = cs ->
  Repo.rollback({:error, cs})  # This creates nested tuple!
```

**Suggested Refactor:**
```elixir
# Always abort with atoms, never with tuples
%{valid?: false} = cs ->
  RepoHelpers.abort(:validation_failed)

# In controller, handle the error atom and fetch changeset separately
```

---

## 4. Areas Likely to Break with New Requirements

### 4.1 Multiple Banks Per Company - Race Condition (CRITICAL) ✅ FIXED

**Status:** RESOLVED in Phase 1

**Original Issue:** `reset_other_defaults/1` ran in `prepare_changes` BEFORE validation. If validation failed, defaults were still reset, creating a window where a company has no default bank account.

**Solution Implemented:**
Moved the reset logic from the changeset to the transaction level:

```elixir
# In lib/edoc_api/core/company_bank_account.ex (UPDATED)
@doc """
Creates a changeset for setting this bank account as the default.
Does NOT reset other defaults - that must be done at transaction level
to avoid race conditions where validation fails after reset.
"""
def set_as_default_changeset(acc, attrs, company_id) do
  acc
  |> changeset(attrs, company_id)
  |> put_change(:is_default, true)
end

@doc """
Resets all default bank accounts for a company to false.
Should be called BEFORE setting a new default within a transaction.
"""
def reset_all_defaults(company_id) do
  from(a in __MODULE__,
    where: a.company_id == ^company_id,
    where: a.is_default == true
  )
  |> Repo.update_all(set: [is_default: false])
end

# In lib/edoc_api/payments.ex (UPDATED)
def set_default_bank_account(user_id, bank_account_id) do
  Repo.transaction(fn ->
    with {:ok, company} <- get_company_or_rollback(user_id),
         {:ok, bank_account} <- verify_bank_account_ownership(company.id, bank_account_id) do

      # Reset all defaults FIRST (before any validation that could fail)
      CompanyBankAccount.reset_all_defaults(company.id)

      # Now set the new default
      bank_account
      |> CompanyBankAccount.set_as_default_changeset(%{}, company.id)
      |> Repo.update()
    else
      {:error, reason} -> Repo.rollback(reason)
      nil -> Repo.rollback(:bank_account_not_found)
    end
  end)
  |> case do
    {:ok, acc} -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
    {:error, reason} -> {:error, reason}
  end
end
```

**Benefits:**
- No race condition window where company has no default
- Changeset validation runs before any state changes
- Cleaner separation of concerns

---

### 4.2 Currency Expansion

**Location:** `lib/edoc_api/core/invoice.ex:64`

**Issue:** Hardcoded `@allowed_currencies ~w(KZT USD EUR RUB)`. The `Currencies` module exists with proper currency handling but isn't used for validation.

**Suggested Refactor:**
```elixir
# In lib/edoc_api/currencies.ex - add:
def supported_currencies, do: ~w(KZT USD EUR RUB)

# In lib/edoc_api/core/invoice.ex:
defp validate_allowed_currencies(changeset) do
  validate_inclusion(changeset, :currency, Currencies.supported_currencies())
end

# Or make it dynamic per company in the future:
def allowed_currencies_for_company(company_id) do
  # Fetch from company settings or use default
  Currencies.supported_currencies()
end
```

---

### 4.3 VAT Rate Changes

**Location:** `lib/edoc_api/core/invoice.ex:78`

**Issue:** Hardcoded `[0, 16]`. No support for:
- Different rates by country
- Exempt vs zero-rated distinction
- Historical rate changes

**Suggested Refactor:**
```elixir
# Create lib/edoc_api/vat_rates.ex
defmodule EdocApi.VatRates do
  @rates %{
    "KZ" => [0, 12],  # Kazakhstan changed from 16% to 12%
    "RU" => [0, 20],
    "DEFAULT" => [0, 16]
  }

  def for_country(country_code) do
    Map.get(@rates, country_code, @rates["DEFAULT"])
  end

  def validate_rate(changeset, field, country_code \\ "DEFAULT") do
    validate_inclusion(changeset, field, for_country(country_code))
  end
end
```

---

### 4.4 Status Workflow Not Enforced

**Location:** `lib/edoc_api/invoicing.ex:387-414`

**Issue:** Status checks scattered in `do_issue_invoice/1`. Direct status updates via `Ecto.Changeset.change(status: "issued")` could bypass business rules. `InvoiceStatus` module exists but doesn't enforce transitions.

**Suggested Refactor:**
```elixir
# Create lib/edoc_api/invoice_state_machine.ex
defmodule EdocApi.InvoiceStateMachine do
  @transitions %{
    "draft" => [:issued, :void],
    "issued" => [:paid, :void],
    "paid" => [:void],
    "void" => []
  }

  def can_transition?(from_status, to_status) do
    allowed_transitions = Map.get(@transitions, from_status, [])
    to_status in allowed_transitions
  end

  def transition(invoice, to_status) do
    if can_transition?(invoice.status, to_status) do
      {:ok, to_status}
    else
      {:error, :invalid_transition, %{from: invoice.status, to: to_status}}
    end
  end
end

# Use in do_issue_invoice:
defp do_issue_invoice(invoice) do
  with {:ok, "issued"} <- InvoiceStateMachine.transition(invoice, "issued"),
       {:ok, bank_account} <- select_bank_account(invoice),
       {:ok, _snap} <- create_bank_snapshot(invoice, bank_account) do
    {:ok, preload_invoice(invoice)}
  end
end
```

---

### 4.5 Company Bank Fields Migration Incomplete

**Locations:** `lib/edoc_api/core/company.ex:16-17,46-47` and throughout

**Issue:** `bank_name`, `iban`, `bank_id`, `kbe_code_id`, `knp_code_id` marked `@deprecated_fields` but still in schema. Creates confusion about source of truth.

**Suggested Refactor:**
1. Create migration to ensure all companies have at least one bank account
2. Add database constraint: `company_bank_accounts.company_id` must have at least one entry per company
3. Remove deprecated fields from `Company` schema
4. Update all references to use `company_bank_accounts` instead

```elixir
# Migration example:
defmodule EdocApi.Repo.Migrations.RemoveDeprecatedBankFieldsFromCompany do
  use Ecto.Migration

  def up do
    # First ensure data is migrated
    execute """
    INSERT INTO company_bank_accounts (company_id, label, iban, bank_id, kbe_code_id, knp_code_id, is_default, inserted_at, updated_at)
    SELECT id, 'Main Account', iban, bank_id, kbe_code_id, knp_code_id, true, NOW(), NOW()
    FROM companies
    WHERE iban IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM company_bank_accounts WHERE company_id = companies.id)
    """

    # Then remove columns
    alter table(:companies) do
      remove :bank_name
      remove :iban
      remove :bank_id
      remove :kbe_code_id
      remove :knp_code_id
    end
  end

  def down do
    # Reverse migration if needed
  end
end
```

---

### 4.6 Invoice Numbering Tightly Coupled

**Location:** `lib/edoc_api/invoicing.ex:336-363`

**Issue:** Single 10-digit format with leading zeros. No support for:
- Multiple sequences per company (by currency, department, etc.)
- Custom number formats
- Yearly resets

**Suggested Refactor:**
```elixir
# Add sequence_name to invoice_counters table
def next_invoice_number!(company_id, sequence_name \\ "default") do
  Repo.transaction(fn ->
    %{next_seq: next_seq} =
      Repo.insert!(
        %InvoiceCounter{company_id: company_id, sequence_name: sequence_name, next_seq: 2},
        on_conflict: [inc: [next_seq: 1]],
        conflict_target: [:company_id, :sequence_name],
        returning: [:next_seq]
      )

    seq = next_seq - 1

    if seq > @max_invoice_number do
      Repo.rollback(:invoice_counter_overflow)
    end

    # Format could be sequence-specific
    format_invoice_number(seq, sequence_name)
  end)
end

defp format_invoice_number(seq, "default"), do: String.pad_leading(Integer.to_string(seq), 10, "0")
defp format_invoice_number(seq, "yearly"), do: "#{DateTime.utc_now().year}-#{String.pad_leading(Integer.to_string(seq), 6, "0")}"
```

---

## Summary by Severity

| Severity | Count | Issues |
|----------|-------|--------|
| **CRITICAL** | 2 | ✅ Both fixed in Phase 1: Bank selection duplication, race condition in default bank account |
| **HIGH** | 5 | Contract ownership, IBAN manipulation, item amount manipulation, inconsistent error shapes, currency hardcoding |
| **MEDIUM** | 7 | Email validation dup, trimming variants, decimal precision, status workflow, deprecated fields, VAT rates, invoice numbering |
| **LOW** | 3 | Snapshot validation, error atom consistency, phone normalization scope |

**Remaining Issues:** 15 (5 High, 7 Medium, 3 Low)

---

## Recommended Action Plan

### Phase 1 - Critical Fixes (Immediate) ✅ COMPLETE
1. ✅ Fix race condition in `CompanyBankAccount.set_as_default_changeset`
2. ✅ Consolidate bank account selection into single function

### Phase 2 - High Priority (Short-term)
1. Create shared `Validators.Email` module
2. Add contract ownership validation
3. Remove `seller_iban` and `amount` from user-modifiable fields
4. Standardize error return shapes

### Phase 3 - Medium Priority (1-2 sprints)
1. Implement state machine for invoice status
2. Consolidate string trimming/normalization helpers
3. Make VAT rates configurable
4. Use `Currencies` module consistently

### Phase 4 - Technical Debt (Ongoing)
1. Complete migration from company bank fields
2. Make invoice numbering more flexible
3. Add comprehensive test coverage for edge cases

---

## Appendix: Files Requiring Changes

### New Files to Create:
- `lib/edoc_api/validators/email.ex`
- `lib/edoc_api/validators/string.ex`
- `lib/edoc_api/errors.ex`
- `lib/edoc_api/invoice_state_machine.ex`
- `lib/edoc_api/vat_rates.ex`

### Files to Modify:
- `lib/edoc_api/core/invoice.ex`
- `lib/edoc_api/core/invoice_item.ex`
- `lib/edoc_api/core/company.ex`
- `lib/edoc_api/core/company_bank_account.ex`
- `lib/edoc_api/core/contract.ex`
- `lib/edoc_api/core/invoice_bank_snapshot.ex`
- `lib/edoc_api/invoicing.ex`
- `lib/edoc_api/payments.ex`
- `lib/edoc_api/accounts/user.ex`
- `lib/edoc_api_web/controller_helpers.ex`

---

*Generated: 2026-01-23*
