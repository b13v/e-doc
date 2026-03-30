# Architecture Review

**Date:** 2026-02-19
**Project:** Edoc API (Elixir/Phoenix)

## Context Boundaries Analysis

### Context Structure

The application follows a Phoenix context pattern with primary contexts in `lib/edoc_api/`:

| Context | Responsibility |
|---------|---------------|
| `EdocApi.Invoicing` | Invoice creation, issuing, payment, number generation |
| `EdocApi.Buyers` | Buyer (counterparty) CRUD operations |
| `EdocApi.Companies` | Company profile management |
| `EdocApi.Acts` | Act (completion certificate) operations |
| `EdocApi.Payments` | Bank accounts, KBE/KNP codes |
| `EdocApi.Core` | **Aggregation facade** + contract operations |
| `EdocApi.Accounts` | User authentication |

### Issues with Context Boundaries

1. **`EdocApi.Core` is an Anti-Pattern** (`/home/biba/codes/e-doc/edoc_api/lib/edoc_api/core.ex`)
   - Not a true context but a delegation facade using `defdelegate` extensively
   - Contains its own contract logic instead of having a dedicated `Contracts` context
   - **Recommendation**: Extract contract operations to `EdocApi.Contracts` context

2. **Cross-Context Dependencies**
   - `Acts` depends on `Buyers`, `Companies`, `Invoicing`
   - `Invoicing` depends on `Companies`, `Payments`
   - This coupling is acceptable for a small application but could become problematic

3. **Invoicing Context is Bloated** (991 lines)
   - Handles: Invoice CRUD, number generation/recycling, status transitions, contract building
   - **Recommendation**: Extract number generation to `EdocApi.InvoiceNumbering`

## Module Organization

### Directory Structure

```
lib/edoc_api/
├── accounts/           # User schema (nested)
├── core/               # 17 domain schemas
├── validators/         # Validation modules
├── calculations/       # Item calculations
├── documents/          # PDF generation
```

### Observations

1. **Inconsistent Schema Location**
   - Domain schemas in `core/` (e.g., `Core.Invoice`, `Core.Company`)
   - User schema in `accounts/` (`Accounts.User`)
   - **Recommendation**: Standardize - either all in `core/` or co-located with contexts

2. **Validators are Well-Organized**
   - `validators/` contains focused modules: `BinIin`, `Email`, `Iban`, `String`

3. **Naming Inconsistencies**
   - Both `InvoiceController` (API) and `InvoicesController` (HTML) exist - intentional but potentially confusing

## Schema & Data Layer

### Schema Patterns Review

| Schema | Lines | Quality |
|--------|-------|---------|
| `Core.Invoice` | 258 | Good - comprehensive validations |
| `Core.Company` | 194 | Good - custom phone validation with warnings |
| `Core.Contract` | 221 | Good - legacy + new buyer support |
| `Core.Act` | 73 | Basic - minimal validation |

### Positive Patterns

1. **Explicit User/Company Injection** - Schemas require explicit user_id/company_id from authenticated context, preventing mass assignment vulnerabilities

2. **Consistent Changeset Structure** - Module attributes for `@required_fields` and `@optional_fields`

3. **Normalization in Changesets** - Fields normalized within changesets using validator modules

### Issues Found

1. **Duplicate Code** - Date validation appears in multiple schemas

2. **Schema Mixes Concerns** - `Invoice` schema performs database queries in `prepare_changes` for ownership verification (acceptable but creates coupling)

3. **No Embedded Schemas** - Could benefit from embedded schemas for form handling

## Web Layer Architecture

### Controller Organization

```
lib/edoc_api_web/
├── controllers/
│   ├── invoice_controller.ex       # JSON API (128 lines) - Thin
│   ├── invoices_controller.ex      # HTML/HTMX (590 lines) - Fat
│   ├── invoice_html.ex             # HTML view functions
├── components/                      # Phoenix Components
├── plugs/                          # Auth, rate limiting
├── serializers/                    # JSON output formatting
```

### Observations

1. **Thin API Controllers** - Appropriate delegation to contexts

2. **Fat HTML Controllers** - `InvoicesController` contains significant form preparation logic

3. **Clean Serialization** - Dedicated serializer modules separate database models from API output

### Issues Found

1. **HTML Controllers Do Too Much** - Form data preparation could be extracted to form objects

2. **Duplicate Error Handling** - `InvoicesController.pay/4` has duplicate clauses at lines 563-566 and 573-576

## Dependencies & Coupling

### Xref Analysis Results

```
Tracked files: 110 (nodes)
Compile dependencies: 38 (edges)
Runtime dependencies: 339 (edges)
Cycles: 29
```

### Top Outgoing Dependencies

| Module | Dependencies |
|--------|--------------|
| `router.ex` | 25 |
| `invoicing.ex` | 15 |
| `core/invoice.ex` | 15 |

### Critical Coupling Areas

1. **`Invoicing` Context** - 15 dependencies, handles multiple concerns

2. **Schema Cycles** - Unavoidable due to belongs_to/has_many relationships

3. **29 Circular Dependencies** - Schema cycles are expected, but context cycles should be minimized

## Issues Found

### Critical

1. **29 Circular Dependencies** - Context cycles should be reduced; the `Core` facade adds unnecessary complexity

2. **No Explicit Behaviours/Protocols** - No `@behaviour`, `defprotocol`, or `defimpl` usage found, limiting polymorphism

### Moderate

1. **Context Naming Inconsistency** - `Core` is not a proper context

2. **Invoicing Context Too Large** - 991 lines with multiple concerns

3. **Schema Location Inconsistency** - `Accounts.User` in `accounts/` while others in `core/`

4. **Duplicate Code in Controllers** - `InvoicesController.pay/4` duplicates error handling

5. **No Aggregates Pattern** - Invoice + Items + BankSnapshot could be treated as an aggregate

### Minor

1. **Mixed Language Comments** - Some comments in Russian (e.g., `lib/edoc_api/companies.ex` line 22)

2. **Complex Transaction Handling** - Some manual `Repo.rollback` could use `RepoHelpers` patterns

## Recommendations

1. **Extract Contracts Context** - Move contract operations from `Core` to dedicated `Contracts` context

2. **Split Invoicing Context** - Extract invoice number generation to `InvoiceNumbering` context

3. **Introduce Behaviours** - Create `@behaviour EdocApi.NumberGenerator` and `@behaviour EdocApi.DocumentRenderer`

4. **Reduce Circular Dependencies** - Use `Ecto.assoc` where appropriate; move cross-cutting validations to validator modules

5. **Standardize Schema Organization** - Either all schemas in `core/` or co-located with contexts

6. **Extract Form Objects** - Move form preparation logic from HTML controllers

7. **Fix Duplicate Controller Code** - Remove duplicate clauses in `InvoicesController.pay/4`

8. **Add Aggregate Pattern** - Treat Invoice + Items + BankSnapshot as an aggregate with enforced boundaries
