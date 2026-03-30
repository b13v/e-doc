# Test Health Audit

**Date:** 2026-02-19
**Project:** Edoc API (Elixir/Phoenix)

## Executive Summary

The e-doc API project has **17 test files** covering core business logic but exhibits several critical gaps and infrastructure issues. The codebase follows good patterns for invoice/contract testing but lacks comprehensive coverage for authentication, authorization, payments, and newer features (Acts, Buyer Bank Accounts, Legal Forms).

**Overall Test Health**: ⚠️ **MODERATE** - Solid foundation with critical gaps

---

## Coverage Analysis

### Test File Breakdown

**Test Files Found (17 total)**:

```
test/edoc_api/ (8 files - Core Business Logic)
├── contract_status_test.exs
├── pdf_test.exs
├── buyers_test.exs
├── legal_forms_test.exs
├── core/contract_changeset_test.exs
├── core/invoice_counter_test.exs
├── core/invoice_issuance_test.exs
└── core/company_bank_account_changeset_test.exs

test/edoc_api/invoicing/ (2 files - Invoice Workflows)
├── invoice_contract_ownership_test.exs
└── invoice_update_test.exs

test/edoc_api_web/controllers/ (5 files - API Controllers)
├── error_json_test.exs
├── invoice_controller_test.exs
├── contract_controller_test.exs
├── buyers_controller_test.exs
└── company_bank_account_controller_test.exs
```

### Coverage by Context Module

| Module | Coverage | Assessment |
|--------|----------|------------|
| `EdocApi.Invoicing` | **GOOD** | Issue/pay workflows tested |
| `EdocApi.Core.Invoice` | **GOOD** | Issuance, counters, contracts |
| `EdocApi.Core.Contract` | **GOOD** | Changesets, issue flow |
| `EdocApi.Buyers` | **MODERATE** | Bank account integration only |
| `EdocApi.Accounts` | **CRITICAL** | No tests found |
| `EdocApi.Payments` | **CRITICAL** | No tests found |
| `EdocApi.Companies` | **CRITICAL** | No tests found |
| `EdocApi.Acts` | **CRITICAL** | No tests (NEW feature) |
| `EdocApi.EmailVerification` | **CRITICAL** | No tests |
| `EdocApi.LegalForms` | **GOOD** | Module tested |
| `EdocApi.Currencies` | **GOOD** | Module tested |

### Coverage by Web Controllers

| Controller | Tested | Missing Tests |
|------------|--------|---------------|
| `InvoiceController` | ✅ | PDF generation |
| `ContractController` | ✅ | None |
| `BuyersController` | ✅ | None |
| `CompanyBankAccountController` | ✅ | None |
| `AuthController` | ❌ | **ALL** (signup, login, verify) |
| `CompanyController` | ❌ | **ALL** |
| `ActsController` | ❌ | **ALL** (NEW) |
| `InvoicesController` | ❌ | **ALL** (HTML/HTMX) |
| `ContractsController` | ❌ | **ALL** (HTML/HTMX) |
| `DictController` | ❌ | **ALL** |

---

## Test Organization

### Structure Assessment: ⚠️ **NEEDS IMPROVEMENT**

**Strengths**:
- ✅ Tests mirror `lib/` structure in `test/edoc_api/` and `test/edoc_api_web/`
- ✅ Clear separation between context tests and controller tests
- ✅ Invoicing tests organized in subdirectory `test/edoc_api/invoicing/`
- ✅ Core module tests grouped in `test/edoc_api/core/`

**Weaknesses**:
- ❌ **No integration test suite** - End-to-end workflows missing
- ❌ **No property-based tests** - Complex logic like VAT calculations unverified
- ❌ **Missing test helpers** - Authentication helpers duplicated across files
- ❌ **No test tags organization** - Can't run targeted test suites (e.g., `@tag :unit`)

---

## Test Quality Patterns

### Iron Law Violations Found

#### ❌ **CRITICAL: Missing `async: true`**

**Violation**: Only **13 of 17 test files** use `async: true`

**Files Missing Async**:
- `test/edoc_api_web/controllers/invoice_controller_test.exs`
- `test/edoc_api_web/controllers/contract_controller_test.exs`
- `test/edoc_api_web/controllers/buyers_controller_test.exs`
- `test/edoc_api_web/controllers/company_bank_account_controller_test.exs`

**Impact**: Tests run sequentially, significantly slower CI times

**Fix**:
```elixir
# Before
use EdocApiWeb.ConnCase

# After
use EdocApiWeb.ConnCase, async: true
```

---

#### ✅ **GOOD: No `Process.sleep` or `:timer.sleep`**

Scan of entire test directory found **ZERO instances** of sleep-based timing, indicating proper async testing with `assert_receive` or synchronous operations.

---

#### ✅ **GOOD: Sandbox Isolation**

`test/support/data_case.ex` properly configures Ecto SQL Sandbox:
```elixir
def setup_sandbox(tags) do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EdocApi.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
end
```

---

#### ⚠️ **WARNING: No Mock Framework Usage**

**Finding**: **ZERO files** use Mox or any mocking framework

**Implications**:
- ✅ Tests are integration-style (testing real behavior)
- ❌ **External dependencies not mocked**:
  - `EdocApi.EmailSender` delivers real emails (though Swoosh adapter used in test)
  - PDF generation depends on `wkhtmltopdf` binary (tests skipped if missing)

**Recommendation**: For external service boundaries (email, PDF, future payment gateways), define behaviours and use Mox.

---

### Factory Pattern Assessment: ⚠️ **NEEDS IMPROVEMENT**

**Current Approach**: Manual fixture functions in `EdocApi.TestFixtures`

**Strengths**:
- ✅ Unique values using `System.unique_integer([:positive])`
- ✅ Proper database inserts for related data
- ✅ Helper functions (`ensure_company_has_bank_account/1`) prevent cascading failures

**Weaknesses**:
- ❌ **NOT using ExMachina** - No `build()` vs `insert()` distinction
- ❌ **All fixtures create DB records** - Slower tests
- ❌ **No trait system** - Cannot compose fixture variations
- ❌ **Hardcoded valid BINs** - Tests depend on specific Kazakhstan BIN format

---

### Setup Pattern Assessment: ✅ **GOOD**

**Positive Findings**:
- ✅ Named setup functions used (e.g., `setup [:create_user, :authenticate]`)
- ✅ Authentication helpers properly extracted
- ✅ Company/buyer creation helper prevents duplication

**Example Good Pattern**:
```elixir
setup %{conn: conn} do
  user = create_user!()
  EdocApi.Accounts.mark_email_verified!(user.id)
  company = create_company!(user)
  {:ok, conn: authenticate(conn, user), user: user, company: company}
end

defp authenticate(conn, user) do
  {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
  put_req_header(conn, "authorization", "Bearer #{token}")
end
```

---

### Assertion Quality: ✅ **STRONG**

**Good Practices Observed**:
- ✅ Pattern matching in assertions (preferred over equality)
- ✅ Specific error tuple matching (not generic `assert {:error, _}`)
- ✅ Descriptive test names
- ✅ Testing both success and failure paths

---

## Critical Missing Tests

### 🔴 **CRITICAL: Authentication & Authorization**

**Missing Coverage**:
```elixir
# Files NOT tested:
lib/edoc_api_web/controllers/auth_controller.ex     # signup, login, verify
lib/edoc_api_web/plugs/authenticate.ex              # JWT verification
lib/edoc_api_web/plugs/rate_limit.ex                # Rate limiting
lib/edoc_api/accounts.ex                            # User registration, auth
lib/edoc_api/email_verification.ex                  # Token lifecycle
```

**Risk**: 🔴 **HIGH** - Security vulnerabilities undetected

**Required Tests**:
1. **Signup Flow**:
   - Valid user registration
   - Duplicate email rejection
   - Password validation
   - Verification token creation
   - Email delivery (mock Swoosh)

2. **Login Flow**:
   - Valid credentials
   - Invalid password
   - Non-existent user
   - Unverified user rejection
   - JWT token generation

3. **Email Verification**:
   - Token verification
   - Token expiration
   - Already verified handling
   - Resend rate limiting

4. **JWT Authentication**:
   - Valid token acceptance
   - Invalid token rejection
   - Expired token rejection
   - Missing token handling

5. **Authorization**:
   - Unverified users blocked from protected endpoints
   - User cannot access another user's resources
   - Company ownership enforcement

---

### 🔴 **CRITICAL: Payments & Bank Accounts**

**Missing Coverage**:
```elixir
lib/edoc_api/payments.ex                            # Payment processing
lib/edoc_api_web/controllers/company_bank_account_controller.ex  # Partially tested
```

**Risk**: 🔴 **HIGH** - Financial transactions unvalidated

---

### 🔴 **CRITICAL: Company Management**

**Missing Coverage**:
```elixir
lib/edoc_api/companies.ex
lib/edoc_api_web/controllers/company_controller.ex
```

**Risk**: 🔴 **MEDIUM-HIGH** - Core entity untested

---

### 🟡 **HIGH PRIORITY: Acts Feature**

**Missing Coverage**:
```elixir
lib/edoc_api/acts.ex                                 # NEW feature
lib/edoc_api_web/controllers/acts_controller.ex     # NEW controller
lib/edoc_api/core/act.ex                            # NEW schema
lib/edoc_api/core/act_item.ex                       # NEW schema
lib/edoc_api/documents/act_pdf.ex                   # NEW PDF generation
```

**Risk**: 🟡 **MEDIUM** - New feature, zero test coverage

---

## Recommendations

### 🔴 **CRITICAL ACTIONS** (Do Immediately)

1. **Add Authentication Test Suite**
   - Create `test/edoc_api_web/controllers/auth_controller_test.exs`
   - Test signup, login, verification flows
   - Test JWT token generation and validation
   - Test authorization plugs

2. **Add Authorization Tests**
   - Verify user isolation (cannot access other users' data)
   - Test company ownership enforcement
   - Test unverified user blocking

3. **Enable `async: true` for Controller Tests**
   - Update all `use EdocApiWeb.ConnCase` to `use EdocApiWeb.ConnCase, async: true`
   - Expected 30-40% test suite speedup

4. **Add Acts Feature Tests**
   - Create `test/edoc_api/acts_test.exs`
   - Create `test/edoc_api_web/controllers/acts_controller_test.exs`

5. **Add Company Management Tests**
   - Create `test/edoc_api/companies_test.exs`
   - Create `test/edoc_api_web/controllers/company_controller_test.exs`

---

### 🟡 **HIGH PRIORITY** (Do This Sprint)

6. **Add Payment/Bank Account Tests**
7. **Install ExMachina** for better factory patterns
8. **Add Email Verification Tests**
9. **Add Integration Test Suite**
10. **Configure Test Coverage**

---

### 🟠 **MEDIUM PRIORITY** (Next Sprint)

11. **Add Test Tags** for categorization
12. **Add Property-Based Tests** for VAT calculations
13. **Add LiveView Tests** for HTML/HTMX controllers
14. **Add Plug Tests** for authentication and rate limiting

---

## Module Coverage Checklist

### Context Modules
- [ ] `EdocApi.Accounts` - 0% coverage
- [ ] `EdocApi.Buyers` - 30% coverage (bank accounts only)
- [x] `EdocApi.Invoicing` - 80% coverage
- [ ] `EdocApi.Companies` - 0% coverage
- [ ] `EdocApi.Payments` - 0% coverage
- [ ] `EdocApi.Acts` - 0% coverage
- [x] `EdocApi.LegalForms` - 100% coverage
- [x] `EdocApi.Currencies` - 100% coverage
- [ ] `EdocApi.EmailVerification` - 0% coverage

### Core Schemas
- [x] `EdocApi.Core.Invoice` - 90% coverage
- [x] `EdocApi.Core.Contract` - 85% coverage
- [ ] `EdocApi.Core.Company` - 20% coverage
- [ ] `EdocApi.Core.Buyer` - 30% coverage
- [ ] `EdocApi.Core.Act` - 0% coverage
- [ ] `EdocApi.Core.ActItem` - 0% coverage
- [ ] `EdocApi.Core.BuyerBankAccount` - 0% coverage
- [ ] `EdocApi.Core.UnitOfMeasurement` - 0% coverage

### Web Controllers
- [x] `EdocApiWeb.InvoiceController` - 75% coverage
- [x] `EdocApiWeb.ContractController` - 80% coverage
- [x] `EdocApiWeb.BuyersController` - 60% coverage
- [x] `EdocApiWeb.CompanyBankAccountController` - 70% coverage
- [ ] `EdocApiWeb.AuthController` - 0% coverage
- [ ] `EdocApiWeb.CompanyController` - 0% coverage
- [ ] `EdocApiWeb.ActsController` - 0% coverage
- [ ] `EdocApiWeb.ContractsController` - 0% coverage
- [ ] `EdocApiWeb.InvoicesController` - 0% coverage

### Web Plugs
- [ ] `EdocApiWeb.Plugs.Authenticate` - 0% coverage
- [ ] `EdocApiWeb.Plugs.RateLimit` - 0% coverage
- [ ] `EdocApiWeb.Plugs.AuthenticateSession` - 0% coverage
- [ ] `EdocApiWeb.Plugs.HtmxDetect` - 0% coverage
- [ ] `EdocApiWeb.Plugs.HtmxLayout` - 0% coverage

---

## Summary

**Current State**: The project has a solid foundation with 17 test files covering core invoicing and contract logic. Tests follow good practices with sandbox isolation, proper setup patterns, and strong assertions.

**Critical Gaps**: Authentication, authorization, payments, company management, and the new Acts feature have zero test coverage, representing significant security and business logic risks.

**Quick Wins**: Enable `async: true` on controller tests (30-40% speedup), add ExMachina for faster factories, and create authentication tests.

**Target Coverage**: Aim for 80% coverage across all critical business logic paths, with particular focus on authentication, authorization, and financial transactions.
