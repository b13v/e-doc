# Code Audit Report

## 1. DUPLICATED BUSINESS RULES

### 1.1 IBAN Normalization (3 locations)

| File | Lines |
|------|-------|
| `lib/edoc_api/core/invoice.ex` | 115-118 |
| `lib/edoc_api/core/company.ex` | 91-94 |
| `lib/edoc_api/core/company_bank_account.ex` | 35-36 |

**Risk:** Changing normalization rules requires updating 3 files.

**Refactor:** Create `lib/edoc_api/validators/iban_validator.ex`:
```elixir
defmodule EdocApi.Validators.IbanValidator do
  def normalize(nil), do: nil
  def normalize(v) when is_binary(v), do: v |> String.replace(~r/\s+/, "") |> String.upcase()
end
```

---

### 1.2 BIN/IIN Validation (2 locations)

| File | Lines |
|------|-------|
| `lib/edoc_api/core/invoice.ex` | 112-130 (`digits_only/1`, `validate_bin_iin/2`) |
| `lib/edoc_api/core/company.ex` | 86-111 (`normalize_digits/1`, `validate_bin_iin/1`) |

**Risk:** If Kazakhstan changes to 13-digit format, must update both places.

**Refactor:** Create `lib/edoc_api/validators/bin_iin_validator.ex` with `@bin_iin_length 12` constant.

---

### 1.3 Invoice Status Hardcoded (3+ places)

| File | Lines | Usage |
|------|-------|-------|
| `lib/edoc_api/invoicing.ex` | 296-311 | Status checks |
| `lib/edoc_api/core/invoice.ex` | 74 | Default "draft" |
| `lib/edoc_api_web/pdf_templates.ex` | 276 | Status comparison |

**Risk:** Adding new statuses (e.g., "archived", "revised") requires hunting through multiple files.

**Refactor:** Create `lib/edoc_api/core/invoice_status.ex` with constants and helper functions like `can_issue?/1`.

---

## 2. MISSING VALIDATIONS

### 2.1 No FK Validation for bank_account_id Ownership

**File:** `lib/edoc_api/invoicing.ex:89-99`

**Risk:** Invoice schema has no constraint ensuring `bank_account_id` belongs to the same company. Runtime check exists but not at changeset level.

**Refactor:** Add `prepare_changes(&validate_bank_account_ownership/1)` to Invoice changeset.

---

### 2.2 No Validation of Negative Amounts

**File:** `lib/edoc_api/core/invoice.ex:76-77`

**Risk:** Only `total > 0` is validated. A negative `subtotal` could create negative VAT. User could send `subtotal: -1000`.

**Refactor:** Add:
```elixir
|> validate_number(:subtotal, greater_than_or_equal_to: 0)
|> validate_number(:vat, greater_than_or_equal_to: 0)
```

---

### 2.3 Missing contract_id Ownership Validation

**File:** `lib/edoc_api/invoicing.ex` (create flow)

**Risk:** No check that `contract_id` belongs to the user's company. A user could attach invoices to another company's contract.

---

## 3. INCONSISTENT ERROR HANDLING

### 3.1 Different Controller Patterns

| File | Pattern |
|------|---------|
| `lib/edoc_api_web/controllers/invoice_controller.ex:60-85` | Explicit `case` with catch-all Logger |
| `lib/edoc_api_web/controllers/company_bank_account_controller.ex:18-37` | `with` without catch-all |
| `lib/edoc_api_web/controllers/contract_controller.ex:14-30` | `with` without catch-all |

**Risk:** Unexpected errors silently fail in some controllers but get logged in others.

**Refactor:** Create `lib/edoc_api_web/response_handler.ex` with unified error mapping.

---

### 3.2 Inconsistent Changeset Wrapping

| File | Lines | Pattern |
|------|-------|---------|
| `lib/edoc_api/invoicing.ex` | 120-122 | `Repo.rollback({:error, cs})` |
| `lib/edoc_api/payments.ex` | 31-34 | Returns `{:error, cs}` directly |

**Risk:** Callers must handle both patterns.

---

## 4. FRAGILE CODE (Will Break with New Requirements)

### 4.1 Multiple Banks Per Company - Dual Source of Truth

**Files:**
- `lib/edoc_api/core/company.ex:14-15` (has `iban`, `bank_name` fields)
- `lib/edoc_api/invoicing.ex:105` (falls back to `company.iban`)

**Risk:** Company has its own IBAN fields AND a `has_many :bank_accounts`. Invoice creation uses bank_account if provided, else falls back to `company.iban`. Two sources of truth.

**Refactor:** Remove `iban`, `bank_name` from Company schema. Always require explicit bank account selection.

---

### 4.2 No State Machine for Invoice Transitions

**File:** `lib/edoc_api/invoicing.ex:288-314`

**Risk:** Status transitions are scattered `cond` checks. Adding "void" or "paid" transitions requires modifying multiple functions.

**Refactor:** Create `lib/edoc_api/core/invoice_state_machine.ex`:
```elixir
@transitions %{
  "draft" => ["issued", "void"],
  "issued" => ["paid", "void"],
  "paid" => [],
  "void" => []
}
def can_transition?(from, to), do: to in Map.get(@transitions, from, [])
```

---

### 4.3 Multi-Currency Decimal Precision Hardcoded

**File:** `lib/edoc_api/invoicing.ex:176-181`

```elixir
|> Decimal.round(2)  # Hardcoded
```

**Risk:** EUR/USD = 2 decimals, but JPY = 0, KWD = 3. Adding new currencies will produce wrong rounding.

**Refactor:** Create `lib/edoc_api/currencies.ex` with `decimal_places/1` function.

---

### 4.4 Race Condition in Default Bank Selection

**File:** `lib/edoc_api/invoicing.ex:334-341`

```elixir
|> where([a], a.company_id == ^invoice_company_id and a.is_default == true)
|> order_by([a], desc: a.inserted_at)
|> limit(1)
```

**Risk:** Multiple accounts can be `is_default: true` simultaneously. No DB constraint. Non-deterministic selection.

**Refactor:** Add partial unique index:
```elixir
create unique_index(:company_bank_accounts, [:company_id],
  where: "is_default = true",
  name: :company_bank_accounts_single_default)
```

---

### 4.5 Invoice Number Overflow

**File:** `lib/edoc_api/invoicing.ex:260`

```elixir
String.pad_leading(Integer.to_string(seq), 10, "0")
```

**Risk:** After 10 billion invoices, number becomes 11 digits. No protection.

---

## 5. PRIORITY SUMMARY

| Priority | Issue | File | Effort |
|----------|-------|------|--------|
| **Critical** | IBAN/BIN validation duplication | Multiple | 2hrs |
| **Critical** | Missing bank_account ownership validation | `invoicing.ex` | 1hr |
| **High** | Hardcoded invoice statuses | Multiple | 2hrs |
| **High** | Dual source of truth for bank | `company.ex`, `invoicing.ex` | 4hrs |
| **High** | Race condition in default bank | `invoicing.ex:334-341` | 1hr |
| **Medium** | Inconsistent error handling | Controllers | 2hrs |
| **Medium** | Multi-currency precision | `invoicing.ex:176-181` | 2hrs |
| **Medium** | Missing amount validations | `invoice.ex` | 1hr |
