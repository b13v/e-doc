# EdocApi Repository Audit Summary

## Project Overview

- **Type**: E-invoicing REST API (Phoenix 1.7.10 / Elixir 1.14+)
- **Purpose**: Electronic document generation for Kazakh companies (invoices, contracts, PDFs)
- **Database**: PostgreSQL
- **Size**: ~4,000 LOC, 13 tests, 129 dependencies
- **Repo**: `git@github.com:b13v/e-doc.git`

## Architecture

```
API Layer: JWT auth (7-day expiry) -> Controllers -> Business Logic -> Ecto -> PostgreSQL
```

**Core Domains:**

- Users & Companies (multi-tenant)
- Invoices (draft -> issued -> paid/void)
- Contracts
- Bank Accounts (multiple per company)
- PDF Generation

## Security Assessment

### Critical Issues

1. **JWT Secret** (`config/config.exs:47`): `"dev-secret-change-me"` - must use env var in production
2. ~~**Race Condition** (`lib/edoc_api/invoicing.ex:96-100`): No DB constraint prevents multiple `is_default=true` bank accounts~~ ✅ **RESOLVED**
3. ~~**Missing Authorization**: No validation that `contract_id` belongs to user's company~~ ✅ **RESOLVED**

### Medium Issues

1. ~~**Hardcoded Currency Precision** (`lib/edoc_api/invoicing.ex:176-181`): Decimal rounding fixed to 2 places~~ ✅ **RESOLVED**
2. ~~**Invoice Number Overflow** (`lib/edoc_api/invoicing.ex:260`): 10-digit padding will break after 10B invoices~~ ✅ **RESOLVED**
3. **Dev Config Exposed** (`config/dev.exs`): DB credentials and secret_key_base in version control (acceptable for dev)

### Good Security Practices

- Argon2 password hashing
- JWT with exp/iss/aud validation
- No SQL injection (parameterized queries via Ecto)
- Bearer token authentication

## Code Quality

### Completed Refactorings (per REFACTORING_SUMMARY.md)

1. Unified controller error handling (`controller_helpers.ex`)
2. Clean transaction error wrapping (`repo_helpers.ex`)
3. Bank account single source of truth (deprecated legacy fields)

### Outstanding Issues

- No invoice state machine (scattered `cond` checks)
- Dual bank info sources still have fallback logic

### Code Health

- **Formatting**: Properly formatted (mix format check passes)
- **No TODO/FIXME comments** found
- **No static analysis tools**: credo/dialyxir/sobelow not configured
- **No CI/CD**: No .github directory or workflows

## Testing

- **Coverage**: Sparse (~182 test lines vs 4,000 LOC)
- **Tests**: 30 passing, 8 test files
- **Missing**: Integration tests, edge case coverage, security tests

## Database

- **Migrations**: 18 migrations (proper versioning)
- **Constraints**: Unique index on (user_id, invoice_number)
- **Missing**: Unique constraint on (company_id, is_default) for bank accounts

## API Endpoints

```
Public:  /v1/auth/{signup,login}, /v1/health
Protected (JWT): /v1/invoices, /v1/contracts, /v1/company, /v1/company/bank-accounts
```

## Recommendations

### Priority 1 (Security)

1. Set `JWT_SECRET` env var for production
2. ~~Add partial unique index: `create unique_index(:company_bank_accounts, [:company_id], where: "is_default = true")`~~ ✅ **DONE**
3. ~~Add `contract_id` ownership validation in invoice changeset~~ ✅ **DONE**

### Priority 2 (Stability)

1. ~~Implement currency precision lookup (`currencies.ex`)~~ ✅ **DONE**
2. Add state machine for invoice transitions
3. ~~Increase invoice number padding or add overflow protection~~ ✅ **DONE**

### Priority 3 (Quality)

1. Add credo/dialyxir/sobelow for code quality
2. Expand test coverage (target: 80%+)
3. Setup GitHub Actions CI/CD pipeline

## Overall Assessment

**Maturity Level**: Early-stage (active refactoring in progress)

The codebase shows good recent refactoring work with centralized validators and unified error handling. However, security gaps (JWT secret, authorization) and missing safeguards (race conditions, overflow protection) should be addressed before production deployment. Test coverage is minimal and needs expansion.
