# Project Health Audit: Edoc API

**Generated:** 2026-03-19
**Project:** e-doc/edoc_api
**Stack:** Phoenix 1.7.21, Ecto 4.4, Elixir ~> 1.14

---

## Executive Summary

### Overall Health Score: **C (71/100)**

| Category | Score | Status | Change |
|----------|-------|--------|--------|
| **Tests** | 78/100 | Strong (C+) | ⬆️ +18 (improved) |
| **Dependencies** | 78/100 | Good (B-) | ⬇️ -12 (more outdated) |
| **Security** | 72/100 | Moderate (C-) | ⬆️ +17 (improved) |
| **Performance** | 72/100 | Moderate (C-) | ⬆️ +22 (improved) |
| **Architecture** | 52/100 | Poor (F) | ⬇️ -13 (worsened) |

**Weighted Score:** 71/100

**Positive Trend:** Security and Performance improved since last audit (hardcoded issues addressed, indexes added)
**Concern:** Architecture debt increased (38 cycles vs 29 previously)

---

## Critical Issues (Must Address)

### Architecture (Critical)

1. **38 Circular Dependency Cycles** (increased from 29)
   - **PDF generation cycle:** 9-node cycle involving Contract PDF → Templates → HTML Controller → Router
   - **Impact:** Difficult to test, refactor, unpredictable ripple effects
   - **Fix:** Extract PDF generation into separate service, break web layer coupling

2. **Schema with Business Logic**
   - `Core.Invoice` contains database queries (violates schema-as-data principle)
   - **Fix:** Move all queries to context modules

3. **No OTP Patterns**
   - No GenServer, Task, or Agent usage
   - **Impact:** Synchronous PDF generation blocks requests

### Security (Moderate - Improved)

4. **Hardcoded JWT Secret** (CRITICAL)
   - **File:** `config/config.exs:18-20`
   - **Issue:** Uses fallback that could be predictable
   - **Fix:** Enforce environment variable with raise error

5. **Information Disclosure**
   - Several controllers use `inspect(reason)` exposing internal details
   - **Fix:** Return sanitized error messages

### Performance (Moderate - Improved)

6. **Unpaginated Lists in HTML Controllers**
   - `invoices_controller.ex`, `acts_controller.ex`, `buyer_html_controller.ex`
   - **Impact:** Memory risk as data grows

7. **Missing Composite Index**
   - Contract sorting with `COALESCE(issue_date, contract_date)` needs index
   - **Fix:** Add `(company_id, sort_date DESC)` composite index

### Tests (Gaps Remain)

8. **Missing HTML Controller Tests** (6 files)
   - Invoices, Contracts, Acts, Signup, Session, VerificationPending controllers
   - **Impact:** UI bugs may slip through

9. **Missing Plug Tests** (5 files)
   - Authenticate, AuthenticateSession, SetLocale, HtmxDetect, HtmxLayout

---

## Detailed Findings

### Architecture (52/100 - F) ⚠️

**Strengths:**
- Clean controller design (no direct Repo access)
- Centralized error handling (UnifiedErrorHandler)
- Proper context delegation

**Critical Issues:**
- **38 circular dependencies** (+31% increase)
- **PDF system** creates 9-node cycle with web layer
- **Schema violations** — `Core.Invoice` imports Ecto.Query
- **No OTP patterns** — No GenServer for state management

**Recommendations:**
1. Extract PDF generation as separate service (break cycles)
2. Move queries from schemas to contexts
3. Implement GenServer for document processing
4. Consider Oban for background jobs

---

### Security (72/100 - C-) ⬆️ IMPROVED

**Improvements Since Last Audit:**
- ✅ `filter_parameters` now configured (lines 71-82 in config.exs)
- ✅ Security headers added (X-Frame-Options, X-Content-Type-Options, CSP)
- ✅ Rate limiting extended (auth: 5/min, verification: 20/min, API: 30/min, PDF: 10/min)

**Strengths:**
- Argon2 password hashing with proper cost factors
- Timing-safe authentication (`Argon2.no_user_verify()`)
- Account lockout after 5 failed attempts
- Proper JWT implementation with Joken
- All data scoped by user_id
- No SQL injection (all queries use `^` operator)

**Remaining Issues:**
1. Hardcoded JWT secret fallback
2. `inspect(reason)` in error responses
3. 7-day JWT expiry (may be too long)
4. No token revocation on logout

---

### Performance (72/100 - C-) ⬆️ IMPROVED

**Improvements Since Last Audit:**
- ✅ Performance indexes added (migration 20260225121000)
- ✅ Status indexes for invoices/contracts
- ✅ ETS used for rate limiting

**Strengths:**
- Most foreign keys have indexes
- Proper use of Ecto preload syntax
- Lightweight assets (HTMX ~45KB)

**Remaining Issues:**
1. Unpaginated lists in HTML controllers
2. Missing composite index for contract sorting
3. No caching for reference data (Banks, KBE/KNP codes)
4. N+1 patterns in nested preloads
5. Leading wildcard searches (`%query%`)

**Recommendations:**
1. Add pagination to all list views
2. Add `invoices[user_id, status]` composite index
3. Implement Cachex for reference data
4. Add trigram index for buyer search

---

### Tests (78/100 - C+) ⬆️ IMPROVED

**Improvements Since Last Audit:**
- ✅ 34 test files (up from 17)
- ✅ Authentication tests added (`auth_controller_test.exs`)
- ✅ Authorization tests added
- ✅ Company tests added (`companies_test.exs`)
- ✅ Acts tests added (`acts_test.exs`)
- ✅ Localization tests (Kazakh/Russian)

**Strengths:**
- Comprehensive authentication & authorization testing
- Strong invoice/contract lifecycle coverage
- Excellent validation testing (BIN/IIN, IBAN)
- Good HTML/HTMX controller testing (7 files)
- Proper rate limiting and security testing
- No flaky tests (zero `Process.sleep`)

**Coverage by Module:**
| Module | Coverage |
|--------|----------|
| Accounts | 90% ✅ |
| Invoicing | 85% ✅ |
| Contracts | 85% ✅ |
| Companies | 85% ✅ |
| Buyers | 80% ✅ |
| Acts | 70% ⚠️ |
| Payments | 75% ⚠️ |
| DocumentDelivery | 85% ✅ |

**Missing Tests:**
- 6 HTML controllers (Invoices, Contracts, Acts, Signup, Session, VerificationPending)
- 5 plugs (Authenticate, AuthenticateSession, SetLocale, HtmxDetect, HtmxLayout)
- No integration test suite
- No property-based tests for calculations

**Iron Law Compliance:**
- ✅ Sandbox isolation
- ✅ No inappropriate mocking
- ✅ No `Process.sleep`
- ⚠️ 14 files missing `async: true` (modify Application env)

---

### Dependencies (78/100 - B-)

**Strengths:**
- No retired packages (hex.audit clean)
- All dependencies actively used (no bloat)
- Permissive licenses (MIT/Apache-2.0)
- Proper classification (runtime/dev)

**Updates Available:**

**Major (Planning Required):**
| Package | Current | Latest | Impact |
|---------|---------|--------|--------|
| phoenix | 1.7.21 | 1.8.5 | Performance, features |
| gettext | 0.26.2 | 1.0.2 | i18n improvements |
| telemetry_metrics | 0.6.2 | 1.1.0 | Metrics system |

**Minor/Patch (Low Risk):**
| Package | Current | Latest |
|---------|---------|--------|
| swoosh | 1.19.9 | 1.23.1 |
| ecto_sql | 3.13.3 | 3.13.5 |
| finch | 0.20.0 | 0.21.0 |
| plug_cowboy | 2.7.5 | 2.8.0 |
| postgrex | 0.21.1 | 0.22.0 |
| tidewave | 0.5.4 | 0.5.5 |

**Recommendations:**
1. Add `mix_audit` for CVE checking
2. Apply patch updates (ecto_sql, tidewave)
3. Plan Phoenix 1.8 upgrade
4. Consider Elixir 1.16+ upgrade

---

## Action Plan

### Immediate (This Sprint)

**Architecture:**
- [ ] Break PDF generation cycles (extract to service)
- [ ] Move queries from `Core.Invoice` schema to Invoicing context

**Security:**
- [ ] Remove JWT secret fallback (enforce ENV var)
- [ ] Sanitize error messages (remove `inspect(reason)`)

**Performance:**
- [ ] Add pagination to invoices/acts controllers
- [ ] Add composite index for contract sorting

**Tests:**
- [ ] Add missing HTML controller tests
- [ ] Add missing plug tests

---

### Short-term (Next 2 Sprints)

**Architecture:**
- [ ] Implement GenServer for document processing
- [ ] Add Oban for background jobs

**Performance:**
- [ ] Install Cachex for reference data caching
- [ ] Add trigram index for buyer search

**Tests:**
- [ ] Add integration test suite
- [ ] Add property-based tests (StreamData)

**Dependencies:**
- [ ] Apply minor/patch updates
- [ ] Add `mix_audit` for security monitoring

---

### Long-term (Backlog)

- [ ] Phoenix 1.8 upgrade
- [ ] Elixir 1.16+ upgrade
- [ ] Microservice boundaries for document generation
- [ ] CQRS implementation for complex domains
- [ ] Token revocation on logout
- [ ] Structured security event logging

---

## Summary

**Current State:** Significant improvements since February audit — security headers added, rate limiting extended, performance indexes created, test coverage doubled (17→34 files). However, architecture debt increased (38 cycles vs 29) and remains the primary concern.

**Focus Areas:**
1. **Architecture first** — Break circular dependencies before they worsen
2. **Security second** — Remove hardcoded JWT secret
3. **Performance third** — Add pagination before data volume grows

**Target Health:** B (80/100) within 2 sprints.

---

**Full Reports:** `.claude/audit/reports/`
- `arch-review.md` — Architecture analysis
- `security-audit.md` — Security vulnerabilities  
- `perf-audit.md` — Performance issues
- `test-audit.md` — Test coverage gaps
- `deps-audit.md` — Dependency health
