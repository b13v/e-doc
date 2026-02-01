# EdocApi Risk Audit Report

## 1. Duplicated Business Rules

### 1.1 Item Amount Calculation Logic ✅ DONE

**Location:** `lib/edoc_api/core/invoice_item.ex:33-46` and `lib/edoc_api/core/contract_item.ex:58-73`

**Issue:** Both modules implement nearly identical `compute_amount/1` functions but with subtle differences:

- `InvoiceItem` checks `is_integer(qty)`
- `ContractItem` uses `parse_decimal/1` helper for qty
- Different rounding behavior

**Risk:** Maintenance burden, inconsistent behavior between invoices and contracts.

**Resolution:** Created `lib/edoc_api/calculations/item_calculation.ex` with shared logic:

- `compute_amount/2` - handles integer, decimal, and string qty types
- `compute_amount_changeset/1` - changeset helper for automatic calculation
- Both `InvoiceItem` and `ContractItem` now use the shared module

---

### 1.2 VAT Rate Validation ✅ DONE

**Location:** `lib/edoc_api/core/contract.ex:100` and `lib/edoc_api/vat_rates.ex:32-38`

**Issue:** Contract schema hardcoded `[0, 12, 16]` for VAT rates but Kazakhstan only uses 16% (and 0%) since 2026. The 12% rate was outdated.

**Risk:** Inconsistent VAT validation - contracts could use 12% which is no longer valid in Kazakhstan.

**Resolution:**

- Removed 12% from contract validation
- Changed to use `VatRates.validate_rate(:vat_rate, "KZ")` which correctly validates `[0, 16]`
- Also updated currency validation to use `Currencies.supported_currencies()` for consistency

---

### 1.3 Currency Validation ✅ DONE

**Location:** `lib/edoc_api/core/contract.ex:99` and `lib/edoc_api/core/invoice.ex:83`, `lib/edoc_api/currencies.ex:13`

**Issue:** Both schemas supported multiple currencies (`~w(KZT USD EUR RUB)`), but the application only operates in Kazakhstan and should only use KZT (Kazakhstani Tenge). Having multiple currencies adds unnecessary complexity.

**Risk:**

- Unnecessary complexity for a Kazakhstan-only system
- Potential currency conversion issues
- Inconsistent currency validation between Contract and Invoice schemas

**Resolution:**

- Changed `Currencies.supported_currencies()` to return only `["KZT"]`
- Updated both Contract and Invoice schemas to use `Currencies.supported_currencies()` consistently
- Removed precision definitions for USD, EUR, RUB from the Currencies module

```elixir
# Before: @supported_currencies ~w(KZT USD EUR RUB)
# After:
@supported_currencies ~w(KZT)

# Both schemas now use:
|> validate_inclusion(:currency, Currencies.supported_currencies())
```

---

### 1.4 Overlapping but Non-Equivalent Status Checks

**Location:** `lib/edoc_api/invoicing.ex:503-507`

**Issue:** Two different checks for "already issued" that are NOT equivalent:

```elixir
not is_nil(invoice.bank_snapshot) -> {:error, :already_issued}
InvoiceStatus.is_issued?(invoice) -> {:error, :already_issued}
```

**Why They Are Different:**

| Check                               | Validates                 | Source of Truth                |
| ----------------------------------- | ------------------------- | ------------------------------ |
| `not is_nil(invoice.bank_snapshot)` | Database record existence | `invoice_bank_snapshots` table |
| `InvoiceStatus.is_issued?(invoice)` | Status field value        | `invoices.status` column       |

**Risk:**

- Both return the SAME error (`:already_issued`), making debugging difficult
- Data inconsistency possible: invoice could have `status: "issued"` but no snapshot, or vice versa
- Unclear which check failed when debugging production issues

**Suggested Refactor:**

Use distinct error messages for each validation layer:

```elixir
# Business logic - status is the canonical state
InvoiceStatus.is_issued?(invoice) ->
  {:error, :already_issued}

# Data integrity - separate concern with distinct error
not is_nil(invoice.bank_snapshot) ->
  {:error, :snapshot_already_exists}
```

Alternatively, remove the snapshot check entirely and rely on the database unique constraint on `invoice_bank_snapshots.invoice_id` to prevent duplicate snapshots.

---

## 2. Missing Validations

### 2.1 No Date Validation

**Location:** `lib/edoc_api/core/invoice.ex`, `lib/edoc_api/core/contract.ex`

**Issue:** No validation that:

- `due_date` is after `issue_date` (Invoice)
- `issue_date` is not in the future (both)
- Contract dates are reasonable

**Risk:** Users can create invoices with past due dates or future issue dates.

**Suggested Refactor:**

```elixir
# In invoice.ex changeset
|> validate_due_date_after_issue_date()

 defp validate_due_date_after_issue_date(changeset) do
  due = get_field(changeset, :due_date)
  issue = get_field(changeset, :issue_date)

  if due && issue && Date.compare(due, issue) == :lt do
    add_error(changeset, :due_date, "must be after issue date")
  else
    changeset
  end
end
```

---

### 2.2 Weak BIN/IIN Validation

**Location:** `lib/edoc_api/validators/bin_iin.ex:40-43`

**Issue:** Only validates length (12 digits) and format, not the actual checksum. Kazakhstan BIN has a validation algorithm.

**Risk:** Invalid BINs can pass validation.

**Suggested Refactor:**

```elixir
def validate(changeset, field) do
  changeset
  |> validate_length(field, is: @bin_iin_length)
  |> validate_format(field, @bin_iin_pattern)
  |> validate_checksum(field)  # Add this
end
```

---

### 2.3 No Invoice Number Format Validation

**Location:** `lib/edoc_api/core/invoice.ex:111-116`

**Issue:** Number is only validated for length (1-32 chars). No format enforcement.

**Risk:** Inconsistent invoice numbers across the system.

**Suggested Refactor:**

```elixir
# Add format validation for auto-generated pattern
|> validate_format(:number, ~r/^[A-Z]{0,3}-?\d{10}$/)
```

---

### 2.4 Missing Contract Buyer Validation Gap

**Location:** `lib/edoc_api/core/contract.ex:137-162`

**Issue:** `validate_buyer_details/1` allows empty buyer info on new contracts but validates on update. This creates a gap where contracts can be created without any buyer.

**Risk:** Contracts without buyers can be issued, causing data integrity issues.

**Suggested Refactor:**

```elixir
# Require buyer info at creation time OR make it truly optional with defaults
|> validate_buyer_details(:create)  # strict mode for creation
```

---

### 2.5 No Currency Consistency Between Contract and Invoice

**Location:** `lib/edoc_api/core/invoice.ex`

**Issue:** When creating an invoice from a contract, there's no validation that currencies match.

**Risk:** Invoice in USD linked to Contract in KZT.

**Suggested Refactor:**

```elixir
# In Invoicing.create_invoice_from_contract/3
|> validate_currency_matches_contract()
```

---

## 3. Inconsistent Error Handling

### 3.1 Multiple Error Return Formats

**Locations:** Various context modules

**Issue:** Different modules return errors in different shapes:

- `Accounts.authenticate_user/2` → `{:error, :invalid_credentials}`
- `Invoicing.create_invoice_for_user/3` → `{:error, reason}` or `{:error, reason, details}`
- `Core.create_contract_for_user/2` → `{:error, changeset}` or `{:error, :company_required}`

**Risk:** Controllers must handle multiple error formats. Hard to write generic error handling.

**Suggested Refactor:**

```elixir
# Standardize on {:error, reason, metadata} format
defmodule EdocApi.Error do
  defstruct [:reason, :message, :details]

  def new(reason, message \\ nil, details \\ %{}) do
    {:error, %__MODULE__{reason: reason, message: message, details: details}}
  end
end
```

---

### 3.2 Inconsistent Transaction Abort Patterns

**Location:** `lib/edoc_api/invoicing.ex:46-48` vs `lib/edoc_api/core.ex:153-155`

**Issue:** Some places use `RepoHelpers.abort/1`, others use pattern matching with `unless`.

**Risk:** Inconsistent error handling makes code harder to follow.

**Code Examples:**

```elixir
# invoicing.ex - uses pattern with unless
unless invoice do
  RepoHelpers.abort(:invoice_not_found)
end

# core.ex - uses direct pattern
unless contract do
  RepoHelpers.abort(:not_found)
end
```

**Suggested Refactor:** Standardize on a single pattern using `fetch_or_abort` helper.

---

### 3.3 HTML vs JSON Controller Error Handling Divergence

**Location:** `lib/edoc_api_web/controllers/invoices_controller.ex:108-129` vs `lib/edoc_api_web/controllers/invoice_controller.ex`

**Issue:** HTML controllers handle errors inline with flash messages; JSON controllers use `ControllerHelpers`.

**Risk:** Error handling logic duplicated and diverging.

**Suggested Refactor:**

```elixir
# Create a unified error handler that dispatches based on request type
# lib/edoc_api_web/error_handler.ex
def handle_error(conn, error) do
  if conn.assigns.htmx.request do
    handle_htmx_error(conn, error)
  else
    handle_html_error(conn, error)
  end
end
```

---

### 3.4 Missing Error Logging

**Location:** `lib/edoc_api_web/controllers/` (HTML controllers)

**Issue:** HTML controllers often swallow errors without logging:

```elixir
{:error, _changeset} ->
  conn
  |> put_flash(:error, "Failed to create invoice")
```

**Risk:** Production issues hard to debug without error context.

**Suggested Refactor:**

```elixir
{:error, changeset} ->
  Logger.warning("Invoice creation failed: #{inspect(changeset.errors)}")
  conn
  |> put_flash(:error, "Failed to create invoice")
```

---

## 4. Places Likely to Break with New Requirements

### 4.1 Invoice Number Generation Complexity

**Location:** `lib/edoc_api/invoicing.ex:342-474`

**Issue:** The `next_invoice_number!/2` function has complex logic for handling:

- New counters vs existing counters
- Different sequence names
- Manual counter setting

**Risk:** High cyclomatic complexity. Adding new sequence types or number formats will be error-prone.

**Refactor Suggestion:**

```elixir
# Extract into a separate module with clear state machine
defmodule EdocApi.InvoiceNumbering do
  def next_number(company_id, opts \\ []) do
    sequence = Keyword.get(opts, :sequence, "default")
    format = Keyword.get(opts, :format, :standard)

    company_id
    |> get_or_create_counter(sequence)
    |> increment_counter()
    |> format_number(format)
  end
end
```

---

### 4.2 PDF Generation External Dependency

**Location:** `lib/edoc_api/pdf.ex:16`

**Issue:** Hard dependency on `wkhtmltopdf` system binary. No fallback mechanism.

**Risk:**

- Deployment fails if binary not installed
- No graceful degradation
- Potential security issues with external binary

**Suggested Refactor:**

```elixir
def html_to_pdf(html) when is_binary(html) do
  case System.find_executable("wkhtmltopdf") do
    nil ->
      Logger.error("wkhtmltopdf not found")
      {:error, :pdf_generator_not_available}
    path ->
      generate_pdf_with_wkhtmltopdf(html, path)
  end
end
```

---

### 4.3 Bank Account Default Switching Race Condition

**Location:** `lib/edoc_api/payments.ex:38-66`

**Issue:** The `set_default_bank_account/2` function:

1. Resets all defaults
2. Sets new default

Between steps 1 and 2, the company temporarily has NO default account.

**Risk:** Concurrent requests could leave company without a default account.

**Suggested Refactor:**

```elixir
def set_default_bank_account(user_id, bank_account_id) do
  Repo.transaction(fn ->
    # Lock the company row first
    company = get_company_for_update!(user_id)

    # Set all to false including target
    CompanyBankAccount
    |> where(company_id: ^company.id)
    |> Repo.update_all(set: [is_default: false])

    # Set target to true
    CompanyBankAccount
    |> where(id: ^bank_account_id, company_id: ^company.id)
    |> Repo.update_all(set: [is_default: true])
  end)
end
```

---

### 4.4 Contract Item Creation Partial Failure

**Location:** `lib/edoc_api/core.ex:191-203`

**Issue:** Contract items are created one by one in a reduce. If item 5 fails, items 1-4 are already created but will be rolled back by transaction.

**Risk:** Works correctly now, but if transaction is removed or modified, partial data possible.

**Suggested Refactor:**

```elixir
# Validate all items before inserting any
|> then(fn contract ->
  items_attrs
  |> Enum.map(&ContractItem.changeset(%ContractItem{}, &1, contract.id))
  |> Enum.reduce(Ecto.Multi.new(), fn changeset, multi ->
    Ecto.Multi.insert(multi, {:item, System.unique_integer()}, changeset)
  end)
  |> Repo.transaction()
end)
```

---

### 4.5 Hardcoded Kazakhstan-Specific Logic

**Location:** Multiple files

**Issue:** Kazakhstan-specific validations and business rules are scattered:

- BIN/IIN length (12 digits)
- VAT rates for KZ
- KBE/KNP codes
- Phone number formats (+7 xxx)

**Risk:** Supporting other countries requires changes across many files.

**Suggested Refactor:**

```elixir
# Create country-specific modules
defmodule EdocApi.Countries.Kazakhstan do
  def bin_length, do: 12
  def vat_rates, do: [0, 16]
  def phone_pattern, do: ~r/^\+7 \(\d{3}\) \d{3} \d{2} \d{2}$/
end

# Use in validators
|> CountryValidator.validate(:bin_iin, country: "KZ")
```

---

### 4.6 Status Transition Enforcement Split

**Location:** `lib/edoc_api/invoice_state_machine.ex` and `lib/edoc_api/invoicing.ex:498-516`

**Issue:** State machine exists but issuance logic also has manual status checks:

```elixir
# State machine defines transitions
@transitions %{"draft" => ["issued", "void"], ...}

# But invoicing.ex also checks:
not InvoiceStatus.can_issue?(invoice) ->
  {:error, :cannot_issue, %{status: "must be draft to issue"}}
(invoice.items || []) == [] ->
  {:error, :cannot_issue, %{items: "must have at least 1 item"}}
```

**Risk:** Business rules split between state machine and service logic. Easy to update one and forget the other.

**Suggested Refactor:**

```elixir
# Move all business rules to state machine guards
def can_issue?(invoice) do
  InvoiceStatus.is_draft?(invoice) and
    length(invoice.items) > 0 and
    Decimal.gt?(invoice.total, 0)
end
```

---

### 4.7 Contract Update Allows Partial Data Loss

**Location:** `lib/edoc_api/core.ex:96-117`

**Issue:** Contract update:

1. Clears all existing items (`put_assoc(:contract_items, [])`)
2. Updates contract
3. Creates new items

If step 2 succeeds but step 3 fails, contract is updated but has NO items.

**Risk:** Data loss on partial update failure.

**Suggested Refactor:**

```elixir
# Use Ecto.Multi for atomic operations
Ecto.Multi.new()
|> Ecto.Multi.update(:contract, changeset)
|> Ecto.Multi.delete_all(:delete_items, query)
|> Ecto.Multi.insert_all(:insert_items, items)
|> Repo.transaction()
```

---

## Summary of Critical Issues

| Priority | Issue                                 | Location                              |
| -------- | ------------------------------------- | ------------------------------------- |
| High     | PDF generation has no fallback        | `lib/edoc_api/pdf.ex`                 |
| High     | Bank account switching race condition | `lib/edoc_api/payments.ex`            |
| Medium   | Duplicate item calculation logic      | `invoice_item.ex`, `contract_item.ex` |
| Medium   | Inconsistent error return formats     | Multiple context modules              |
| Medium   | Missing date validations              | `invoice.ex`, `contract.ex`           |
| Low      | Hardcoded country-specific logic      | Multiple validators                   |
| Low      | Complex invoice numbering             | `invoicing.ex`                        |

---

## Recommended Action Plan

1. **Immediate (High Risk):**
   - Add `wkhtmltopdf` availability check at application startup
   - Fix bank account default switching to use atomic update

2. **Short Term (Medium Risk):**
   - Extract shared item calculation logic
   - Standardize error return formats using `EdocApi.Errors` module
   - Add date validation to schemas

3. **Long Term (Technical Debt):**
   - Create country-specific validation modules
   - Simplify invoice numbering with state machine pattern
   - Unify HTML/JSON error handling
