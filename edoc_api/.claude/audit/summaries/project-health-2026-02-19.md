# Project Health Audit: Edoc API

**Generated:** 2026-02-19
**Project:** e-doc/edoc_api
**Stack:** Phoenix 1.7.21, Ecto 4.4, Elixir ~> 1.14

---

## Executive Summary

### Overall Health Score: **D (64/100)**

| Category | Score | Status | Weight |
|----------|-------|--------|--------|
| **Dependencies** | 90/100 | Excellent (A) | 10% |
| **Architecture** | 65/100 | Needs Improvement (C) | 15% |
| **Tests** | 60/100 | Needs Work (D) | 20% |
| **Security** | 55/100 | Critical Issues (F) | 30% |
| **Performance** | 50/100 | Critical Issues (F) | 25% |

**Weighted Score:** 64/100

---

## Critical Issues (Must Address Immediately)

### Security (Critical)

1. **Hardcoded Secrets in Configuration Files**
   - **Files:** `config/config.exs:53`, `config/dev.exs:27`, `config/test.exs:20`
   - **Issue:** JWT secret and secret_key_base are hardcoded
   - **Risk:** Credentials in version control, production secrets may be exposed
   - **Fix:** Use environment variables with fallback to raise error if unset

2. **Missing Log Parameter Filtering**
   - **Issue:** Sensitive data (passwords, tokens) may be logged
   - **Fix:** Add `config :phoenix, :filter_parameters, ["password", "token", "secret"]`

3. **Information Disclosure via `inspect(reason)`**
   - **Files:** Multiple controllers (auth_controller.ex, buyers_controller.ex)
   - **Issue:** Internal error details exposed to users
   - **Fix:** Return sanitized error messages

### Performance (Critical)

4. **Unpaginated Lists in HTML Controllers**
   - **Files:** `invoices_controller.ex`, `acts_controller.ex`, `buyer_html_controller.ex`
   - **Issue:** ALL records loaded without limit
   - **Risk:** Memory exhaustion as data grows
   - **Fix:** Add pagination with `limit` and `offset` parameters

5. **Missing Database Indexes**
   - **Tables:** `invoices.status`, `contracts.status`
   - **Issue:** Full table scans on status filter queries
   - **Fix:** Add indexes and composite index `(company_id, status)`

6. **No Caching Layer**
   - **Issue:** Reference data (KBE/KNP codes, banks) fetched on every request
   - **Fix:** Install Cachex for reference data caching

### Tests (Critical)

7. **Zero Authentication Test Coverage**
   - **Missing:** `AuthController`, `Accounts` context, JWT validation
   - **Risk:** Security vulnerabilities undetected

8. **Zero Authorization Test Coverage**
   - **Missing:** User isolation tests, company ownership enforcement
   - **Risk:** Horizontal privilege escalation undetected

9. **Zero Coverage for New Acts Feature**
   - **Missing:** All Acts-related tests
   - **Risk:** New feature bugs undetected

---

## Detailed Findings

### Architecture (65/100 - C)

**Strengths:**
- Proper Phoenix context pattern foundation
- Explicit user/company injection prevents mass assignment
- Consistent changeset structure with validation
- Clean serialization layer separates DB from API

**Issues:**
- **29 circular dependencies** between modules
- `EdocApi.Core` is a facade anti-pattern, not a true context
- `Invoicing` context bloated (991 lines) — handles multiple concerns
- Schema location inconsistent (Accounts.User in `accounts/`, others in `core/`)
- No `@behaviour` or protocols — limits polymorphism
- HTML controllers contain form preparation logic (should be form objects)

**Recommendations:**
1. Extract `EdocApi.Contracts` context from `Core`
2. Split invoice number generation to `InvoiceNumbering` context
3. Standardize schema organization
4. Extract form objects from HTML controllers
5. Introduce behaviours for number generation and document rendering

---

### Security (55/100 - F)

**Strengths:**
- Argon2 password hashing (industry best practice)
- Timing-safe authentication prevents timing attacks
- JWT implementation using Joken library
- Proper data scoping by user_id in all context functions
- Changesets for all input validation
- No SQL injection — all queries use `^` operator
- CSRF protection enabled
- Email verification required

**Critical Issues:**
1. Hardcoded JWT secret: `"dev-secret-change-me"`
2. Hardcoded secret_key_base in dev/test configs
3. Hardcoded session signing_salt in endpoint
4. No `filter_parameters` configuration
5. `inspect(reason)` exposes internal details
6. Missing security headers (X-Frame-Options, X-Content-Type-Options)
7. CSP uses `unsafe-inline` for scripts
8. Rate limiting only on auth endpoints
9. 7-day JWT expiry (may be too long)
10. No token revocation on logout

**Recommendations:**
1. Move all secrets to environment variables
2. Add parameter filtering to Phoenix config
3. Sanitize error messages
4. Add missing security headers
5. Extend rate limiting to all sensitive endpoints
6. Consider shorter JWT expiry with refresh tokens

---

### Performance (50/100 - F)

**Strengths:**
- Recent migrations added important foreign key indexes
- Proper use of Ecto预加载 syntax

**Critical Issues:**
1. **Unpaginated lists** — All invoices/acts/buyers loaded
2. **Missing indexes** — `invoices.status`, `contracts.status`
3. **No caching** — Reference data fetched on every request
4. **N+1 queries** — 8 patterns (preload after query, enum.each with Repo)
5. **Bulk operations in loops** — Invoice/act items inserted one-by-one
6. **Inefficient search** — Leading wildcard `%query%` prevents index use

**Recommendations:**
1. Add pagination to all list views
2. Create migration for status indexes
3. Install Cachex for reference data (KBE/KNP codes, banks)
4. Convert bulk inserts to `insert_all/2`
5. Add trigram index for buyer search or migrate to full-text search

---

### Tests (60/100 - D)

**Strengths:**
- 17 test files covering core business logic
- Good patterns: sandbox isolation, proper setup, strong assertions
- No `Process.sleep` — proper async testing
- Named setup functions prevent duplication

**Critical Gaps:**
| Module | Coverage | Risk |
|--------|----------|------|
| `EdocApi.Accounts` | 0% | HIGH — Auth logic untested |
| `EdocApi.Auth` | 0% | HIGH — JWT untested |
| `EdocApi.Payments` | 0% | HIGH — Financial transactions untested |
| `EdocApi.Acts` | 0% | MEDIUM — New feature |
| `EdocApi.Companies` | 0% | MEDIUM — Core entity |

**Missing Controller Tests:**
- `AuthController` — signup, login, verification
- `CompanyController` — all endpoints
- `ActsController` — all endpoints (new)
- HTML/HTMX controllers — all forms and interactivity

**Issues:**
1. 4 controller tests missing `async: true` (slower CI)
2. No integration test suite
3. No mock framework (Mox)
4. Manual fixtures instead of ExMachina
5. No test tags for categorization

**Recommendations:**
1. Create authentication test suite
2. Create authorization test suite
3. Create Acts feature test suite
4. Enable `async: true` on all controller tests (30-40% speedup)
5. Install ExMachina for better factories

---

### Dependencies (90/100 - A)

**Strengths:**
- No retired packages (hex.audit clean)
- All dependencies actively used
- Permissive licenses (MIT/Apache-2.0)
- Proper classification (compile/runtime/dev)

**Updates Available:**
- Patch: `ecto_sql` 3.13.3 → 3.13.4, `tidewave` 0.5.4 → 0.5.5
- Minor: `finch`, `plug_cowboy`, `postgrex`, `swoosh`
- Major: Phoenix 1.7.21 → 1.8.3 (requires constraint change)

**Recommendations:**
1. Apply patch updates
2. Plan Phoenix 1.8 upgrade for next cycle
3. Consider upgrading to Elixir 1.16+

---

## Action Plan

### Immediate (This Sprint)

**Security:**
- [ ] Remove hardcoded secrets from config files
- [ ] Add `filter_parameters` to Phoenix config
- [ ] Sanitize error messages (remove `inspect(reason)`)

**Performance:**
- [ ] Add pagination to `invoices_controller.ex`
- [ ] Add pagination to `acts_controller.ex`
- [ ] Create migration for status indexes

**Tests:**
- [ ] Create authentication test suite
- [ ] Enable `async: true` on controller tests

---

### Short-term (Next 2 Sprints)

**Security:**
- [ ] Add missing security headers
- [ ] Extend rate limiting to protected endpoints
- [ ] Tighten CSP policy

**Performance:**
- [ ] Install Cachex and cache reference data
- [ ] Convert bulk inserts to `insert_all/2`
- [ ] Add composite indexes for user queries

**Architecture:**
- [ ] Extract `Contracts` context from `Core`
- [ ] Split invoice number generation to separate context

**Tests:**
- [ ] Create Acts feature test suite
- [ ] Create authorization test suite
- [ ] Install ExMachina for factories

---

### Long-term (Backlog)

- [ ] Phoenix 1.8 upgrade
- [ ] Elixir 1.16+ upgrade
- [ ] Install Oban for background jobs (PDF generation)
- [ ] Implement search service for buyer queries
- [ ] Add integration test suite
- [ ] Implement token revocation on logout
- [ ] Add structured security event logging

---

## Summary

**Current State:** The Edoc API has a solid foundation with proper Phoenix patterns, good input validation, and a clean dependency tree. However, critical security vulnerabilities (hardcoded secrets), performance issues (unpaginated queries, missing indexes), and major test coverage gaps (authentication, authorization, new features) require immediate attention.

**Focus Areas:**
1. **Security first** — Remove hardcoded secrets immediately
2. **Performance second** — Add pagination before data volume grows
3. **Tests third** — Cover authentication and authorization paths

**Target Health:** B (80/100) within 2 sprints by addressing critical issues above.
